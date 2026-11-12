import '../netease_api.dart';
import 'official_footprint.dart';
import 'listening_footprint_models.dart';

/// These POST routes read reports, not playback-write APIs. Keep payloads to
/// the official page's type/endTime fields; no local minutes are uploaded.
class OfficialFootprintRepository
    implements OfficialFootprintSource, OfficialFootprintDetailSource {
  OfficialFootprintRepository(this.api)
    : credential = api.session?.credentialId;
  final NeteaseApi api;
  final String? credential;
  static const _root = '/api/content/activity/listen/data';

  Future<OfficialListenPeriod> _current(String type) async =>
      OfficialListenPeriod.parse(
        await api.request('$_root/realtime/report', {
          'type': type,
        }, expectedCredential: credential),
      );
  @override
  Future<OfficialListenPeriod> currentWeek() => _current('week');
  @override
  Future<OfficialListenPeriod> currentMonth() => _current('month');
  @override
  Future<int> totalSeconds() async {
    final data = footprintData(
      await api.request(
        '$_root/total',
        const {},
        expectedCredential: credential,
      ),
    );
    final value = data['totalDuration'];
    // Reuse the seconds DTO validation without adding widget hour/minute fields.
    final n = value is num ? value : num.tryParse('$value');
    if (n == null ||
        !n.isFinite ||
        n < 0 ||
        n > 1000000000000 ||
        n != n.round()) {
      throw const FormatException('官方总时长暂不可用');
    }
    return n.toInt();
  }

  @override
  Future<OfficialListenPeriod> history(String month) async =>
      OfficialListenPeriod.parse(
        await api.request('$_root/report', {
          'type': 'month',
          'endTime': footprintHistoryEnd(month),
        }, expectedCredential: credential),
      ).forMonth(month);

  /// Source: public listen-home modules 6882/82796/87869. History uses the
  /// selected period's end minus one hour; a fallback response is rejected by
  /// its actual calendar interval, even when the response code is 200.
  @override
  Future<OfficialListeningReport> report(
    FootprintPeriod selection, {
    required bool current,
  }) async {
    if (selection.scale == FootprintScale.year) {
      throw const FormatException('年度足迹请读取官方年度汇总');
    }
    final response = await api.request(
      '$_root/${current ? 'realtime/report' : 'report'}',
      {'type': selection.type, if (!current) 'endTime': selection.historyEnd},
      expectedCredential: credential,
    );
    return OfficialListeningReport.parse(
      response,
    ).forSelection(selection, current: current);
  }

  /// The official yearly module 11461 consumes yearItems[].playDuration in
  /// seconds and playNum as song count. It does not expose monthly durations.
  @override
  Future<OfficialYearlyFootprint> years() async =>
      OfficialYearlyFootprint.parse(
        await api.request(
          '$_root/year/report',
          const {},
          expectedCredential: credential,
        ),
      );

  /// The public todayList endpoint has no historical date argument. Never
  /// relabel these songs as the selected historical day's listening detail.
  @override
  Future<OfficialTodaySongs> todaySongs(String day) async =>
      OfficialTodaySongs.parse(
        await api.request(
          '$_root/today/song/play/rank',
          const {},
          expectedCredential: credential,
        ),
        day: day,
      );
}
