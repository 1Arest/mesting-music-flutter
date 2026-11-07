import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter_test/flutter_test.dart';

// Exercise the manual example's actual recorder without exporting it from
// the shipped SDK. This example entry is deliberately outside the SDK lib.
// ignore: avoid_relative_lib_imports
import '../example/lib/p8p_native_probe.dart' show NativeProbeEvidence;

const zero = {'peerConnections': 0, 'dataChannels': 0, 'channelObservers': 0};
const one = {'peerConnections': 1, 'dataChannels': 1, 'channelObservers': 1};
const phases = <Map<String, Object>>[
  {'phase': 'main_started', 'elapsed_ms': 0},
  {'phase': 'sharing_finish_received', 'elapsed_ms': 1000},
  {'phase': 'progress_subscription_cancel_begin', 'elapsed_ms': 2000},
  {'phase': 'progress_subscription_cancel_end', 'elapsed_ms': 3000},
  {'phase': 'sdk_dispose_begin', 'elapsed_ms': 4000},
  {'phase': 'sdk_dispose_end', 'elapsed_ms': 5000},
  {'phase': 'probe_storage_delete_begin', 'elapsed_ms': 6000},
  {'phase': 'probe_storage_delete_end', 'elapsed_ms': 7000},
  {'phase': 'final_native_owners_begin', 'elapsed_ms': 8000},
  {'phase': 'final_native_owners_end', 'elapsed_ms': 9000},
  {'phase': 'disposed_marker_queued', 'elapsed_ms': 10000},
];

Map<String, dynamic> snapshot(NativeProbeEvidence recorder) =>
    jsonDecode(recorder.encode(phases)) as Map<String, dynamic>;

void main() {
  test(
    'owner samples are copied and zero final values remain actual values',
    () {
      final recorder = NativeProbeEvidence();
      final initial = {...zero};
      recorder.recordOwners(initial, 5);
      initial['peerConnections'] = 99;
      final positive = {...one};
      recorder.recordOwners(positive, 200);
      positive['dataChannels'] = 99;
      recorder.recordOwners(zero, 8500);
      final native = snapshot(recorder)['native'];
      expect(native['initial']['counts'], zero);
      expect(native['positive_one']['counts'], one);
      expect(native['positive_one']['query'], 2);
      expect(native['positive_one']['elapsed_ms'], 200);
      expect(native['final']['counts'], zero);
      expect(native['queries'], 3);
    },
  );

  test(
    'zero-only and nonzero initial samples are never repaired or invented',
    () {
      final idle = NativeProbeEvidence()
        ..recordOwners(zero, 5)
        ..recordOwners(zero, 8500);
      expect(snapshot(idle)['native']['positive_one'], isNull);
      expect(snapshot(idle)['native']['positive_two'], isNull);
      final badInitial = NativeProbeEvidence()
        ..recordOwners(one, 5)
        ..recordOwners(zero, 8500);
      expect(snapshot(badInitial)['native']['initial']['counts'], one);
    },
  );

  test('two-owner evidence requires simultaneous counts in the same query', () {
    final recorder = NativeProbeEvidence()..recordOwners(zero, 5);
    recorder.recordOwners({
      'peerConnections': 2,
      'dataChannels': 1,
      'channelObservers': 2,
    }, 100);
    recorder.recordOwners({
      'peerConnections': 1,
      'dataChannels': 2,
      'channelObservers': 2,
    }, 200);
    expect(snapshot(recorder)['native']['positive_two'], isNull);
    recorder.recordOwners({
      'peerConnections': 2,
      'dataChannels': 2,
      'channelObservers': 2,
    }, 250);
    recorder.recordOwners(zero, 8500);
    final native = snapshot(recorder)['native'];
    expect(native['positive_two']['query'], 4);
    expect(native['positive_two']['elapsed_ms'], 250);
    expect(native['positive_one']['query'], 2);
  });

  test('buffer peak preserves every sample before actual first pause', () {
    final recorder = NativeProbeEvidence()..recordOwners(zero, 5);
    final values = [100, 300000];
    recorder.recordBuffers(values, 100);
    values[1] = 999999;
    recorder.recordBuffers([250000], 200);
    recorder.recordLifecycle('paused', 300);
    recorder.recordBuffers([999999], 400);
    recorder.recordLifecycle('resumed', 700);
    recorder.recordBuffers([888888], 800);
    recorder.recordOwners(zero, 8500);
    expect(snapshot(recorder)['buffers'], {
      'queries_before_pause': 2,
      'peak_bytes_before_pause': 300000,
    });
  });

  test(
    'invalid owner inputs poison final evidence instead of hiding errors',
    () {
      for (final invalid in [
        {'peerConnections': -1, 'dataChannels': 0, 'channelObservers': 0},
        {...zero, 'private': 1},
        {'peerConnections': 0, 'dataChannels': 0},
      ]) {
        final recorder = NativeProbeEvidence()..recordOwners(zero, 5);
        expect(() => recorder.recordOwners(invalid, 10), throwsStateError);
        expect(() => recorder.encode(phases), throwsStateError);
      }
    },
  );

  test(
    'out of order time and lifecycle overflow cannot leave a valid subset',
    () {
      final backwards = NativeProbeEvidence()..recordOwners(zero, 5);
      expect(() => backwards.recordBuffers([], 4), throwsStateError);
      expect(() => backwards.encode(phases), throwsStateError);
      final overflow = NativeProbeEvidence()..recordOwners(zero, 0);
      for (var index = 1; index <= 16; index++) {
        overflow.recordLifecycle(index.isEven ? 'resumed' : 'paused', index);
      }
      expect(() => overflow.recordLifecycle('paused', 17), throwsStateError);
      expect(() => overflow.encode(phases), throwsStateError);
    },
  );

  test('overlap copies the actual incomplete and cancelled task samples', () {
    final recorder = NativeProbeEvidence()..recordOwners(zero, 5);
    final before = <String, Object?>{
      'state': 'transferring',
      'received': 10,
      'total': 100,
      'terminal': null,
      'lifecycle': 'resumed',
    };
    recorder.recordOverlap('start', before, 400);
    before['received'] = 100;
    recorder.recordOverlap('end', {
      'state': 'cancelled',
      'received': 15,
      'total': 100,
      'terminal': 'cancelled',
      'lifecycle': 'resumed',
    }, 600);
    recorder.recordOwners(zero, 8500);
    expect(snapshot(recorder)['overlap']['start']['sample']['received'], 10);
    expect(snapshot(recorder)['overlap']['end']['sample']['received'], 15);
    expect(
      () => recorder.recordOverlap('start', before, 8501),
      throwsStateError,
    );
    expect(() => recorder.encode(phases), throwsStateError);
  });

  test('raw evidence has a fixed encoded size bound', () {
    final recorder = NativeProbeEvidence()
      ..recordOwners(zero, 5)
      ..recordOwners(zero, 8500);
    final huge = <Map<String, Object>>[
      {'phase': 'x' * 4000, 'elapsed_ms': 0},
    ];
    expect(() => recorder.encode(huge), throwsStateError);
    expect(() => recorder.encode(phases), throwsStateError);
  });

  test(
    'log record stays below the observed tablet limit without data loss',
    () {
      final recorder = NativeProbeEvidence()
        ..recordOwners(zero, 5)
        ..recordOwners(one, 200)
        ..recordOwners(zero, 8500);
      final record = recorder.encodeLogRecord(phases);
      expect(utf8.encode(record).length, lessThanOrEqualTo(900));
      expect(record.contains('\n'), isFalse);
      final encoded = record.substring('P8P_NATIVE_EVIDENCE_GZIP '.length);
      expect(
        utf8.decode(gzip.decode(base64Decode(encoded))),
        recorder.encode(phases),
      );
    },
  );

  test('maximum lifecycle and overlap observations fit the log transport', () {
    final recorder = NativeProbeEvidence()
      ..recordOwners(zero, 0)
      ..recordOwners(one, 1)
      ..recordOwners({for (final key in zero.keys) key: 1024}, 2)
      ..recordBuffers([315392], 3);
    for (var index = 0; index < 16; index++) {
      recorder.recordLifecycle(index.isEven ? 'paused' : 'resumed', index + 4);
    }
    for (final name in ['start', 'end']) {
      recorder.recordOverlap(name, {
        'state': name == 'start' ? 'transferring' : 'cancelled',
        'received': 16777294,
        'total': 16777295,
        'terminal': name == 'start' ? null : 'cancelled',
        'lifecycle': 'resumed',
      }, name == 'start' ? 599998 : 599999);
    }
    recorder.recordOwners(zero, 600000);
    final record = recorder.encodeLogRecord(phases);
    expect(utf8.encode(record).length, lessThanOrEqualTo(900));
    final encoded = record.substring('P8P_NATIVE_EVIDENCE_GZIP '.length);
    expect(
      utf8.decode(gzip.decode(base64Decode(encoded))),
      recorder.encode(phases),
    );
  });

  test(
    'actual Dart encoded cache fixture is consumable by the strict reader',
    () {
      final recorder = NativeProbeEvidence()
        ..recordOwners(zero, 5)
        ..recordOwners(one, 200)
        ..recordBuffers([300000], 250)
        ..recordLifecycle('paused', 300)
        ..recordBuffers([999999], 400)
        ..recordLifecycle('resumed', 700)
        ..recordOwners(zero, 8500);
      final encoded = recorder.encode(phases);
      expect(utf8.encode(encoded).length, lessThanOrEqualTo(3500));
      // A deterministic serializer fixture, not a claimed Android device result.
      debugPrintSynchronously('P8P_DART_EVIDENCE_FIXTURE $encoded');
      debugPrintSynchronously(
        'P8P_DART_TRANSPORT_FIXTURE ${recorder.encodeLogRecord(phases)}',
      );
    },
  );
}
