import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/security/android_credential_archive.dart';
import '../../../core/security/retained_secure_read.dart';
import 'qishui_signer_defaults.dart';

/// User-owned service configuration. Music-account credentials never belong in
/// this record; the Bearer token authorizes only the selected signing helper.
class QishuiSignerConfig {
  const QishuiSignerConfig._(
    this.baseUri,
    this.accessToken,
    this.accountBoundSigning,
  );

  factory QishuiSignerConfig.parse(
    String address,
    String token, {
    bool accountBoundSigning = false,
  }) {
    final uri = Uri.tryParse(address.trim());
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.port < 1 ||
        uri.port > 65535 ||
        RegExp(r'[\s\\]').hasMatch(address.trim()) ||
        uri.pathSegments.any(
          (part) =>
              part == '.' ||
              part == '..' ||
              part.contains(RegExp(r'[/\\\x00-\x20]')),
        )) {
      throw const FormatException('请填写完整的 HTTP 或 HTTPS 服务地址，不要附带令牌或查询参数');
    }
    // Old records stay anonymous. Account participation is a separate explicit
    // choice, valid only for the user's HTTPS helper, never the public signer.
    if (accountBoundSigning &&
        (uri.scheme != 'https' ||
            uri.host == Uri.parse(qishuiReferenceSignerUrl).host)) {
      throw const FormatException('账号参与签名仅支持自建 HTTPS 服务，请检查地址或关闭此开关');
    }
    final normalizedToken = token.trim().replaceFirst(
      RegExp(r'^Bearer\s+', caseSensitive: false),
      '',
    );
    if (!RegExp(r'^[A-Za-z0-9_-]{43,128}$').hasMatch(normalizedToken)) {
      throw const FormatException('请填写签名助手生成的访问令牌');
    }
    var path = uri.path.replaceAll(RegExp(r'/+$'), '');
    if (path.endsWith('/sign')) path = path.substring(0, path.length - 5);
    return QishuiSignerConfig._(
      uri.replace(path: '$path/'),
      normalizedToken,
      accountBoundSigning,
    );
  }

  final Uri baseUri;
  final String accessToken;
  final bool accountBoundSigning;
  Uri get signUri => baseUri.resolve('sign');
  Uri get configUri => baseUri.resolve('config');

  Map<String, Object> toJson() => {
    'schema': 1,
    'address': baseUri.toString(),
    'accessToken': accessToken,
    'accountBoundSigning': accountBoundSigning,
  };

  factory QishuiSignerConfig.fromJson(Map<String, dynamic> value) {
    if (value['schema'] != 1 ||
        value['address'] is! String ||
        value['accessToken'] is! String ||
        (value.containsKey('accountBoundSigning') &&
            value['accountBoundSigning'] is! bool)) {
      throw const FormatException('签名服务设置无法读取，请重新保存');
    }
    return QishuiSignerConfig.parse(
      value['address'] as String,
      value['accessToken'] as String,
      accountBoundSigning: value['accountBoundSigning'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is QishuiSignerConfig &&
      other.baseUri == baseUri &&
      other.accessToken == accessToken &&
      other.accountBoundSigning == accountBoundSigning;
  @override
  int get hashCode => Object.hash(baseUri, accessToken, accountBoundSigning);
  @override
  String toString() => 'QishuiSignerConfig(<private>)';
}

abstract interface class QishuiSignerSettingsStore {
  Future<QishuiSignerConfig?> read();
  Future<void> write(QishuiSignerConfig config);
}

/// Configuration has its own data, wrapped-key and KeyStore namespace. It
/// never opens or resets a music account's legacy encrypted preferences.
const qishuiSelfHostedSignerAddress =
    'https://download.csnas.asia/qishui-signer/';
const qishuiSignerSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(
    storageNamespace: 'mesting_qishui_signer_v1',
    resetOnError: false,
  ),
);

class QishuiSignerSettingsFailure implements Exception {
  const QishuiSignerSettingsFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Ordinary namespaced configuration reads do not use the account-recovery
/// archive. Independent reopen verification uses the native required key prefix.
class SecureQishuiSignerSettingsStore implements QishuiSignerSettingsStore {
  const SecureQishuiSignerSettingsStore({
    this.storage = qishuiSignerSecureStorage,
    this.android,
  });
  static const key = 'mesting_music_platform_qishui_signer_settings_v1';
  final FlutterSecureStorage storage;
  final bool? android;
  static final _writes = Expando<Future<void>>();
  @override
  Future<QishuiSignerConfig?> read() async {
    try {
      final raw = await readRetainedSecureValue(storage, key);
      return raw == null
          ? null
          : QishuiSignerConfig.fromJson(
              jsonDecode(raw) as Map<String, dynamic>,
            );
    } on Object {
      throw const QishuiSignerSettingsFailure('签名服务设置未能读取，请重试；已保存的资料不会被清除');
    }
  }

  @override
  Future<void> write(QishuiSignerConfig config) async {
    if (_writes[storage] != null) {
      throw const QishuiSignerSettingsFailure('上次保存仍在处理中，请稍后重新读取核对');
    }
    final encoded = jsonEncode(config.toJson());
    final operation = () async {
      await storage.write(key: key, value: encoded);
      if (await readRetainedSecureValue(storage, key) != encoded) {
        throw const QishuiSignerSettingsFailure('签名服务设置保存核对失败，请重新读取核对');
      }
      if (android ?? Platform.isAndroid) {
        await const AndroidCredentialArchive().verifyPrimary(
          key,
          encoded,
          storage.aOptions.toMap(),
        );
      }
    }();
    _writes[storage] = operation;
    // A deadline cannot cancel a native write. Keep a single pending operation
    // until it settles; do not enqueue a second save after an uncertain result.
    unawaited(
      operation.then<void>(
        (_) {
          if (identical(_writes[storage], operation)) _writes[storage] = null;
        },
        onError: (Object _, StackTrace _) {
          if (identical(_writes[storage], operation)) _writes[storage] = null;
        },
      ),
    );
    try {
      await operation.timeout(const Duration(seconds: 15));
    } on Object {
      throw const QishuiSignerSettingsFailure('签名服务设置保存结果未确认，请重新读取核对；不会自动重复保存');
    }
  }
}

final qishuiSignerSettingsStoreProvider = Provider<QishuiSignerSettingsStore>(
  (ref) => const SecureQishuiSignerSettingsStore(),
);
final qishuiSignerSettingsProvider =
    AsyncNotifierProvider<QishuiSignerSettingsController, QishuiSignerConfig?>(
      QishuiSignerSettingsController.new,
      // Native rejections must become an error instead of automatic retries.
      retry: (retryCount, error) => null,
    );

/// The API listens to this synchronous revision, not the encrypted settings
/// loader. Merely visiting another platform must not open the Qishui vault.
class QishuiSignerRevision extends Notifier<int> {
  @override
  int build() => 0;
  void changed() => state++;
}

final qishuiSignerRevisionProvider =
    NotifierProvider<QishuiSignerRevision, int>(QishuiSignerRevision.new);

class QishuiSignerSettingsController
    extends AsyncNotifier<QishuiSignerConfig?> {
  bool _saving = false;
  @override
  Future<QishuiSignerConfig?> build() => ref
      .watch(qishuiSignerSettingsStoreProvider)
      .read()
      .timeout(
        const Duration(seconds: 9),
        onTimeout: () =>
            throw const QishuiSignerSettingsFailure('读取签名服务设置超时，请手动重试'),
      );

  Future<void> save(QishuiSignerConfig config) async {
    if (_saving) throw StateError('签名服务设置正在保存');
    _saving = true;
    try {
      // Publish only after durable encrypted readback. Playback keeps using the
      // last committed configuration if a storage operation fails.
      await ref.read(qishuiSignerSettingsStoreProvider).write(config);
      state = AsyncData(config);
      ref.read(qishuiSignerRevisionProvider.notifier).changed();
    } finally {
      _saving = false;
    }
  }
}
