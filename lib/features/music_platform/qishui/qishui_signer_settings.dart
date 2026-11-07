import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/security/retained_credential_vault.dart';
import '../../../core/security/retained_secure_storage.dart';

/// User-owned service configuration. Music-account credentials never belong in
/// this record; the Bearer token authorizes only the selected signing helper.
class QishuiSignerConfig {
  const QishuiSignerConfig._(this.baseUri, this.accessToken);

  factory QishuiSignerConfig.parse(String address, String token) {
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
    final normalizedToken = token.trim().replaceFirst(
      RegExp(r'^Bearer\s+', caseSensitive: false),
      '',
    );
    if (!RegExp(r'^[A-Za-z0-9_-]{43,128}$').hasMatch(normalizedToken)) {
      throw const FormatException('请填写签名助手生成的访问令牌');
    }
    var path = uri.path.replaceAll(RegExp(r'/+$'), '');
    if (path.endsWith('/sign')) path = path.substring(0, path.length - 5);
    return QishuiSignerConfig._(uri.replace(path: '$path/'), normalizedToken);
  }

  final Uri baseUri;
  final String accessToken;
  Uri get signUri => baseUri.resolve('sign');
  Uri get configUri => baseUri.resolve('config');

  Map<String, Object> toJson() => {
    'schema': 1,
    'address': baseUri.toString(),
    'accessToken': accessToken,
  };

  factory QishuiSignerConfig.fromJson(Map<String, dynamic> value) {
    if (value['schema'] != 1 ||
        value['address'] is! String ||
        value['accessToken'] is! String) {
      throw const FormatException('签名服务设置无法读取，请重新保存');
    }
    return QishuiSignerConfig.parse(
      value['address'] as String,
      value['accessToken'] as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is QishuiSignerConfig &&
      other.baseUri == baseUri &&
      other.accessToken == accessToken;
  @override
  int get hashCode => Object.hash(baseUri, accessToken);
  @override
  String toString() => 'QishuiSignerConfig(<private>)';
}

abstract interface class QishuiSignerSettingsStore {
  Future<QishuiSignerConfig?> read();
  Future<void> write(QishuiSignerConfig config);
}

/// Reuses the verified encrypted vault, in a separate namespace. Failed reads
/// propagate and never masquerade as an empty setting or a public fallback.
class SecureQishuiSignerSettingsStore implements QishuiSignerSettingsStore {
  const SecureQishuiSignerSettingsStore({this.storage = retainedSecureStorage});
  static const key = 'mesting_qishui_signer_settings_v1';
  final FlutterSecureStorage storage;
  RetainedCredentialVault get _vault => RetainedCredentialVault(storage);
  @override
  Future<QishuiSignerConfig?> read() async {
    final raw = await _vault.read(key);
    return raw == null
        ? null
        : _vault.decode(
            key,
            () => QishuiSignerConfig.fromJson(
              jsonDecode(raw) as Map<String, dynamic>,
            ),
          );
  }

  @override
  Future<void> write(QishuiSignerConfig config) =>
      _vault.write(key, jsonEncode(config.toJson()));
}

final qishuiSignerSettingsStoreProvider = Provider<QishuiSignerSettingsStore>(
  (ref) => const SecureQishuiSignerSettingsStore(),
);
final qishuiSignerSettingsProvider =
    AsyncNotifierProvider<QishuiSignerSettingsController, QishuiSignerConfig?>(
      QishuiSignerSettingsController.new,
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
  Future<QishuiSignerConfig?> build() =>
      ref.watch(qishuiSignerSettingsStoreProvider).read();

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
