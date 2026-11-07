import 'package:flutter_test/flutter_test.dart';
import 'package:ring_download_sdk/src/p8p/source_goodput.dart';

void main() {
  const bytes = 1000000;

  test(
    'serial delivery over two queued requests retains aggregate link rate',
    () {
      final rate = P8PSourceGoodput()..started(0);
      rate.verified(bytes, 100000);
      rate.stopped(100000);
      rate.started(150000);
      rate.started(150000);
      rate.verified(bytes, 250000);
      rate.stopped(250000);
      rate.started(250000);
      rate.verified(bytes, 350000);
      rate.stopped(350000);
      rate.verified(bytes, 450000);
      rate.stopped(450000);
      expect(rate.bytesPerMicrosecond, closeTo(10, 0.000001));
      expect(rate.samples, 4);
    },
  );

  test('parallel completions at the same instant share their elapsed time', () {
    final rate = P8PSourceGoodput()
      ..started(0)
      ..started(0);
    rate.verified(bytes, 100000);
    rate.stopped(100000);
    rate.verified(bytes, 100000);
    rate.stopped(100000);
    expect(rate.bytesPerMicrosecond, closeTo(20, 0.000001));
  });

  test('idle gaps without physical requests do not lower source goodput', () {
    final rate = P8PSourceGoodput()..started(0);
    rate.verified(bytes, 100000);
    rate.stopped(100000);
    rate.started(5100000);
    rate.verified(bytes, 5200000);
    rate.stopped(5200000);
    expect(rate.bytesPerMicrosecond, closeTo(10, 0.000001));
  });

  test('unverified or cancelled work cannot produce a positive sample', () {
    final rate = P8PSourceGoodput()..started(0);
    rate.stopped(500000);
    expect(rate.bytesPerMicrosecond, isNull);
    expect(rate.samples, 0);
  });

  test('an idle source with stale samples starts a new measurement epoch', () {
    final rate = P8PSourceGoodput()..started(0);
    rate.verified(bytes, 100000);
    rate.stopped(100000);
    final start = 100000 + P8PSourceGoodput.sampleTtlMicros + 1;
    rate.started(start);
    expect(rate.samples, 0);
    expect(rate.bytesPerMicrosecond, isNull);
    rate.verified(bytes, start + 200000);
    rate.stopped(start + 200000);
    expect(rate.bytesPerMicrosecond, closeTo(5, 0.000001));
  });

  test('old slow completions leave the bounded recent-goodput window', () {
    final rate = P8PSourceGoodput();
    var now = 0;
    for (final micros in [
      ...List.filled(4, 1000000),
      ...List.filled(4, 100000),
    ]) {
      rate.started(now);
      now += micros;
      rate.verified(bytes, now);
      rate.stopped(now);
      expect(rate.samples, lessThanOrEqualTo(4));
    }
    expect(rate.bytesPerMicrosecond, closeTo(10, 0.000001));
  });
}
