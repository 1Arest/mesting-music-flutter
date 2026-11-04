import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ring_download_sdk/src/p8p/transfer_protocol.dart';

void main() {
  final fixture =
      jsonDecode(File('test/fixtures/p8p-transfer-v1.json').readAsStringSync())
          as Map<String, dynamic>;
  Uint8List fromHex(String value) => Uint8List.fromList([
    for (var index = 0; index < value.length; index += 2)
      int.parse(value.substring(index, index + 2), radix: 16),
  ]);
  for (final row in fixture['controls'] as List) {
    test('shared control vector ${row['name']}', () {
      final raw = jsonEncode(row['value']);
      if (row['valid'] == true) {
        expect(
          P8PTransferProtocol.request(raw, fixture['piece_count'] as int),
          row['value'],
        );
      } else {
        expect(
          () => P8PTransferProtocol.request(raw, fixture['piece_count'] as int),
          throwsFormatException,
        );
      }
    });
  }
  for (final row in fixture['frames'] as List) {
    test('shared frame vector ${row['name']}', () {
      final raw = fromHex(row['hex'] as String);
      if (row['valid'] == true) {
        final frame = P8PTransferProtocol.frame(raw);
        expect(frame.generation, row['generation']);
        expect(frame.identity, row['request_id']);
        expect(frame.offset, row['offset']);
        expect(frame.body, fromHex(row['body_hex'] as String));
        expect(
          P8PTransferProtocol.encode(
            frame.generation,
            frame.identity,
            frame.offset,
            frame.body,
          ),
          raw,
        );
      } else {
        expect(() => P8PTransferProtocol.frame(raw), throwsFormatException);
      }
    });
  }
  test('optional transfer capability has strict independent bounds', () {
    expect(P8PTransferProtocol.capability, fixture['capability']);
    expect(P8PTransferProtocol.advertised({'version': 1}), false);
    expect(
      P8PTransferProtocol.advertised({
        'version': 1,
        'transfer': fixture['capability'],
      }),
      true,
    );
    for (final entry in {
      'version': 2,
      'header_bytes': 16.0,
      'cancel': 1,
      'max_inflight': true,
    }.entries) {
      expect(
        P8PTransferProtocol.advertised({
          'version': 1,
          'transfer': {
            ...P8PTransferProtocol.capability,
            entry.key: entry.value,
          },
        }),
        false,
      );
    }
  });
}
