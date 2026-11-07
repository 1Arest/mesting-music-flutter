import 'dart:convert';
import 'dart:io';

import 'package:ring_download_sdk/src/core/services/app_upgrade_p2p_piece_store.dart';
import 'package:ring_download_sdk/src/core/services/app_upgrade_p2p_protocol.dart';
import 'package:ring_download_sdk/src/p8p/leases.dart';
import 'package:ring_download_sdk/src/p8p/ordered_writer.dart';
import 'package:ring_download_sdk/src/p8p/transfer_receiver.dart';

/// Replay scripts/p8p_export_transcript.py output through the actual receiver.
/// This measures interoperability and file integrity; it is not a speed test.
Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError('Expected transcript.json and an output directory');
  }
  final transcript =
      jsonDecode(await File(args[0]).readAsString()) as Map<String, dynamic>;
  final metadata = transcript['manifest'] as Map<String, dynamic>;
  final folder = Directory(args[1]);
  await folder.create(recursive: true);
  final file = File('${folder.path}/received.bin');
  if (await file.exists()) throw StateError('Output already exists');
  final manifest = AppUpgradeP2PManifest(
    fileSize: metadata['file_size'] as int,
    sha256: metadata['sha256'] as String,
    pieceHashes: List<String>.from(metadata['piece_hashes'] as List),
    stunUrls: const ['stun:example.test:3479'],
    apiBase: 'https://example.test/p2p',
    serverSeedUrl: 'https://example.test/p2p/server-offer',
  );
  final watch = Stopwatch()..start();
  final book = P8PLeaseBook(
    contentKey: 'example/interop/v1',
    fileSha256: manifest.sha256,
    generation: transcript['generation'] as int,
    fileBytes: manifest.fileSize,
    pieceBytes: AppUpgradeP2PManifest.chunkSize,
    clockMicros: () => watch.elapsedMicroseconds,
  );
  final store = AppUpgradeP2PPieceStore(file, manifest, bufferedWrites: true);
  final writer = await P8POrderedWriter.open(book, store);
  final sent = <Map<String, Object?>>[];
  final receiver = P8PTransferReceiver(
    source: 'python-sender',
    writer: writer,
    send: (value) async {
      sent.add(value);
    },
    closeTransport: () async {},
  );
  try {
    final connecting = receiver.connect(const Duration(seconds: 2));
    final records = transcript['records'] as List;
    receiver.acceptControl(jsonEncode((records.first as Map)['control']));
    await connecting;
    final tickets = <P8PTransferTicket>[];
    for (final row in transcript['requests'] as List) {
      final lease = book.request(
        row['index'] as int,
        'python-sender',
        timeout: const Duration(seconds: 5),
      )!;
      if (lease.id != row['request_id']) throw StateError('Request IDs differ');
      tickets.add(receiver.request(lease));
    }
    for (final row in records.skip(1)) {
      if (row['binary'] is String) {
        receiver.acceptBinary(base64Decode(row['binary'] as String));
      } else {
        receiver.acceptControl(jsonEncode(row['control']));
      }
    }
    await Future.wait(tickets.map((ticket) => ticket.verified));
    await writer.idle;
    final verified = await store.completeAndVerified();
    if (!verified || !book.complete || receiver.pending != 0) {
      throw StateError('Transcript failed integrity');
    }
    final report = {
      'success': true,
      'scope': transcript['scope'],
      'bytes': await file.length(),
      'sha256': manifest.sha256,
      'records': records.length,
      'requests': sent.length - 1,
      'out_of_order': true,
      'metrics': store.metrics,
    };
    await File(
      '${folder.path}/result.json',
    ).writeAsString('${jsonEncode(report)}\n');
    stdout.writeln(jsonEncode(report));
  } finally {
    await receiver.close();
    await writer.close();
  }
}
