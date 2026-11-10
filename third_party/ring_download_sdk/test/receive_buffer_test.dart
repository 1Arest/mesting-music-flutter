import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ring_download_sdk/src/sdk/receive_buffer.dart';
import 'package:ring_download_sdk/ring_download_sdk.dart';

const channel = MethodChannel('ring_download_sdk/test_receive_buffer');
String candidate(
  int port, {
  String address = '192.0.2.10',
  String type = 'host',
  String protocol = 'udp',
}) => 'candidate:123 1 $protocol 2122260223 $address $port typ $type';
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 15));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'tuneRtcReceiveBuffer'
          ? {'code': 'adjusted'}
          : true;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'reports actual minimum buffer with only bounded numeric socket facts',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'tuneRtcReceiveBuffer') return true;
        return {
          'code': 'adjusted',
          'matched': 2,
          'minBufferBytes': 425984,
          'address': 'PRIVATE-ADDRESS',
          'owner': 'PRIVATE-OWNER',
        };
      });
      final observations = <RingDownloadDiagnostic>[];
      final legacy = <String>[];
      final observed = Completer<void>();
      final owner = RingRtcReceiveBufferOwner(
        channel: channel,
        onResult: legacy.add,
        onDiagnostic: (event) {
          observations.add(event);
          observed.complete();
          throw StateError('optional observer');
        },
      );
      owner.addCandidate(candidate(45000));
      await observed.future.timeout(const Duration(seconds: 1));
      await owner.close();
      expect(legacy, ['receive_buffer_adjusted']);
      expect(observations.single.toJson(), {
        'stage': 'rtc',
        'code': 'receive_buffer_adjusted',
        'minReceiveBufferBytes': 425984,
        'matchedReceiveSockets': 2,
      });
    },
  );

  test(
    'invalid or absent native measurements stay unknown in diagnostics',
    () async {
      for (final values in <Map<String, Object?>>[
        {'code': 'adjusted'},
        {'code': 'adjusted', 'matched': true, 'minBufferBytes': 2097152},
        {'code': 'adjusted', 'matched': 9, 'minBufferBytes': 2097152},
        {'code': 'adjusted', 'matched': -1, 'minBufferBytes': 2097152},
        {'code': 'adjusted', 'matched': 0, 'minBufferBytes': 2097152},
        {'code': 'adjusted', 'matched': 1, 'minBufferBytes': 0},
        {'code': 'adjusted', 'matched': 1, 'minBufferBytes': 425984.0},
        {'code': 'adjusted', 'matched': 1, 'minBufferBytes': 67108865},
        {'code': 'PRIVATE-URL', 'matched': 1, 'minBufferBytes': 2097152},
      ]) {
        messenger.setMockMethodCallHandler(channel, (call) async {
          return call.method == 'tuneRtcReceiveBuffer' ? values : true;
        });
        final observed = Completer<RingDownloadDiagnostic>();
        final owner = RingRtcReceiveBufferOwner(
          channel: channel,
          onDiagnostic: observed.complete,
        );
        owner.addCandidate(candidate(45000));
        final event = await observed.future.timeout(const Duration(seconds: 1));
        await owner.close();
        expect(event.minReceiveBufferBytes, isNull, reason: values.toString());
        expect(event.toJson().containsKey('minReceiveBufferBytes'), false);
        expect(event.toJson().toString(), isNot(contains('PRIVATE')));
      }
    },
  );

  test(
    'retirement from the legacy observer fences the numeric observation',
    () async {
      final observations = <RingDownloadDiagnostic>[];
      final retired = Completer<void>();
      late final RingRtcReceiveBufferOwner owner;
      owner = RingRtcReceiveBufferOwner(
        channel: channel,
        onResult: (_) {
          unawaited(owner.close().then((_) => retired.complete()));
        },
        onDiagnostic: observations.add,
      );
      owner.addCandidate(candidate(45000));
      await retired.future.timeout(const Duration(seconds: 1));
      expect(observations, isEmpty);
    },
  );

  test('only numeric, unicast host UDP candidates are eligible', () {
    expect(
      RingRtcReceiveBufferOwner.hostBinding(candidate(45000))?['port'],
      45000,
    );
    expect(
      RingRtcReceiveBufferOwner.hostBinding(
        candidate(45000, address: '2001:db8::1'),
      )?['family'],
      6,
    );
    for (final value in [
      candidate(0),
      candidate(65536),
      candidate(1234, type: 'srflx'),
      candidate(1234, protocol: 'tcp'),
      candidate(1234, address: 'device.local'),
      candidate(1234, address: '127.0.0.1'),
      candidate(1234, address: '169.254.1.2'),
      candidate(1234, address: '224.0.0.1'),
      candidate(1234, address: '0.0.0.0'),
      candidate(1234, address: '::'),
      candidate(1234, address: '::1'),
      candidate(1234, address: 'fe80::1'),
      candidate(1234, address: '::ffff:192.0.2.1'),
      candidate(1234).replaceFirst('2122260223', '4294967296'),
      candidate(1234).replaceFirst('candidate:123', 'candidate:'),
    ]) {
      expect(
        RingRtcReceiveBufferOwner.hostBinding(value),
        isNull,
        reason: value,
      );
    }
  });
  test(
    'batches at most eight bindings, deduplicates a wildcard port, and exposes no SDP',
    () async {
      final events = <String>[];
      final observations = <RingDownloadDiagnostic>[];
      final owner = RingRtcReceiveBufferOwner(
        channel: channel,
        onResult: events.add,
        onDiagnostic: observations.add,
      );
      owner.addCandidate(candidate(45000));
      owner.addCandidate(candidate(45000, address: '192.0.2.11'));
      for (var i = 1; i < 20; i++) {
        owner.addCandidate(candidate(45000 + i));
      }
      await settle();
      await owner.close();
      final tunes = calls
          .where((call) => call.method == 'tuneRtcReceiveBuffer')
          .toList();
      expect(tunes.length, 1);
      final args = tunes.single.arguments as Map;
      expect(args['bindings'], hasLength(8));
      expect(args.keys, unorderedEquals(['owner', 'bindings', 'expiresAt']));
      expect(args['owner'], matches(RegExp(r'^[a-f0-9]{32}$')));
      expect(events, ['receive_buffer_adjusted']);
    },
  );
  test(
    'a candidate arriving while a batch is pending gets only one remaining batch',
    () async {
      final gate = Completer<Object?>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'tuneRtcReceiveBuffer' &&
            calls.where((c) => c.method == call.method).length == 1) {
          return gate.future;
        }
        return call.method == 'tuneRtcReceiveBuffer'
            ? {'code': 'unchanged'}
            : true;
      });
      final owner = RingRtcReceiveBufferOwner(channel: channel);
      owner.addCandidate(candidate(45000));
      await settle();
      owner.addCandidate(candidate(45001));
      await settle();
      gate.complete({'code': 'adjusted'});
      await settle();
      owner.addCandidate(candidate(45002));
      await settle();
      await owner.close();
      expect(
        calls.where((c) => c.method == 'tuneRtcReceiveBuffer'),
        hasLength(2),
      );
    },
  );
  test(
    'retirement fences a delayed begin and old candidates cannot tune a new owner',
    () async {
      final begin = Completer<Object?>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'beginRtcReceiveBuffer' ? begin.future : true;
      });
      final old = RingRtcReceiveBufferOwner(channel: channel);
      old.addCandidate(candidate(45000));
      await settle();
      await old.close();
      old.addCandidate(candidate(45001));
      begin.complete(true);
      await settle();
      expect(calls.where((c) => c.method == 'tuneRtcReceiveBuffer'), isEmpty);
      final next = RingRtcReceiveBufferOwner(channel: channel);
      await settle();
      await next.close();
      final ids = calls
          .where((c) => c.method == 'beginRtcReceiveBuffer')
          .map((c) => (c.arguments as Map)['owner'])
          .toSet();
      expect(ids, hasLength(2));
    },
  );
  test(
    'missing plugin, rejected native capability and host diagnostics cannot fail close',
    () async {
      for (final mode in ['missing', 'unsupported', 'observer']) {
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (mode == 'missing') throw MissingPluginException();
          if (call.method == 'beginRtcReceiveBuffer') {
            return mode != 'unsupported';
          }
          return call.method == 'tuneRtcReceiveBuffer'
              ? {'code': 'private-untrusted-url'}
              : true;
        });
        final events = <String>[];
        final owner = RingRtcReceiveBufferOwner(
          channel: channel,
          onResult: (code) {
            events.add(code);
            throw StateError('observer');
          },
        );
        owner.addCandidate(candidate(45000));
        await settle();
        await owner.close();
        expect(events, everyElement('receive_buffer_unavailable'));
      }
    },
  );
  test(
    'stalled native replies have a fixed bound and late replies emit no result',
    () async {
      final gate = Completer<Object?>();
      final started = Completer<void>();
      final events = <String>[];
      final observations = <RingDownloadDiagnostic>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'tuneRtcReceiveBuffer') {
          started.complete();
          return gate.future;
        }
        return true;
      });
      final owner = RingRtcReceiveBufferOwner(
        channel: channel,
        onResult: events.add,
        onDiagnostic: observations.add,
      );
      owner.addCandidate(candidate(45000));
      await started.future;
      await owner.close();
      gate.complete({'code': 'adjusted'});
      await settle();
      expect(events, isEmpty);
      expect(observations, isEmpty);
      final count = calls.length;
      owner.addCandidate(candidate(45002));
      await settle();
      expect(calls, hasLength(count));
    },
  );

  test(
    'an unresponsive tuning call reports a bounded optional failure while the owner stays live',
    () async {
      final gate = Completer<Object?>(), observed = Completer<String>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        return call.method == 'tuneRtcReceiveBuffer' ? gate.future : true;
      });
      final owner = RingRtcReceiveBufferOwner(
        channel: channel,
        onResult: (code) {
          if (!observed.isCompleted) observed.complete(code);
        },
      );
      owner.addCandidate(candidate(45000));
      expect(
        await observed.future.timeout(const Duration(seconds: 2)),
        'receive_buffer_unavailable',
      );
      await owner.close();
      gate.complete({'code': 'adjusted'});
      await settle();
    },
  );
}
