import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../network/music_network_diagnostics.dart';
import 'credential_failure.dart';
import 'retained_secure_read.dart';
import 'retained_secure_storage.dart';
import 'android_credential_archive.dart';

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
  static final _vaults = Expando<Map<Object?, RetainedCredentialVault>>();
  factory RetainedCredentialVault(
    FlutterSecureStorage primary, {
    FlutterSecureStorage? recovery,
    AndroidCredentialArchive? archive,
  }) {
    final nativeArchive =
        archive ??
        (recovery == null &&
                !kIsWeb &&
                Platform.isAndroid &&
                identical(primary, retainedSecureStorage)
            ? const AndroidCredentialArchive()
            : null);
    final effective =
        recovery ??
        (nativeArchive == null &&
                !kIsWeb &&
                Platform.isAndroid &&
                identical(primary, retainedSecureStorage)
            ? retainedRecoveryStorage
            : null);
    return (_vaults[primary] ??= {}).putIfAbsent(
      nativeArchive ?? effective,
      () => RetainedCredentialVault._(primary, effective, nativeArchive),
    );
  }
  RetainedCredentialVault._(this.primary, this.recovery, this.archive);
  final FlutterSecureStorage primary;
  final FlutterSecureStorage? recovery;
  final AndroidCredentialArchive? archive;
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
    if ((backup != null || archive != null) && !_checked.contains(key)) {
      // Production Android checks raw entry presence before touching a cipher.
      // No entry means the original 50/51 read path, even if the unused archive
      // has an invalid key. Existing 54/55 overlays and logout tombstones remain
      // authoritative; unreadable entries are never mistaken for an empty slot.
      final raw = archive != null
          ? await credentialStep(
              platform: _platform(key),
              phase: MusicDiagnosticPhase.storageRead,
              run: () => archive!.read(key),
            )
          : await _rawRead(backup!, key);
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
        if (archive != null && identical(storage, primary)) {
          // A same-instance read may reuse an AES key whose RSA private key is
          // already unusable. Reopen from persisted wrapped bytes before a
          // controller is allowed to publish a successful login.
          await archive!.verifyPrimary(key, value, primary.aOptions.toMap());
        }
      },
    );
  }

  Future<void> write(String key, String value) async {
    // Resolve the actual owner before the first write to a different platform.
    // Otherwise a retained archive could be shadowed by a write to legacy data.
    final previous = await read(key);
    if (_active.contains(key)) {
      final envelope = jsonEncode({'schema': 1, 'value': value});
      await _writeArchive(key, envelope);
      _recoveryValues[key] = envelope;
    } else {
      // A failed local write must not discard a readable previous account.
      // Unknown/failed reads are not treated as empty and never overwritten.
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
    if (archive != null) {
      // A fresh verified login must never read either failed old cipher first.
      // Its receipt can restore the previous pointer without decrypting it.
      final oldChecked = _checked.contains(key);
      final oldActive = _active.contains(key);
      final oldCached = _recoveryValues[key];
      final envelope = jsonEncode({'schema': 1, 'value': value});
      final receipt = await credentialStep(
        platform: _platform(key),
        phase: MusicDiagnosticPhase.recoveryWrite,
        run: () => archive!.replace(key, envelope),
      );
      _checked.add(key);
      _active.add(key);
      _recoveryValues[key] = envelope;
      return CredentialRecoveryWrite(() async {
        await archive!.rollback(key, receipt);
        if (!oldChecked) _checked.remove(key);
        if (!oldActive) _active.remove(key);
        if (oldCached == null) {
          _recoveryValues.remove(key);
        } else {
          _recoveryValues[key] = oldCached;
        }
      });
    }
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
    await read(key);
    if (_active.contains(key)) {
      // A tombstone prevents old retained credentials resurfacing after logout.
      final envelope = jsonEncode({'schema': 1, 'value': null});
      await _writeArchive(key, envelope);
      _recoveryValues[key] = envelope;
    } else {
      await credentialStep(
        platform: _platform(key),
        phase: MusicDiagnosticPhase.storageWrite,
        run: () => primary.delete(key: key),
      );
    }
  }

  Future<void> _writeArchive(String key, String envelope) async {
    if (archive == null) {
      await _commit(recovery!, key, envelope, isRecovery: true);
      return;
    }
    await credentialStep(
      platform: _platform(key),
      phase: MusicDiagnosticPhase.storageWrite,
      run: () => archive!.write(key, envelope),
    );
  }
}
