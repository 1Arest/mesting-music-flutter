import 'package:flutter_test/flutter_test.dart';
import 'package:ring_download_sdk/src/core/services/app_upgrade_upload_budget.dart';

void main() {
  testWidgets(
    'payload budget survives receiver reconnection without a new burst',
    (tester) async {
      var micros = 0;
      final budget = AppUpgradeUploadBudget(
        bytesPerSecond: 1000,
        burstBytes: 100,
        clockMicros: () => micros,
      );
      final first = budget.tryAcquire()!;
      await first.take(100, () => true);
      expect(budget.tryAcquire(), null);
      first.cancel();
      expect(
        budget.tryAcquire(),
        null,
      ); // Cancellation does not retire native IO.
      first.release();
      final second = budget.tryAcquire()!;
      var queued = false;
      final pending = second.take(100, () => true).then((_) => queued = true);
      await tester.pump();
      expect(queued, false);
      micros = 99000;
      await tester.pump(const Duration(milliseconds: 99));
      expect(queued, false);
      micros = 100000;
      await tester.pump(const Duration(milliseconds: 1));
      await pending;
      expect(queued, true);
      second.release();
    },
  );

  testWidgets(
    'revocation wakes pacing immediately and keeps receiver ownership',
    (tester) async {
      final budget = AppUpgradeUploadBudget(
        bytesPerSecond: 1,
        burstBytes: 100,
        clockMicros: () => 0,
      );
      final slot = budget.tryAcquire()!;
      await slot.take(100, () => true);
      final waiting = slot.take(100, () => true);
      final failed = expectLater(waiting, throwsStateError);
      slot.cancel();
      await tester.pump();
      await failed;
      expect(budget.tryAcquire(), null);
      slot.release();
      final next = budget.tryAcquire()!;
      next.release();
    },
  );

  test('policy recheck rejects payload before consuming credit', () async {
    final budget = AppUpgradeUploadBudget();
    final slot = budget.tryAcquire()!;
    await expectLater(slot.take(48 * 1024, () => false), throwsStateError);
    await slot.take(256 * 1024, () => true);
    slot.release();
  });
}
