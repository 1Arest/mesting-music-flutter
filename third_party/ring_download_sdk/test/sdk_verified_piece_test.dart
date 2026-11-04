import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ring_download_sdk/compat.dart';

void main() {
  late Directory directory;
  late Uint8List payload;
  late AppUpgradeP2PManifest manifest;
  late AppUpgradeP2PPieceStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sdk-owned-piece-');
    payload = Uint8List.fromList(List.generate(1024, (index) => index % 251));
    manifest = AppUpgradeP2PManifest(
      fileSize: payload.length,
      sha256: sha256.convert(payload).toString(),
      pieceHashes: [sha256.convert(payload).toString()],
      stunUrls: const ['stun:example.test:3479'],
      apiBase: 'https://download1.csnas.asia/api/app/lifering/p2p',
      serverSeedUrl:
          'https://download1.csnas.asia/api/app/lifering/p2p/server-offer',
    );
    store = AppUpgradeP2PPieceStore(
      File('${directory.path}/result.apk'),
      manifest,
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'receiver to writer hashes once and final file still gets full SHA',
    () async {
      final receiver = AppUpgradeP2PPieceReceiver(store, 0);
      receiver.start({'index': 0, 'size': payload.length});
      receiver.add(payload);
      final verified = receiver.end({'index': 0});
      await store.append(0, 0, verified);
      expect(store.metrics['piece_verify_calls'], 1);
      expect(store.metrics['piece_verify_reused'], 1);
      expect(await store.completeAndVerified(), true);
      expect(store.metrics['full_sha_scans'], 1);
    },
  );

  test('caller mutation cannot alter verified owned bytes', () async {
    final expected = Uint8List.fromList(payload);
    final verified = store.verifyOwnedPiece(0, payload);
    payload[0] ^= 255;
    await store.append(0, 0, verified);
    expect(await store.file.readAsBytes(), expected);
    expect(await store.completeAndVerified(), true);
  });

  test('typed list buffer and byte-data mutation paths stay read only', () {
    final verified = store.verifyOwnedPiece(0, payload);
    expect(() => verified[0] = 9, throwsUnsupportedError);
    expect(() => verified.buffer.asUint8List()[0] = 9, throwsUnsupportedError);
    expect(
      () => verified.buffer.asByteData().setUint8(0, 9),
      throwsUnsupportedError,
    );
    expect(
      () => Uint8List.sublistView(verified)[0] = 9,
      throwsUnsupportedError,
    );
  });

  test(
    'untrusted append snapshots bytes before asynchronous file work',
    () async {
      final expected = Uint8List.fromList(payload);
      final writing = store.append(0, 0, payload);
      payload[0] ^= 255;
      await writing;
      expect(await store.file.readAsBytes(), expected);
      expect(await store.completeAndVerified(), true);
    },
  );

  test('payload from another store is independently verified', () async {
    final verified = store.verifyOwnedPiece(0, payload);
    final other = AppUpgradeP2PPieceStore(
      File('${directory.path}/other.apk'),
      manifest,
    );
    await other.append(0, 0, verified);
    expect(other.metrics['piece_verify_calls'], 1);
    await other.close();
  });

  test('changed manifest hashes cannot reuse an old receipt', () async {
    final verified = store.verifyOwnedPiece(0, payload);
    manifest.pieceHashes[0] = '0' * 64;
    await expectLater(
      store.append(0, 0, verified),
      throwsA(isA<AppUpgradeP2PFailure>()),
    );
    expect(store.file.existsSync(), false);
  });

  test(
    'disk changes are found by the retained whole-file verification',
    () async {
      await store.append(0, 0, store.verifyOwnedPiece(0, payload));
      final changed = Uint8List.fromList(payload)..[0] ^= 255;
      await store.file.writeAsBytes(changed);
      expect(await store.completeAndVerified(), false);
    },
  );

  test('corrupt and truncated untrusted pieces are never written', () async {
    final changed = Uint8List.fromList(payload)..[0] ^= 255;
    await expectLater(
      store.append(0, 0, changed),
      throwsA(isA<AppUpgradeP2PFailure>()),
    );
    await expectLater(
      store.append(0, 0, Uint8List(1)),
      throwsA(isA<AppUpgradeP2PFailure>()),
    );
    expect(store.file.existsSync(), false);
  });
}
