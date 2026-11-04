import 'package:flutter/services.dart';
import '../netease_music_repository.dart';

/// Read only the server's relation-wide cumulative snapshot. Session time is
/// a separate measurement: neither it nor an earlier snapshot may be added to
/// this value. Missing/invalid totals stay unknown, including on old servers
/// which return only currentConnectionTime.
Duration? parseTogetherCumulativeDuration(Object? value) {
  var data = NeteaseMusicRepository.object(value);
  if (data['data'] is Map) data = NeteaseMusicRepository.object(data['data']);
  final seconds = int.tryParse('${data['totalConnectionTime']}'.trim());
  return seconds != null && seconds >= 0 && seconds < 100 * 366 * 86400
      ? Duration(seconds: seconds)
      : null;
}

/// Platform distance is in kilometres (the official client formats it directly
/// as km). Zero/negative sentinel values must never masquerade as proximity.
class TogetherDistance {
  const TogetherDistance({
    this.kilometres,
    this.unopenedUserIds = const [],
    this.copyWriting = '',
  });
  final double? kilometres;
  final List<String> unopenedUserIds;
  final String copyWriting;
  factory TogetherDistance.parse(Object? value) {
    var data = NeteaseMusicRepository.object(value);
    if (data['data'] is Map) data = NeteaseMusicRepository.object(data['data']);
    final number = double.tryParse('${data['distance']}');
    final copy = '${data['copyWriting'] ?? ''}'.trim();
    final unopened = data['unopenedUserIds'] is List
        ? (data['unopenedUserIds'] as List)
              .map((v) => '$v')
              .where((v) => RegExp(r'^\d+$').hasMatch(v))
              .toList()
        : const <String>[];
    return TogetherDistance(
      // The server's unopened state takes precedence over a cached numeric
      // distance, including when a participant has just closed sharing.
      kilometres:
          unopened.isEmpty &&
              number != null &&
              number.isFinite &&
              number > 0 &&
              number <= 21000
          ? number
          : null,
      unopenedUserIds: unopened,
      copyWriting: copy.length <= 120 ? copy : '',
    );
  }
  String get label => kilometres == null
      ? unopenedUserIds.isNotEmpty
            ? '等待对方开启位置'
            : copyWriting.isNotEmpty
            ? copyWriting
            : '距离暂不可用'
      : '相距约 ${kilometres! < .01 ? '<0.01' : kilometres!.toStringAsFixed(2)} 公里';
}

class TogetherLocationFix {
  const TogetherLocationFix(this.latitude, this.longitude, this.accuracyMeters);
  final double latitude, longitude, accuracyMeters;
  static TogetherLocationFix parse(Object? value) {
    final data = NeteaseMusicRepository.object(value);
    double number(String key) => double.tryParse('${data[key]}') ?? double.nan;
    final lat = number('latitude'),
        lon = number('longitude'),
        accuracy = number('accuracyMeters');
    if (!lat.isFinite ||
        lat < -90 ||
        lat > 90 ||
        !lon.isFinite ||
        lon < -180 ||
        lon > 180 ||
        !accuracy.isFinite ||
        accuracy < 0 ||
        accuracy > 50000) {
      throw const FormatException('当前位置无效，请重新获取');
    }
    return TogetherLocationFix(lat, lon, accuracy);
  }
}

/// The UI requests this only after its disclosure. Coordinates stay transient;
/// the room controller alone owns any authenticated report to NetEase.
class TogetherLocationGateway {
  const TogetherLocationGateway();
  static const channel = MethodChannel('mesting/together_location');
  Future<TogetherLocationFix> requestFix() async => TogetherLocationFix.parse(
    await channel.invokeMethod<Object?>('requestFix'),
  );
}

String formatTogetherDuration(Duration duration) {
  final minutes = duration.inMinutes;
  return minutes < 1
      ? '一起听了不到 1 分钟'
      : minutes < 60
      ? '一起听了 $minutes 分钟'
      : '一起听了 ${minutes ~/ 60} 小时${minutes % 60 == 0 ? '' : ' ${minutes % 60} 分钟'}';
}
