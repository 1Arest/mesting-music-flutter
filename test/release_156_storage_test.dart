import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/security/android_credential_archive.dart';
import 'package:mesting_music/core/security/retained_credential_vault.dart';
import 'package:mesting_music/core/security/credential_failure.dart';
import 'support/release_155_storage_fixture.dart';
import 'release_155_storage_test.dart' as previous;
import 'package:mesting_music/features/music_platform/data/kugou_account_store.dart';
import 'package:mesting_music/features/music_platform/netease/netease_session.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';

/// Model the boundary omitted by the earlier tests: both old keys may fail,
/// while a new verified login must save without reading either of them first.
class _Archive extends AndroidCredentialArchive {
  final values = <String, String>{};
  bool unreadable = false, rejectReopen = false;
  int reads = 0, replacements = 0, primaryVerifications = 0;
  String? previous;
  @override
  Future<String?> read(String key) async {
    reads++;
    if (unreadable && values.containsKey(key)) {
      throw PlatformException(
        code: 'mesting_storage',
        details: {'family': 'keyInvalidated'},
      );
    }
    return values[key];
  }

  @override
  Future<Map<String, String?>> replace(String key, String envelope) async {
    replacements++;
    if (rejectReopen) {
      throw PlatformException(
        code: 'mesting_storage',
        details: {'family': 'keyInvalidated'},
      );
    }
    previous = values[key];
    values[key] = envelope;
    unreadable = false;
    return {'generation': 'synthetic-slot', 'previous': 'opaque-previous'};
  }

  @override
  Future<void> rollback(String key, Map<String, String?> receipt) async {
    if (previous == null) {
      values.remove(key);
    } else {
      values[key] = previous!;
    }
  }

  @override
  Future<void> write(String key, String envelope) async {
    values[key] = envelope;
  }

  @override
  Future<void> verifyPrimary(
    String key,
    String expected,
    Map<String, String> options,
  ) async {
    primaryVerifications++;
    if (rejectReopen) {
      throw PlatformException(
        code: 'mesting_storage',
        details: {'family': 'keyInvalidated'},
      );
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = 'mesting_music_platform_netease_session_v1';

  test(
    'NetEase restore failure does not replace a healthy multi-account Kugou store',
    () async {
      final primary = Storage155();
      await previous.seed155(primary);
      const second = PlatformSession(userId: '1563', token: 'synthetic-other');
      await SecureKugouAccountStore(storage: primary).write(second);
      primary.values[SecureNeteaseSessionStore.key] =
          'synthetic-malformed-json';
      final recovery = Storage155();
      final scope = await previous.accounts155(
        primary,
        recovery,
        choice: 'netease',
      );
      await expectLater(
        scope.read(platformAccountProvider.future),
        throwsA(isA<CredentialStoreException>()),
      );
      await scope
          .read(platformAccountProvider.notifier)
          .accept(previous.kugou155.toJson());
      expect(recovery.values, isEmpty);
      final accounts = await SecureKugouAccountStore(
        storage: primary,
      ).snapshot();
      expect(
        accounts.accounts.map((a) => a.userId),
        containsAll([previous.kugou155.userId, second.userId]),
      );
    },
  );

  test(
    'Kugou restore failure leaves a healthy NetEase login on its original store',
    () async {
      final primary = Storage155();
      await previous.seed155(primary);
      primary.values[SecureKugouAccountStore.key] = 'synthetic-malformed-json';
      final recovery = Storage155();
      final scope = await previous.accounts155(primary, recovery);
      await expectLater(
        scope.read(platformAccountProvider.future),
        throwsA(isA<CredentialStoreException>()),
      );
      await scope
          .read(platformAccountProvider.notifier)
          .acceptNetease(previous.netease155);
      expect(recovery.values, isEmpty);
      expect(
        (await SecureNeteaseSessionStore(storage: primary).read())?.userId,
        previous.netease155.userId,
      );
    },
  );

  test(
    'empty archive with broken old key leaves the 50/51 primary path usable',
    () async {
      final primary = Storage155({key: 'old-readable-login'});
      final archive = _Archive()..unreadable = true;
      final vault = RetainedCredentialVault(primary, archive: archive);
      expect(await vault.read(key), 'old-readable-login');
      expect(primary.writes, 0);
      expect(archive.replacements, 0);
      await vault.write(key, 'updated-login');
      expect(primary.values[key], 'updated-login');
      expect(archive.primaryVerifications, 1);
      expect(archive.values, isEmpty);
    },
  );

  test(
    'two unreadable old stores cannot block a verified replacement or require data clear',
    () async {
      final primary = Storage155({key: 'opaque-legacy'})
        ..readFailures[key] = 'keyInvalidated';
      final archive = _Archive()
        ..values[key] = 'opaque-archive'
        ..unreadable = true;
      final vault = RetainedCredentialVault(primary, archive: archive);
      await expectLater(
        vault.read(key),
        throwsA(isA<CredentialStoreException>()),
      );
      final reads = archive.reads;
      await vault.recover(key, 'verified-new-login');
      expect(
        archive.reads,
        reads,
        reason: 'replacement must not read a failed old key',
      );
      expect(primary.values[key], 'opaque-legacy');
      expect(primary.writes, 0);
      expect(primary.deletes, 0);
      final restarted = RetainedCredentialVault(
        Storage155(primary.values),
        archive: archive,
      );
      expect(await restarted.read(key), 'verified-new-login');
    },
  );

  test(
    'reopen failure leaves the old pointer and credentials untouched',
    () async {
      final primary = Storage155({key: 'old'});
      final archive = _Archive()..rejectReopen = true;
      final vault = RetainedCredentialVault(primary, archive: archive);
      await expectLater(
        vault.recover(key, 'new'),
        throwsA(isA<CredentialStoreException>()),
      );
      expect(archive.values, isEmpty);
      expect(primary.values[key], 'old');
    },
  );

  test(
    'existing 54/55 envelope and logout tombstone remain authoritative',
    () async {
      final primary = Storage155({key: 'obsolete'});
      final archive = _Archive()
        ..values[key] = jsonEncode({'schema': 1, 'value': 'current'});
      final vault = RetainedCredentialVault(primary, archive: archive);
      expect(await vault.read(key), 'current');
      await vault.clear(key);
      expect(
        await RetainedCredentialVault(
          Storage155(primary.values),
          archive: archive,
        ).read(key),
        isNull,
      );
      expect(primary.values[key], 'obsolete');
    },
  );

  test(
    'first write resolves an existing archive instead of shadowing it in legacy',
    () async {
      final primary = Storage155({key: 'obsolete'});
      final archive = _Archive()
        ..values[key] = jsonEncode({'schema': 1, 'value': 'current'});
      await RetainedCredentialVault(
        primary,
        archive: archive,
      ).write(key, 'updated');
      expect(primary.values[key], 'obsolete');
      expect(primary.writes, 0);
      expect(jsonDecode(archive.values[key]!)['value'], 'updated');
    },
  );

  test('cancelled local publication rolls back the opaque pointer', () async {
    final primary = Storage155({key: 'old'});
    final archive = _Archive();
    final vault = RetainedCredentialVault(primary, archive: archive);
    expect(await vault.read(key), 'old');
    final receipt = await vault.recover(key, 'new');
    await receipt.rollback();
    expect(await vault.read(key), 'old');
    expect(archive.values, isEmpty);
  });
}
