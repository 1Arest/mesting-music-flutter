import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../network/music_network_diagnostics.dart';
import 'credential_failure.dart';
import 'retained_secure_read.dart';
import 'retained_secure_storage.dart';

/// Recovery has separate data, wrapped keys, configuration and KeyStore aliases.
/// It is used only after an explicit, platform-verified login. Existing encrypted
/// bytes are never reset, overwritten or interpreted as an empty account list.
const retainedRecoveryStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(
    resetOnError: false,
    storageNamespace: 'mesting_verified_recovery_v1',
  ),
);

class CredentialRecoveryWrite {
  const CredentialRecoveryWrite(this.rollback);
  final Future<void> Function() rollback;
}

class RetainedCredentialVault {
  static final _vaults =
      Expando<Map<FlutterSecureStorage?, RetainedCredentialVault>>();
  factory RetainedCredentialVault(
    FlutterSecureStorage primary, {
    FlutterSecureStorage? recovery,
  }) {
    final effective =
        recovery ??
        (!kIsWeb &&
                Platform.isAndroid &&
                identical(primary, retainedSecureStorage)
            ? retainedRecoveryStorage
            : null);
    return (_vaults[primary] ??= {}).putIfAbsent(
      effective,
      () => RetainedCredentialVault._(primary, effective),
    );
  }
  RetainedCredentialVault._(this.primary, this.recovery);
  final FlutterSecureStorage primary;
  final FlutterSecureStorage? recovery;
  final Set<String> _checked = {}, _active = {};
  final Map<String, String?> _recoveryValues = {};

  String _platform(String key) => key.contains('netease') ? 'netease' : 'kugou';

  Future<String?> _rawRead(FlutterSecureStorage storage, String key) =>
      credentialStep(
        platform: _platform(key),
        phase: MusicDiagnosticPhase.storageRead,
        run: () => readRetainedSecureValue(storage, key),
      );

  Future<String?> read(String key) async {
    final backup = recovery;
    if (backup != null && !_checked.contains(key)) {
      final raw = await _rawRead(backup, key);
      _recoveryValues[key] = raw;
      _checked.add(key);
      if (raw != null) _active.add(key);
    }
    if (_active.contains(key)) {
      return credentialStep(
        platform: _platform(key),
        phase: MusicDiagnosticPhase.storageDecode,
        run: () async {
          final envelope = jsonDecode(_recoveryValues[key]!);
          if (envelope is! Map ||
              envelope['schema'] != 1 ||
              envelope['value'] != null && envelope['value'] is! String) {
            throw const FormatException('Invalid recovery envelope');
          }
          return envelope['value'] as String?;
        },
      );
    }
    return _rawRead(primary, key);
  }

  Future<T> decode<T>(String key, T Function() decode) => credentialStep(
    platform: _platform(key),
    phase: MusicDiagnosticPhase.storageDecode,
    run: () async => decode(),
  );

  Future<void> _commit(
    FlutterSecureStorage storage,
    String key,
    String value, {
    bool isRecovery = false,
  }) async {
    await credentialStep(
      platform: _platform(key),
      phase: isRecovery
          ? MusicDiagnosticPhase.recoveryWrite
          : MusicDiagnosticPhase.storageWrite,
      run: () => storage.write(key: key, value: value),
    );
    await credentialStep(
      platform: _platform(key),
      phase: MusicDiagnosticPhase.storageVerify,
      run: () async {
        if (await readRetainedSecureValue(storage, key) != value) {
          throw const CredentialStoreException(
            MusicDiagnosticPhase.storageVerify,
            MusicFailureFamily.io,
          );
        }
      },
    );
  }

  Future<void> write(String key, String value) async {
    if (_active.contains(key)) {
      final envelope = jsonEncode({'schema': 1, 'value': value});
      await _commit(recovery!, key, envelope, isRecovery: true);
      _recoveryValues[key] = envelope;
    } else {
      // A failed local write must not discard a readable previous account.
      // Unknown/failed reads are not treated as empty and never overwritten.
      final previous = await _rawRead(primary, key);
      try {
        await _commit(primary, key, value);
      } on Object {
        if (previous != null) {
          try {
            await _commit(primary, key, previous);
          } on Object {
            // Preserve the original failure. Native committed preferences are
            // journaled; no delete/reset is attempted on an uncertain write.
          }
        }
        rethrow;
      }
    }
  }

  /// Only a verified login may create this overlay. Rollback touches solely the
  /// newly created recovery entry, leaving every legacy key/account unchanged.
  Future<CredentialRecoveryWrite> recover(String key, String value) async {
    final backup = recovery;
    if (backup == null) {
      // Injectable stores retain their original contract in non-Android tests.
      await write(key, value);
      return CredentialRecoveryWrite(() async {});
    }
    final previous = await _rawRead(backup, key);
    final envelope = jsonEncode({'schema': 1, 'value': value});
    await _commit(backup, key, envelope, isRecovery: true);
    _checked.add(key);
    _active.add(key);
    _recoveryValues[key] = envelope;
    return CredentialRecoveryWrite(() async {
      if (previous == null) {
        await backup.delete(key: key);
        _active.remove(key);
      } else {
        await _commit(backup, key, previous, isRecovery: true);
      }
      _recoveryValues[key] = previous;
    });
  }

  Future<void> clear(String key) async {
    if (_active.contains(key)) {
      // A tombstone prevents old retained credentials resurfacing after logout.
      final envelope = jsonEncode({'schema': 1, 'value': null});
      await _commit(recovery!, key, envelope, isRecovery: true);
      _recoveryValues[key] = envelope;
    } else {
      await credentialStep(
        platform: _platform(key),
        phase: MusicDiagnosticPhase.storageWrite,
        run: () => primary.delete(key: key),
      );
    }
  }
}
