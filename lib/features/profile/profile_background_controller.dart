import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/persistence/app_preferences.dart';
import '../auth/auth_providers.dart';
import 'data/profile_background_sync_api.dart';

final profileBackgroundDocumentsDirectoryProvider = Provider<Future<Directory>>(
  (ref) => getApplicationDocumentsDirectory(),
);

const profileBackgroundPresetIds = <String>{
  'rose-cloud',
  'midnight',
  'aurora',
  'sunset',
};

enum ProfileBackgroundKind { image, preset }

class ProfileBackgroundState {
  const ProfileBackgroundState({this.accountId, this.kind, this.value});

  final String? accountId;
  final ProfileBackgroundKind? kind;
  final String? value;

  bool get active => accountId != null && kind != null && value != null;
  bool get isImage => kind == ProfileBackgroundKind.image;
  bool get isPreset => kind == ProfileBackgroundKind.preset;

  String? get imagePath => isImage ? value : null;
  String? get presetId => isPreset ? value : null;
}

class ProfileBackgroundException implements Exception {
  const ProfileBackgroundException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ProfileBackgroundController extends Notifier<ProfileBackgroundState> {
  static const _preferencePrefix = 'profile_background_v1';
  static const _cloudPreferencePrefix = 'profile_background_cloud_v1';
  static const _maxBackgroundBytes = 15 * 1024 * 1024;
  String? _reconcilingAccountId;
  int _revision = 0;

  @override
  ProfileBackgroundState build() {
    final accountId = ref.watch(currentUserProvider)?.uid;
    final preferences = ref.watch(sharedPreferencesProvider);
    if (accountId == null || accountId.trim().isEmpty) {
      return const ProfileBackgroundState();
    }

    final kindName = preferences.getString(_kindKey(accountId));
    final value = preferences.getString(_valueKey(accountId))?.trim();
    final kind = ProfileBackgroundKind.values
        .cast<ProfileBackgroundKind?>()
        .firstWhere((item) => item?.name == kindName, orElse: () => null);
    final local = kind == null || value == null || value.isEmpty
        ? ProfileBackgroundState(accountId: accountId)
        : kind == ProfileBackgroundKind.image && !File(value).existsSync()
        ? ProfileBackgroundState(accountId: accountId)
        : kind == ProfileBackgroundKind.preset &&
              !profileBackgroundPresetIds.contains(value)
        ? ProfileBackgroundState(accountId: accountId)
        : ProfileBackgroundState(
            accountId: accountId,
            kind: kind,
            value: value,
          );
    final syncApi = ref.watch(profileBackgroundSyncApiProvider);
    if (syncApi != null && _reconcilingAccountId != accountId) {
      _reconcilingAccountId = accountId;
      final revision = _revision;
      scheduleMicrotask(
        () => _reconcileCloud(accountId, local, syncApi, revision),
      );
    }
    return local;
  }

  Future<void> setImage(String sourcePath) async {
    final accountId = _requireAccountId();
    final validated = await _validateImage(sourcePath);
    final root = await ref.read(profileBackgroundDocumentsDirectoryProvider);
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}profile_backgrounds',
    );
    await directory.create(recursive: true);
    final accountToken = sha256
        .convert(utf8.encode(accountId))
        .toString()
        .substring(0, 16);
    final target = File(
      '${directory.path}${Platform.pathSeparator}'
      'background_${accountToken}_${DateTime.now().millisecondsSinceEpoch}'
      '${validated.extension}',
    );

    try {
      await validated.file.copy(target.path);
    } on Object {
      throw const ProfileBackgroundException('背景图片保存失败，请稍后重试');
    }

    if (ref.read(currentUserProvider)?.uid != accountId) {
      await _deleteIfExists(target);
      throw const ProfileBackgroundException('账号已切换，请重新选择背景图片');
    }

    final previous = state;
    final preferences = ref.read(sharedPreferencesProvider);
    final savedKind = await preferences.setString(
      _kindKey(accountId),
      ProfileBackgroundKind.image.name,
    );
    final savedValue = await preferences.setString(
      _valueKey(accountId),
      target.path,
    );
    if (!savedKind || !savedValue) {
      await _deleteIfExists(target);
      throw const ProfileBackgroundException('背景设置未能保存，请稍后重试');
    }

    state = ProfileBackgroundState(
      accountId: accountId,
      kind: ProfileBackgroundKind.image,
      value: target.path,
    );
    _revision += 1;
    if (previous.isImage && previous.imagePath != target.path) {
      await _deleteManagedImage(previous.imagePath, directory);
    }
    await _syncLocalImage(accountId, target.path);
  }

  Future<void> setPreset(String presetId) async {
    final accountId = _requireAccountId();
    if (!profileBackgroundPresetIds.contains(presetId)) {
      throw const ProfileBackgroundException('所选背景风格不可用，请重新选择');
    }
    final previous = state;
    final preferences = ref.read(sharedPreferencesProvider);
    final savedKind = await preferences.setString(
      _kindKey(accountId),
      ProfileBackgroundKind.preset.name,
    );
    final savedValue = await preferences.setString(
      _valueKey(accountId),
      presetId,
    );
    if (!savedKind || !savedValue) {
      throw const ProfileBackgroundException('背景设置未能保存，请稍后重试');
    }
    state = ProfileBackgroundState(
      accountId: accountId,
      kind: ProfileBackgroundKind.preset,
      value: presetId,
    );
    _revision += 1;
    if (previous.isImage) {
      final root = await ref.read(profileBackgroundDocumentsDirectoryProvider);
      await _deleteManagedImage(
        previous.imagePath,
        Directory('${root.path}${Platform.pathSeparator}profile_backgrounds'),
      );
    }
    await _syncLocalPreset(accountId, presetId);
  }

  Future<void> clear() async {
    final accountId = _requireAccountId();
    final previous = state;
    final syncApi = ref.read(profileBackgroundSyncApiProvider);
    if (syncApi != null) {
      try {
        await syncApi.clear();
      } on ProfileBackgroundSyncException catch (error) {
        throw ProfileBackgroundException(error.message);
      }
    }
    final preferences = ref.read(sharedPreferencesProvider);
    await preferences.remove(_kindKey(accountId));
    await preferences.remove(_valueKey(accountId));
    state = ProfileBackgroundState(accountId: accountId);
    _revision += 1;
    await _rememberCloudBackground(accountId, null);
    if (previous.isImage) {
      final root = await ref.read(profileBackgroundDocumentsDirectoryProvider);
      await _deleteManagedImage(
        previous.imagePath,
        Directory('${root.path}${Platform.pathSeparator}profile_backgrounds'),
      );
    }
  }

  Future<void> _reconcileCloud(
    String accountId,
    ProfileBackgroundState local,
    ProfileBackgroundSyncApi syncApi,
    int revision,
  ) async {
    try {
      final preferences = ref.read(sharedPreferencesProvider);
      if (preferences.getBool(_cloudMigratedKey(accountId)) != true &&
          local.active) {
        if (local.isImage) {
          final remote = await syncApi.saveImage(local.imagePath!);
          if (_revision != revision) return;
          await _rememberCloudBackground(accountId, remote);
        } else {
          final remote = await syncApi.savePreset(local.presetId!);
          if (_revision != revision) return;
          await _rememberCloudBackground(accountId, remote);
        }
        return;
      }

      final remote = await syncApi.load();
      if (ref.read(currentUserProvider)?.uid != accountId ||
          _revision != revision) {
        return;
      }
      if (remote == null) {
        await _applyCloudClear(accountId);
        return;
      }
      final rememberedKind = preferences.getString(_cloudKindKey(accountId));
      final rememberedValue = preferences.getString(_cloudValueKey(accountId));
      if (rememberedKind == remote.kind &&
          rememberedValue == remote.value &&
          local.active) {
        await preferences.setBool(_cloudMigratedKey(accountId), true);
        return;
      }
      await _applyRemoteBackground(accountId, remote, syncApi);
    } on Object {
      // 本机背景继续可用；下次登录或重新进入应用时会再次尝试云端对账。
    } finally {
      if (_reconcilingAccountId == accountId) {
        _reconcilingAccountId = null;
      }
    }
  }

  Future<void> _syncLocalImage(String accountId, String path) async {
    final syncApi = ref.read(profileBackgroundSyncApiProvider);
    if (syncApi == null) return;
    final preferences = ref.read(sharedPreferencesProvider);
    await preferences.setBool(_cloudMigratedKey(accountId), false);
    try {
      final remote = await syncApi.saveImage(path);
      if (ref.read(currentUserProvider)?.uid != accountId) return;
      await _rememberCloudBackground(accountId, remote);
    } on ProfileBackgroundSyncException catch (error) {
      throw ProfileBackgroundException('背景已保存在本机；${error.message}');
    }
  }

  Future<void> _syncLocalPreset(String accountId, String presetId) async {
    final syncApi = ref.read(profileBackgroundSyncApiProvider);
    if (syncApi == null) return;
    final preferences = ref.read(sharedPreferencesProvider);
    await preferences.setBool(_cloudMigratedKey(accountId), false);
    try {
      final remote = await syncApi.savePreset(presetId);
      if (ref.read(currentUserProvider)?.uid != accountId) return;
      await _rememberCloudBackground(accountId, remote);
    } on ProfileBackgroundSyncException catch (error) {
      throw ProfileBackgroundException('背景已保存在本机；${error.message}');
    }
  }

  Future<void> _applyRemoteBackground(
    String accountId,
    CloudProfileBackground remote,
    ProfileBackgroundSyncApi syncApi,
  ) async {
    if (remote.kind == ProfileBackgroundKind.preset.name) {
      if (!profileBackgroundPresetIds.contains(remote.value)) return;
      await _persistRemoteState(
        accountId,
        kind: ProfileBackgroundKind.preset,
        value: remote.value,
      );
      await _rememberCloudBackground(accountId, remote);
      return;
    }
    if (remote.kind != ProfileBackgroundKind.image.name ||
        remote.downloadUrl == null) {
      return;
    }

    final bytes = await syncApi.downloadImage(remote.downloadUrl!);
    final root = await ref.read(profileBackgroundDocumentsDirectoryProvider);
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}profile_backgrounds',
    );
    await directory.create(recursive: true);
    final temporary = File(
      '${directory.path}${Platform.pathSeparator}'
      'background_cloud_${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await temporary.writeAsBytes(bytes, flush: true);
    try {
      final validated = await _validateImage(temporary.path);
      final accountToken = sha256
          .convert(utf8.encode(accountId))
          .toString()
          .substring(0, 16);
      final target = File(
        '${directory.path}${Platform.pathSeparator}'
        'background_${accountToken}_${DateTime.now().millisecondsSinceEpoch}'
        '${validated.extension}',
      );
      await temporary.rename(target.path);
      await _persistRemoteState(
        accountId,
        kind: ProfileBackgroundKind.image,
        value: target.path,
      );
      await _rememberCloudBackground(accountId, remote);
    } finally {
      await _deleteIfExists(temporary);
    }
  }

  Future<void> _persistRemoteState(
    String accountId, {
    required ProfileBackgroundKind kind,
    required String value,
  }) async {
    if (ref.read(currentUserProvider)?.uid != accountId) return;
    final previous = state;
    final preferences = ref.read(sharedPreferencesProvider);
    await preferences.setString(_kindKey(accountId), kind.name);
    await preferences.setString(_valueKey(accountId), value);
    state = ProfileBackgroundState(
      accountId: accountId,
      kind: kind,
      value: value,
    );
    _revision += 1;
    if (previous.isImage && previous.imagePath != value) {
      final root = await ref.read(profileBackgroundDocumentsDirectoryProvider);
      await _deleteManagedImage(
        previous.imagePath,
        Directory('${root.path}${Platform.pathSeparator}profile_backgrounds'),
      );
    }
  }

  Future<void> _applyCloudClear(String accountId) async {
    if (ref.read(currentUserProvider)?.uid != accountId) return;
    final previous = state;
    final preferences = ref.read(sharedPreferencesProvider);
    await preferences.remove(_kindKey(accountId));
    await preferences.remove(_valueKey(accountId));
    state = ProfileBackgroundState(accountId: accountId);
    _revision += 1;
    await _rememberCloudBackground(accountId, null);
    if (previous.isImage) {
      final root = await ref.read(profileBackgroundDocumentsDirectoryProvider);
      await _deleteManagedImage(
        previous.imagePath,
        Directory('${root.path}${Platform.pathSeparator}profile_backgrounds'),
      );
    }
  }

  Future<void> _rememberCloudBackground(
    String accountId,
    CloudProfileBackground? remote,
  ) async {
    final preferences = ref.read(sharedPreferencesProvider);
    if (remote == null) {
      await preferences.remove(_cloudKindKey(accountId));
      await preferences.remove(_cloudValueKey(accountId));
    } else {
      await preferences.setString(_cloudKindKey(accountId), remote.kind);
      await preferences.setString(_cloudValueKey(accountId), remote.value);
    }
    await preferences.setBool(_cloudMigratedKey(accountId), true);
  }

  String _requireAccountId() {
    final accountId = ref.read(currentUserProvider)?.uid;
    if (accountId == null || accountId.trim().isEmpty) {
      throw const ProfileBackgroundException('登录后才能设置个人主页背景');
    }
    return accountId;
  }

  Future<_ValidatedBackgroundImage> _validateImage(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const ProfileBackgroundException('选择的背景图片已不存在，请重新选择');
    }
    final length = await file.length();
    if (length <= 0) {
      throw const ProfileBackgroundException('背景图片为空，请重新选择');
    }
    if (length > _maxBackgroundBytes) {
      throw const ProfileBackgroundException('背景图片不能超过 15 MB');
    }
    final input = await file.open();
    late final List<int> header;
    try {
      header = await input.read(12);
    } finally {
      await input.close();
    }
    if (_startsWith(header, const [0xFF, 0xD8, 0xFF])) {
      return _ValidatedBackgroundImage(file: file, extension: '.jpg');
    }
    if (_startsWith(header, const [
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ])) {
      return _ValidatedBackgroundImage(file: file, extension: '.png');
    }
    if (header.length >= 12 &&
        String.fromCharCodes(header.take(4)) == 'RIFF' &&
        String.fromCharCodes(header.skip(8).take(4)) == 'WEBP') {
      return _ValidatedBackgroundImage(file: file, extension: '.webp');
    }
    throw const ProfileBackgroundException('仅支持真实的 JPG、PNG 或 WebP 图片');
  }

  Future<void> _deleteManagedImage(String? path, Directory directory) async {
    if (path == null) return;
    final file = File(path);
    if (file.parent.absolute.path != directory.absolute.path) return;
    await _deleteIfExists(file);
  }

  Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on Object {
      // 背景已经切换成功；旧缓存清理失败不应阻断用户操作。
    }
  }

  String _kindKey(String accountId) =>
      '${_preferencePrefix}_${_accountPreferenceToken(accountId)}_kind';

  String _valueKey(String accountId) =>
      '${_preferencePrefix}_${_accountPreferenceToken(accountId)}_value';

  String _cloudKindKey(String accountId) =>
      '${_cloudPreferencePrefix}_${_accountPreferenceToken(accountId)}_kind';

  String _cloudValueKey(String accountId) =>
      '${_cloudPreferencePrefix}_${_accountPreferenceToken(accountId)}_value';

  String _cloudMigratedKey(String accountId) =>
      '${_cloudPreferencePrefix}_${_accountPreferenceToken(accountId)}_ready';

  String _accountPreferenceToken(String accountId) =>
      base64Url.encode(utf8.encode(accountId)).replaceAll('=', '');
}

final profileBackgroundSyncApiProvider = Provider<ProfileBackgroundSyncApi?>((
  ref,
) {
  if (ref.watch(authBackendKindProvider) != AuthBackendKind.cloudBase ||
      ref.watch(currentUserProvider) == null) {
    return null;
  }
  return CloudBaseProfileBackgroundSyncApi(
    environmentId: cloudBaseEnvironmentId,
    sessionProvider: () =>
        ref.read(authControllerProvider.notifier).ensureFreshSession(),
  );
});

class _ValidatedBackgroundImage {
  const _ValidatedBackgroundImage({
    required this.file,
    required this.extension,
  });

  final File file;
  final String extension;
}

bool _startsWith(List<int> value, List<int> prefix) {
  if (value.length < prefix.length) return false;
  for (var index = 0; index < prefix.length; index += 1) {
    if (value[index] != prefix[index]) return false;
  }
  return true;
}

final profileBackgroundProvider =
    NotifierProvider<ProfileBackgroundController, ProfileBackgroundState>(
      ProfileBackgroundController.new,
    );
