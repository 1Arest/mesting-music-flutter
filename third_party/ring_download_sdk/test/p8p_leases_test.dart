import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ring_download_sdk/src/p8p/leases.dart';

void main() {
  var now = 0;
  const timeout = Duration(seconds: 2);
  P8PLeaseBook make({
    int slots = 4,
    int repeat = 64,
    int attempts = 3,
    int persisted = 0,
    Duration budget = const Duration(minutes: 5),
  }) => P8PLeaseBook(
    contentKey: 'example/app/release',
    fileSha256: 'a' * 64,
    generation: 1,
    fileBytes: 15,
    pieceBytes: 4,
    clockMicros: () => now,
    maxReservations: slots,
    repeatBudgetBytes: repeat,
    maxAttempts: attempts,
    persistedPieces: persisted,
    taskBudget: budget,
  );
  setUp(() => now = 0);

  test(
    'diagnostic view distinguishes cancelling loser from ready winner of same piece',
    () {
      final book = make();
      final slow = book.request(0, 'slow', timeout: timeout)!;
      now = 1100000;
      final fast = book.request(0, 'fast', timeout: timeout, hedge: true)!;
      expect(book.verified(fast), true);
      final before = book.diagnosticReservations;
      expect(before.map((s) => s.phase), [
        P8PReservationPhase.cancelling,
        P8PReservationPhase.ready,
      ]);
      expect(before.map((s) => s.lease.source), ['slow', 'fast']);
      expect(book.reservations, 2);
      expect(() => before.clear(), throwsUnsupportedError);
      final write = book.beginWrite()!;
      now = 3000000;
      final during = book.diagnosticReservations;
      expect(during.map((s) => s.phase), [
        P8PReservationPhase.cancelling,
        P8PReservationPhase.writing,
      ]);
      expect(
        book.reservations,
        2,
        reason: 'Observation cannot expire or release physical owners',
      );
      expect(
        before.last.phase,
        P8PReservationPhase.ready,
        reason: 'Captured view is immutable',
      );
      book.acknowledgeStopped(slow);
      book.persisted(write);
      expect(book.reservations, 0);
      expect(book.persistedPieces, 1);
    },
  );

  test(
    'bodyless admission keeps capacity until physical stop without using a body attempt',
    () {
      final book = make(slots: 1, attempts: 1, repeat: 0);
      final rejected = book.request(0, 'https', timeout: timeout)!;
      expect(book.rejectAdmission(rejected), true);
      expect(book.reservations, 1);
      expect(book.request(0, 'node', timeout: timeout), null);
      expect(book.verified(rejected), false);
      expect(book.acknowledgeStopped(rejected), true);
      expect(book.acknowledgeStopped(rejected), false);
      final replacement = book.request(0, 'node', timeout: timeout)!;
      expect(replacement.id, greaterThan(rejected.id));
      expect(book.repeatReservedBytes, 0);
      expect(book.rejectAdmission(replacement), false);
    },
  );

  test(
    'admission release never refunds earlier payload or ordinary cancellation',
    () {
      final book = make(repeat: 4);
      final first = book.request(0, 'node', timeout: timeout)!;
      book.cancel(first);
      book.acknowledgeStopped(first);
      final admission = book.request(0, 'https', timeout: timeout)!;
      expect(book.repeatReservedBytes, 4);
      expect(book.rejectAdmission(admission), true);
      expect(book.repeatReservedBytes, 4);
      book.acknowledgeStopped(admission);
      expect(book.repeatReservedBytes, 0);
      final retry = book.request(0, 'node', timeout: timeout)!;
      expect(book.repeatReservedBytes, 4);
      book.cancel(retry);
      book.acknowledgeStopped(retry);
      expect(book.repeatReservedBytes, 4);
      expect(book.request(0, 'node', timeout: timeout), null);
    },
  );

  test('invalid local bounds cannot create unbounded reservations', () {
    for (final slots in [0, 5]) {
      expect(() => make(slots: slots), throwsArgumentError);
    }
    expect(() => make(attempts: 9), throwsArgumentError);
    expect(() => make(repeat: -1), throwsArgumentError);
    expect(() => make(persisted: 5), throwsArgumentError);
    expect(() => make(budget: Duration.zero), throwsArgumentError);
  });

  test('bodyless admission exemptions are bounded across the entire task', () {
    final book = make();
    for (var index = 0; index < 2; index++) {
      final lease = book.request(index, 'https', timeout: timeout)!;
      expect(book.rejectAdmission(lease), true);
      expect(book.acknowledgeStopped(lease), true);
    }
    final third = book.request(2, 'https', timeout: timeout)!;
    expect(book.rejectAdmission(third), false);
    expect(book.reservations, 1);
    book.cancel(third);
    book.acknowledgeStopped(third);
    expect(book.request(2, 'node', timeout: timeout), isNotNull);
    expect(book.repeatReservedBytes, 4);
  });

  test('invalid indices and identities never reserve a slot', () {
    final book = make();
    for (final index in [-1, 4, 1000000]) {
      expect(book.request(index, 'b', timeout: timeout), null);
    }
    expect(book.request(0, '', timeout: timeout), null);
    expect(book.request(0, 'b', timeout: Duration.zero), null);
    expect(book.reservations, 0);
    expect(book.reservedBytes, 0);
  });

  test('ready and writing pieces count until contiguous commit', () {
    final book = make();
    final leases = [
      for (var index = 0; index < 4; index++)
        book.request(index, 'b', timeout: timeout)!,
    ];
    expect(book.reservations, 4);
    expect(book.reservedBytes, 15);
    expect(book.peakReservations, 4);
    expect(book.peakReservedBytes, 15);
    expect(book.verified(leases[1]), true);
    expect(book.beginWrite(), null);
    expect(book.phase(1), P8PPiecePhase.ready);
    expect(book.verified(leases[0]), true);
    final first = book.beginWrite()!;
    expect(book.phase(0), P8PPiecePhase.writing);
    expect(book.beginWrite(), null);
    expect(book.reservations, 4);
    book.persisted(first);
    expect(() => book.persisted(first), throwsStateError);
    expect(book.reservations, 3);
    expect(book.persistedBytes, 4);
    book.persisted(book.beginWrite()!);
    expect(book.persistedPieces, 2);
    expect(book.peakReservations, 4);
    expect(book.peakReservedBytes, 15);
  });

  test('expiry reserves its slot until actual transport stop', () {
    final book = make(slots: 1);
    final lease = book.request(0, 'b', timeout: timeout)!;
    now = timeout.inMicroseconds;
    book.expire();
    expect(book.leasePhase(lease), P8PLeasePhase.cancelling);
    expect(book.accepts(lease), false);
    expect(book.verified(lease), false);
    expect(book.request(0, 'c', timeout: timeout), null);
    expect(book.reservations, 1);
    expect(book.acknowledgeStopped(lease), true);
    expect(book.acknowledgeStopped(lease), false);
    final retry = book.request(0, 'c', timeout: timeout)!;
    expect(retry.id, isNot(lease.id));
    expect(book.accepts(lease), false);
    expect(book.reservedBytes, 4);
  });

  test('a cancel frame alone does not create free capacity', () {
    final book = make(slots: 1);
    final lease = book.request(0, 'b', timeout: timeout)!;
    expect(book.acknowledgeStopped(lease), false);
    expect(book.cancel(lease), true);
    expect(book.cancel(lease), false);
    expect(book.request(1, 'b', timeout: timeout), null);
    expect(book.acknowledgeStopped(lease), true);
    expect(book.request(1, 'b', timeout: timeout), isNotNull);
  });

  test('foreign generation objects cannot complete equal request IDs', () {
    final old = make();
    final next = make();
    final before = old.request(0, 'b', timeout: timeout)!;
    final after = next.request(0, 'b', timeout: timeout)!;
    expect(before.id, after.id);
    expect(next.verified(before), false);
    expect(next.cancel(before), false);
    expect(next.acknowledgeStopped(before), false);
    expect(next.accepts(after), true);
    old.close();
    expect(old.accepts(before), false);
  });

  test('hedging needs age, another source, a slot and repeat bytes', () {
    final book = make(repeat: 4);
    final slow = book.request(0, 'b', timeout: timeout)!;
    expect(book.request(0, 'c', timeout: timeout, hedge: true), null);
    now = 1000000;
    expect(book.request(0, 'b', timeout: timeout, hedge: true), null);
    final fast = book.request(0, 'c', timeout: timeout, hedge: true)!;
    expect(book.repeatReservedBytes, 4);
    expect(book.request(0, 'd', timeout: timeout, hedge: true), null);
    expect(book.verified(fast), true);
    expect(book.reservations, 2);
    expect(book.leasePhase(slow), P8PLeasePhase.cancelling);
    expect(book.verified(slow), false);
    book.persisted(book.beginWrite()!);
    expect(book.reservations, 1);
    book.acknowledgeStopped(slow);
    expect(book.reservations, 0);
    expect(book.repeatReservedBytes, 4);
  });

  test('retry cannot refund reserved duplicate traffic', () {
    final book = make(repeat: 4);
    for (var attempt = 0; attempt < 2; attempt++) {
      final lease = book.request(0, 'b', timeout: timeout)!;
      book.cancel(lease);
      book.acknowledgeStopped(lease);
    }
    expect(book.repeatReservedBytes, 4);
    expect(book.request(0, 'c', timeout: timeout), null);
    expect(book.request(1, 'c', timeout: timeout), isNotNull);
  });

  test('attempt count stays bounded even with a larger traffic budget', () {
    final book = make(attempts: 2);
    for (var attempt = 0; attempt < 2; attempt++) {
      final lease = book.request(0, 'b', timeout: timeout)!;
      book.cancel(lease);
      book.acknowledgeStopped(lease);
    }
    expect(book.request(0, 'c', timeout: timeout), null);
  });

  test('task deadline cancels active work and rejects late responses', () {
    final book = make(budget: const Duration(seconds: 1));
    final lease = book.request(0, 'b', timeout: timeout)!;
    expect(lease.deadlineMicros, 1000000);
    now = 1000000;
    book.expire();
    expect(book.closed, true);
    expect(book.verified(lease), false);
    expect(book.reservations, 1);
    book.acknowledgeStopped(lease);
    expect(book.reservations, 0);
  });

  test('verified resume prefix cannot be leased again', () {
    final book = make(persisted: 3);
    expect(book.request(2, 'b', timeout: timeout), null);
    final last = book.request(3, 'b', timeout: timeout)!;
    expect(last.bytes, 3);
    book.verified(last);
    book.persisted(book.beginWrite()!);
    expect(book.complete, true);
    expect(book.persistedBytes, 15);
    expect(book.request(3, 'b', timeout: timeout), null);
  });

  test('clock going backwards is rejected', () {
    final book = make();
    now = 10;
    book.request(0, 'b', timeout: timeout);
    now = 9;
    expect(book.expire, throwsStateError);
  });

  test('random cancellation, arrival and write order preserve bounds', () {
    for (var seed = 0; seed < 32; seed++) {
      now = 0;
      final random = Random(seed);
      final book = make();
      final all = <P8PLease>[];
      P8PWrite? writing;
      var committed = 0;
      for (var step = 0; step < 500; step++) {
        now += random.nextInt(10000);
        final selected = all.isEmpty ? null : all[random.nextInt(all.length)];
        switch (random.nextInt(7)) {
          case 0 || 1:
            final lease = book.request(
              random.nextInt(4),
              'source_${random.nextInt(3)}',
              timeout: const Duration(milliseconds: 30),
              hedge: true,
              hedgeAfter: const Duration(milliseconds: 10),
            );
            if (lease != null) all.add(lease);
          case 2:
            if (selected != null) book.cancel(selected);
          case 3:
            if (selected != null) book.acknowledgeStopped(selected);
          case 4:
            if (selected != null) book.verified(selected);
          case 5:
            writing ??= book.beginWrite();
          case 6:
            if (writing != null) {
              book.persisted(writing);
              writing = null;
            }
        }
        book.expire();
        final owners = all.where((lease) => book.leasePhase(lease) != null);
        final ready = [
          for (var index = 0; index < 4; index++)
            if ({
              P8PPiecePhase.ready,
              P8PPiecePhase.writing,
            }.contains(book.phase(index)))
              index,
        ];
        expect(book.reservations, owners.length + ready.length);
        expect(book.reservations, inInclusiveRange(0, 4));
        expect(book.reservedBytes, inInclusiveRange(0, 16));
        expect(book.repeatReservedBytes, lessThanOrEqualTo(64));
        expect(book.persistedPieces, greaterThanOrEqualTo(committed));
        committed = book.persistedPieces;
      }
      book.close();
      if (writing != null) book.persisted(writing);
      for (final lease in book.cancellations) {
        book.acknowledgeStopped(lease);
      }
      expect(book.reservations, 0);
    }
  });
}
