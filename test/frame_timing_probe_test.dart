import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/performance/frame_timing_probe.dart';

void main() {
  test('frame timing summary reports the 120Hz and 60Hz budgets', () {
    final timings = <FrameTiming>[
      _timing(buildMicros: 900, rasterMicros: 5000),
      _timing(buildMicros: 1200, rasterMicros: 9000),
      _timing(buildMicros: 1600, rasterMicros: 18000),
    ];

    final summary = frameTimingSummary(timings);

    expect(summary, contains('frames=3'));
    expect(summary, contains('build_p50_ms=1.20'));
    expect(summary, contains('raster_p50_ms=9.00'));
    expect(summary, contains('raster_over_8_33=2'));
    expect(summary, contains('raster_over_16_67=1'));
  });
}

FrameTiming _timing({required int buildMicros, required int rasterMicros}) {
  final rasterStart = 1000 + buildMicros;
  return FrameTiming(
    vsyncStart: 0,
    buildStart: 1000,
    buildFinish: 1000 + buildMicros,
    rasterStart: rasterStart,
    rasterFinish: rasterStart + rasterMicros,
    rasterFinishWallTime: rasterStart + rasterMicros,
    frameNumber: 1,
  );
}
