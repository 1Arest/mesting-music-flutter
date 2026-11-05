import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ring_download_sdk/src/core/services/app_upgrade_cache_verifier.dart';
import 'package:ring_download_sdk/src/core/services/app_upgrade_p2p_protocol.dart';

void main() {
  late Directory directory;
  late File file;
  late Uint8List bytes;
  late AppUpgradeCacheVerifier owner;
  AppUpgradeP2PManifest manifest({List<String>? pieceHashes}) =>
      AppUpgradeP2PManifest(
        fileSize: bytes.length,
        sha256: sha256.convert(bytes).toString(),
        pieceHashes:
            pieceHashes ??
            [
              for (var start = 0; start < bytes.length; start += 1048576)
                sha256
                    .convert(
                      bytes.sublist(
                        start,
                        (start + 1048576).clamp(0, bytes.length),
                      ),
                    )
                    .toString(),
            ],
        stunUrls: [],
        apiBase: '',
        serverSeedUrl: '',
      );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ring-cache-verifier-');
    file = File('${directory.path}/authorized.apk');
    bytes = Uint8List.fromList(List.generate(1048576 + 731, (i) => i % 251));
    await file.writeAsBytes(bytes, flush: true);
    owner = AppUpgradeCacheVerifier();
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'one isolate scan checks full identity and every piece and releases file',
    () async {
      await owner.verify(file, manifest());
      expect(owner.scans, 1);
      await file.rename('${directory.path}/moved.apk');
    },
  );
  test(
    'concurrent same-file restorations serialize and reuse one valid receipt',
    () async {
      await Future.wait([
        owner.verify(file, manifest()),
        owner.verify(file, manifest()),
      ]);
      expect(owner.scans, 1);
      expect(owner.reused, 1);
    },
  );
  test(
    'changed file stamp invalidates receipt even at the same path and size',
    () async {
      final identity = manifest();
      await owner.verify(file, identity);
      final corrupt = Uint8List.fromList(bytes)..[0] ^= 1;
      await file.writeAsBytes(corrupt, flush: true);
      await file.setLastModified(
        DateTime.now().add(const Duration(seconds: 2)),
      );
      await expectLater(
        owner.verify(file, identity),
        throwsA(
          isA<AppUpgradeP2PFailure>().having(
            (e) => e.code,
            'code',
            'file_checksum_mismatch',
          ),
        ),
      );
      expect(owner.scans, 2);
      expect(await file.readAsBytes(), corrupt);
    },
  );
  test(
    'piece identity cannot reuse a matching full-file receipt or truncate file',
    () async {
      await owner.verify(file, manifest());
      await expectLater(
        owner.verify(file, manifest(pieceHashes: ['0' * 64, '0' * 64])),
        throwsA(
          isA<AppUpgradeP2PFailure>().having(
            (e) => e.code,
            'code',
            'piece_checksum_mismatch',
          ),
        ),
      );
      expect(owner.scans, 2);
      expect(await file.readAsBytes(), bytes);
    },
  );
}
