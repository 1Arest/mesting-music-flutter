import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ring_download_sdk/src/core/services/app_upgrade_p2p_piece_store.dart';
import 'package:ring_download_sdk/src/core/services/app_upgrade_p2p_protocol.dart';
import 'package:ring_download_sdk/src/p8p/coordinator.dart';
import 'package:ring_download_sdk/src/p8p/leases.dart';
import 'package:ring_download_sdk/src/p8p/ordered_writer.dart';
import 'package:ring_download_sdk/src/p8p/sources.dart';
import 'package:ring_download_sdk/src/p8p/transfer_receiver.dart';

/// The bridge owns native RTC and signaling. Actual SDK code owns protocol,
/// SHA validation, scheduling, reservations and disk writes. No rate shaper.
/// This is an established-transport test, not Flutter/Android/startup acceptance.
Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError('Expected bridge-command.json and a new output folder');
  }
  final command = jsonDecode(await File(args[0]).readAsString()) as Map;
  final folder = Directory(args[1]);
  if (await folder.exists()) throw StateError('Output folder already exists');
  await folder.create(recursive: true);
  const chunk = AppUpgradeP2PManifest.chunkSize;
  final payload = Uint8List(8 * chunk);
  for (var i = 0; i < payload.length; i++) {
    payload[i] = i % 251;
  }
  final digest = sha256.convert(payload).toString();
  final hashes = [
    for (var i = 0; i < payload.length; i += chunk)
      sha256.convert(Uint8List.sublistView(payload, i, i + chunk)).toString(),
  ];
  final manifest = AppUpgradeP2PManifest(
    fileSize: payload.length,
    sha256: digest,
    pieceHashes: hashes,
    stunUrls: const ['stun:example.test:3479'],
    apiBase: 'https://example.test/p2p',
    serverSeedUrl: 'https://example.test/p2p/seed',
  );
  final watch = Stopwatch()..start();
  final store = AppUpgradeP2PPieceStore(
    File('${folder.path}/received.bin'),
    manifest,
    bufferedWrites: true,
  );
  final book = P8PLeaseBook(
    contentKey: 'example/native-competition',
    fileSha256: digest,
    generation: 501,
    fileBytes: payload.length,
    pieceBytes: chunk,
    clockMicros: () => watch.elapsedMicroseconds,
    repeatBudgetBytes: 2 * chunk,
  );
  final persisted = <Map<String, Object?>>[];
  final diagnostics = <String>[];
  final writer = await P8POrderedWriter.open(
    book,
    store,
    onPersisted: (lease) {
      persisted.add({
        'index': lease.index,
        'source': lease.source,
        'bytes': lease.bytes,
        'elapsed_ms': watch.elapsedMilliseconds,
        'lease_age_us': watch.elapsedMicroseconds - lease.startedMicros,
      });
    },
  );
  final coordinator = P8PCoordinator(
    writer,
    clockMicros: () => watch.elapsedMicroseconds,
    onDiagnostic: (event) =>
        diagnostics.add('${event.alias}:${event.reason.code}'),
  );
  final bridge = await Process.start(
    command['executable'] as String,
    List<String>.from(command['arguments'] as List),
    workingDirectory: command['workingDirectory'] as String?,
  );
  void send(Map<String, Object?> value) =>
      bridge.stdin.writeln(jsonEncode(value));
  final connected = {
    for (final source in ['seed', 'peer1']) source: Completer<void>(),
  };
  final physicallyClosed = {
    for (final source in ['seed', 'peer1']) source: Completer<void>(),
  };
  final openedAt = <String, int>{};
  final receivers = <String, P8PTransferReceiver>{};
  final completion = Completer<Map<String, dynamic>>();
  final inputErrors = <String>[];
  final stderrFile = File('${folder.path}/bridge-stderr.log').openWrite();
  final errorSubscription = bridge.stderr.listen(stderrFile.add);
  for (final source in ['seed', 'peer1']) {
    receivers[source] = P8PTransferReceiver(
      source: source,
      writer: writer,
      send: (control) async =>
          send({'kind': 'send', 'source': source, 'control': control}),
      closeTransport: () async {
        send({'kind': 'close_source', 'source': source});
        await physicallyClosed[source]!.future;
      },
      onDiagnostic: (event) => diagnostics.add('$source:${event.reason.code}'),
    );
  }
  void fail(Object error) {
    inputErrors.add(error.toString());
    for (final ready in connected.values) {
      if (!ready.isCompleted) ready.completeError(error);
    }
    if (!completion.isCompleted) completion.completeError(error);
  }

  // Awaiting connect inside this listener would block its own hello reply.
  final subscription = bridge.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(
        (line) {
          try {
            final row = jsonDecode(line) as Map<String, dynamic>;
            final source = row['source'] as String?;
            switch (row['kind']) {
              case 'transport_open':
                openedAt[source!] = watch.elapsedMilliseconds;
                unawaited(
                  receivers[source]!.connect(const Duration(seconds: 8)).then((
                    _,
                  ) {
                    if (!connected[source]!.isCompleted) {
                      connected[source]!.complete();
                    }
                  }, onError: (Object error) => fail(error)),
                );
              case 'control':
                receivers[source]!.acceptControl(row['control'] as String);
              case 'binary':
                receivers[source]!.acceptBinary(
                  base64Decode(row['data'] as String),
                );
              case 'source_closed':
                if (row['native_exit_zero'] != true ||
                    row['native_closed'] != true) {
                  final error = StateError(
                    'Native source failed physical closure',
                  );
                  physicallyClosed[source]!.completeError(error);
                  fail(error);
                } else {
                  physicallyClosed[source]!.complete();
                }
              case 'bridge_complete':
                if (!completion.isCompleted) {
                  completion.complete(row);
                }
              case 'bridge_error':
                fail(StateError('Native bridge reported ${row['error']}'));
            }
          } catch (error) {
            fail(error);
          }
        },
        onError: fail,
        onDone: () {
          if (!completion.isCompleted) {
            fail(StateError('Bridge ended without terminal proof'));
          }
        },
      );
  // Failure futures are observed while the main path may still await handshake.
  unawaited(completion.future.then<void>((_) {}, onError: (Object _) {}));
  for (final ready in connected.values) {
    unawaited(ready.future.then<void>((_) {}, onError: (Object _) {}));
  }
  for (final closed in physicallyClosed.values) {
    unawaited(closed.future.then<void>((_) {}, onError: (Object _) {}));
  }
  var success = false;
  try {
    await Future.wait(connected.values.map((ready) => ready.future));
    // Both transports are established; seed is intentionally inserted first.
    // There is no artificial delay, bandwidth cap, or fixed role preference.
    coordinator.add(
      P8PRtcPieceSource(receivers['seed']!),
      diagnosticAlias: 'seed',
    );
    coordinator.add(
      P8PRtcPieceSource(receivers['peer1']!),
      diagnosticAlias: 'peer1',
    );
    final schedulingStarted = watch.elapsedMilliseconds;
    final complete = await coordinator.run(active: () => true);
    final schedulingCompleted = watch.elapsedMilliseconds;
    final verified = complete && await store.completeAndVerified();
    final native = await completion.future;
    final exitCode = await bridge.exitCode;
    final report = {
      'scope':
          'Actual SDK coordinator/RTC protocol over a stdio bridge to native aiortc; no Android, HTTPS, discovery, or startup-race acceptance',
      'verified': verified,
      'bytes': payload.length,
      'sha256': digest,
      'seed_inserted_first': true,
      'both_transports_established_before_scheduling': true,
      'sender_rate_shaping': false,
      'transport_open_ms': openedAt,
      'probe_total_ms_including_archive': watch.elapsedMilliseconds,
      'scheduling_and_close_ms': schedulingCompleted - schedulingStarted,
      'scheduling_started_ms': schedulingStarted,
      'last_persisted_ms': persisted.isEmpty
          ? null
          : persisted.last['elapsed_ms'],
      'persisted_pieces': persisted,
      'coordinator_metrics': coordinator.metrics,
      'diagnostics': diagnostics,
      'bridge_exit_code': exitCode,
      'input_errors': inputErrors,
      'native': native,
    };
    await File(
      '${folder.path}/result.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
    success =
        verified &&
        exitCode == 0 &&
        native['cleanup_complete'] == true &&
        inputErrors.isEmpty;
    if (!success) throw StateError('Native SDK competition did not verify');
    stdout.writeln(jsonEncode(report));
  } catch (error) {
    await File('${folder.path}/failure.json').writeAsString(
      jsonEncode({
        'error': error.toString(),
        'input_errors': inputErrors,
        'coordinator_metrics': coordinator.metrics,
        'persisted_pieces': persisted,
      }),
    );
    rethrow;
  } finally {
    Object? cleanupError;
    try {
      await coordinator.close();
    } catch (error) {
      cleanupError = error;
    }
    for (final receiver in receivers.values) {
      try {
        await receiver.close();
      } catch (error) {
        cleanupError ??= error;
      }
    }
    await bridge.stdin.close();
    await bridge.exitCode;
    await subscription.cancel();
    await errorSubscription.cancel();
    await stderrFile.close();
    await store.close();
    if (success && cleanupError == null) await store.file.delete();
    if (cleanupError != null) throw cleanupError;
  }
}
