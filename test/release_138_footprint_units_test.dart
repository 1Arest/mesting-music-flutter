import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/official_footprint.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/official_footprint_repository.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';

import 'netease_v112_listening_test.dart' show session;
import 'release_137_footprint_test.dart' show footprintResponse;

void main() {
  test('372 report minutes show 6h12 and 386 period minutes show 6h26', () {
    final report = OfficialListenPeriod.parse(
      footprintResponse(
        minutes: 386,
        day: {'period': '2026-11-02', 'duration': 372},
      ),
    );
    expect(report.today('2026-11-02'), 22320);
    expect(report.seconds, 23160);
    expect(officialDuration(report.today('2026-11-02')), '6 小时 12 分钟');
    expect(officialDuration(report.seconds), '6 小时 26 分钟');
  });

  test('all daily resource categories use the same minute wire contract', () {
    final response = footprintResponse(
      minutes: 386,
      day: {
        'period': '2026-11-02',
        'duration': '360',
        'podcastDuration': 8,
        'audiobookDuration': '4',
      },
    );
    // Numeric strings follow the same unit as JSON numbers; they are not
    // an alternate seconds contract.
    ((response['data'] as Map)['listenTimeDistributionBlock']
            as Map)['playDuration'] =
        '386';
    final report = OfficialListenPeriod.parse(response);
    expect(report.today('2026-11-02'), 22320);
    expect(report.seconds, 23160);
  });

  test('historical month reports normalize minutes at the same boundary', () {
    final history = OfficialListenPeriod.parse(
      footprintResponse(
        month: '2026-10',
        minutes: 600,
        day: {'period': '2026-10-31', 'duration': 60},
      ),
    ).forMonth('2026-10');
    expect(history.seconds, 36000);
    expect(history.today('2026-10-31'), 3600);
    expect(officialDuration(history.seconds), '10 小时 0 分钟');
  });

  test(
    'zero minutes stay zero and optional absent categories stay absent zero',
    () {
      final report = OfficialListenPeriod.parse(
        footprintResponse(
          minutes: 0,
          day: {'period': '2026-11-02', 'duration': 0},
        ),
      );
      expect(report.seconds, 0);
      expect(report.today('2026-11-02'), 0);
      expect(officialDuration(report.seconds), '0 分钟');
    },
  );

  test('minute fields reject fractional, negative and missing values', () {
    for (final invalid in <Object?>[.5, -1, null, 'unavailable']) {
      final response = footprintResponse(
        day: {'period': '2026-11-02', 'duration': invalid},
      );
      expect(() => OfficialListenPeriod.parse(response), throwsFormatException);
      final periodResponse = footprintResponse();
      final block =
          (periodResponse['data'] as Map)['listenTimeDistributionBlock'] as Map;
      if (invalid == null) {
        block.remove('playDuration');
      } else {
        block['playDuration'] = invalid;
      }
      expect(
        () => OfficialListenPeriod.parse(periodResponse),
        throwsFormatException,
      );
    }
  });

  test(
    'historical total remains seconds and is never multiplied by 60',
    () async {
      var requests = 0;
      final api = NeteaseApi(
        MockClient((request) async {
          requests++;
          expect(request.url.path, '/eapi/content/activity/listen/data/total');
          return http.Response(
            jsonEncode({
              'code': 200,
              'data': {'totalDuration': '20194260'},
            }),
            200,
          );
        }),
      )..configure(session);
      final seconds = await OfficialFootprintRepository(api).totalSeconds();
      expect(seconds, 20194260);
      expect(officialDuration(seconds), '5609 小时 31 分钟');
      expect(requests, 1);
    },
  );
}
