import 'package:flutter_test/flutter_test.dart';
import 'package:ring_download_sdk/src/core/services/app_upgrade_p2p_protocol.dart';
import 'package:ring_download_sdk/src/core/services/app_upgrade_seed_candidates.dart';

void main() {
  const first = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const second = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  Map<String, Object?> row(
    int sequence, {
    String offer = first,
    bool end = false,
  }) => {
    'sequence': sequence,
    'offer_id': offer,
    'candidate': end
        ? null
        : {
            'candidate':
                'candidate:$sequence 1 udp 1 192.0.2.25 5000 typ srflx',
            'sdpMid': '0',
            'sdpMLineIndex': 0,
            'usernameFragment': null,
          },
  };
  late AppUpgradeSeedCandidates inbox;
  setUp(() {
    inbox = AppUpgradeSeedCandidates()..register(first);
  });
  test(
    'seed candidates retain order and replay advances no duplicate work',
    () {
      final rows = [row(1), row(2, end: true)];
      final values = inbox.accept(rows, currentOffer: first);
      expect(values.first!.candidate, contains('candidate:1'));
      expect(values.last, isNull);
      expect(inbox.acknowledged, 2);
      expect(inbox.accept(rows, currentOffer: first), isEmpty);
      expect(
        () => inbox.accept([row(3)], currentOffer: first),
        throwsA(isA<AppUpgradeP2PFailure>()),
      );
      expect(inbox.acknowledged, 2);
    },
  );
  test(
    'seed candidates invalid batch leaves acknowledgement and queue unchanged',
    () {
      expect(
        () => inbox.accept([
          row(1),
          {'sequence': '2'},
        ], currentOffer: first),
        throwsA(isA<AppUpgradeP2PFailure>()),
      );
      expect(inbox.acknowledged, 0);
      expect(inbox.accept([row(1)], currentOffer: first), hasLength(1));
      expect(
        () => inbox.accept([row(1, end: true)], currentOffer: first),
        throwsA(isA<AppUpgradeP2PFailure>()),
      );
    },
  );
  test(
    'seed candidates ignore retired generation while accepting new sequence gaps',
    () {
      inbox.register(second);
      final values = inbox.accept([
        row(1),
        row(3, offer: second),
        row(4, offer: second, end: true),
      ], currentOffer: second);
      expect(values, hasLength(2));
      expect(values.first!.candidate, contains('candidate:3'));
      expect(inbox.acknowledged, 4);
      expect(inbox.accept([row(5, end: true)], currentOffer: null), isEmpty);
      expect(inbox.acknowledged, 5);
    },
  );
  test(
    'seed candidates reject foreign generation future bound and reversed order',
    () {
      for (final rows in [
        [row(1, offer: second)],
        [row(67)],
        [row(2), row(1)],
        [row(1), row(1)],
      ]) {
        expect(
          () => inbox.accept(rows, currentOffer: first),
          throwsA(isA<AppUpgradeP2PFailure>()),
        );
        expect(inbox.acknowledged, 0);
      }
      inbox.register(second);
      expect(
        () => inbox.register('cccccccccccccccccccccccccccccccc'),
        throwsA(isA<AppUpgradeP2PFailure>()),
      );
    },
  );
  test(
    'seed candidates keep fixed candidate budget and reserve final marker',
    () {
      expect(
        inbox.accept([
          for (var n = 1; n <= 32; n++) row(n),
        ], currentOffer: first),
        hasLength(32),
      );
      expect(
        () => inbox.accept([row(33)], currentOffer: first),
        throwsA(isA<AppUpgradeP2PFailure>()),
      );
      expect(inbox.acknowledged, 32);
      expect(inbox.accept([row(33, end: true)], currentOffer: first), [null]);
    },
  );
  test('seed candidates invalid native payload cannot be acknowledged', () {
    for (final value in [
      <String, Object?>{'candidate': 'opaque-secret', 'sdpMid': '0'},
      {'candidate': 'candidate:x\r\na=evil', 'sdpMid': '0'},
      {'candidate': 'candidate:x', 'sdpMid': false},
      {'candidate': 'candidate:x', 'sdpMLineIndex': true},
      {'candidate': 'candidate:${'x' * 600}', 'sdpMid': '0'},
    ]) {
      expect(
        () => inbox.accept([
          {'sequence': 1, 'offer_id': first, 'candidate': value},
        ], currentOffer: first),
        throwsA(isA<AppUpgradeP2PFailure>()),
      );
      expect(inbox.acknowledged, 0);
    }
  });
}
