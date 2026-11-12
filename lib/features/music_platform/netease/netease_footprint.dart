import 'dart:convert';

/// Read-only official footprint-calendar aggregate. It cannot prove that an
/// individual log was indexed, or that a replay was assigned to its old month.
class NeteaseFootprint {
  const NeteaseFootprint(this.month, this.hours, this.minutes);
  final String month;
  final int hours, minutes;
  // The official widget displays hours when positive, otherwise minutes.
  // The two fields are not proven to be a quotient/remainder pair, so they
  // must never be added into a fabricated exact Duration.
  String get label => hours > 0 ? '$hours 小时' : '$minutes 分钟';
  static NeteaseFootprint? parse(Object? value) {
    try {
      if (value is String) value = jsonDecode(value);
      if (value is! Map) return null;
      if (value.containsKey('data')) value = value['data'];
      if (value is String) value = jsonDecode(value);
      if (value is! Map) return null;
      final hours = int.tryParse('${value['hourDuration']}');
      final minutes = int.tryParse('${value['minuteDuration']}');
      if (hours == null ||
          minutes == null ||
          hours < 0 ||
          hours > 1000000 ||
          minutes < 0 ||
          minutes > 60000000) {
        return null;
      }
      final month = '${value['monthDate'] ?? ''}'.trim();
      if (month.isEmpty || month.length > 32) return null;
      return NeteaseFootprint(month, hours, minutes);
    } on Object {
      return null;
    }
  }
}
