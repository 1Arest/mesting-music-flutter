import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ring_download_sdk/src/p8p/window.dart';
import 'package:ring_download_sdk/src/core/services/app_upgrade_p2p_protocol.dart';
import 'package:ring_download_sdk/src/core/services/app_upgrade_p2p_piece_receiver.dart';
import 'package:ring_download_sdk/src/core/services/app_upgrade_p2p_piece_store.dart';

void main() {
  test(
    'P8P cancellation fails queued pieces without issuing replacement work',
    () async {
      final root = await Directory.systemTemp.createTemp('p8p-cancel-');
      final manifest = AppUpgradeP2PManifest(
        fileSize: 4 * 1048576,
        sha256: 'a' * 64,
        pieceHashes: List.filled(4, 'b' * 64),
        stunUrls: const [],
        apiBase: '/unused',
        serverSeedUrl: 'https://example.test',
      );
      final store = AppUpgradeP2PPieceStore(
        File('${root.path}/part'),
        manifest,
      );
      final entered = Completer<void>();
      final requests = <int>[];
      final receiver = AppUpgradeP2PWindowReceiver(store, [0, 1, 2, 3], (
        indices,
      ) async {
        requests.addAll(indices);
        entered.complete();
      }, controller: P8PWindowController());
      try {
        final flight = receiver.take(0, const Duration(seconds: 2));
        await entered.future;
        final failed = expectLater(flight, throwsStateError);
        receiver.fail(StateError('cancelled'));
        await failed;
        await expectLater(
          receiver.take(1, const Duration(seconds: 2)),
          throwsStateError,
        );
        expect(requests, [0, 1, 2, 3]);
      } finally {
        await store.close();
        await root.delete(recursive: true);
      }
    },
  );
  for (final adaptive in [false, true]) {
    test(
      'receiver slow consumer adaptive=$adaptive bounds queue and verifies every payload',
      () async {
        final root = await Directory.systemTemp.createTemp('p8p-receiver-');
        final payload = Uint8List.fromList(
          List.generate(1048576, (i) => i % 251),
        );
        const count = 14;
        final manifest = AppUpgradeP2PManifest(
          fileSize: payload.length * count,
          sha256: 'a' * 64,
          pieceHashes: List.filled(count, sha256.convert(payload).toString()),
          stunUrls: const [],
          apiBase: '/unused',
          serverSeedUrl: 'https://example.test',
        );
        final store = AppUpgradeP2PPieceStore(
          File('${root.path}/part'),
          manifest,
        );
        final policy = adaptive ? P8PWindowController() : null;
        final requested = <int>[];
        var consumed = 0, peak = 0;
        late AppUpgradeP2PWindowReceiver receiver;
        receiver = AppUpgradeP2PWindowReceiver(
          store,
          List.generate(count, (i) => i),
          (indices) async {
            requested.addAll(indices);
            final outstanding = requested.length - consumed;
            if (outstanding > peak) peak = outstanding;
            expect(outstanding, lessThanOrEqualTo(4));
            for (final index in indices) {
              receiver.start({
                'type': 'piece-start',
                'index': index,
                'size': payload.length,
              });
              for (var start = 0; start < payload.length; start += 48 * 1024) {
                final end = (start + 48 * 1024).clamp(0, payload.length);
                receiver.add(Uint8List.sublistView(payload, start, end));
              }
              receiver.end({'type': 'piece-end', 'index': index});
            }
          },
          controller: policy,
        );
        try {
          for (var index = 0; index < count; index++) {
            final bytes = await receiver.take(
              index,
              const Duration(seconds: 2),
            );
            expect(
              sha256.convert(bytes).toString(),
              manifest.pieceHashes[index],
            );
            consumed++;
            // Model the real consumer's async persistence, not a fabricated link
            // speed observation. The next take() measures this actual interval.
            await Future<void>.delayed(const Duration(milliseconds: 15));
          }
          expect(requested, List.generate(count, (i) => i));
          expect(peak, 4);
          // Real hashing/processing time varies by host. Assert a meaningful
          // reduction without requiring the exact minimum after 14 pieces.
          if (adaptive) expect(policy!.window, inInclusiveRange(2, 3));
        } finally {
          await store.close();
          await root.delete(recursive: true);
        }
      },
    );
  }
}
