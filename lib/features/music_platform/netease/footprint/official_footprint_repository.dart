import '../netease_api.dart';
import 'official_footprint.dart';

/// These POST routes read reports, not playback-write APIs. Keep payloads to
/// the official page's type/endTime fields; no local minutes are uploaded.
class OfficialFootprintRepository implements OfficialFootprintSource {
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
}
