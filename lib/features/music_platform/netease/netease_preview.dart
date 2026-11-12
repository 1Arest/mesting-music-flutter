/// Passport/API serializers may return milliseconds as an int, a double, or
/// a numeric string. Parsing only integer strings silently lost preview times.
int neteaseMilliseconds(Object? value) {
  final number = value is num ? value : num.tryParse('$value');
  return number != null && number.isFinite && number > 0 ? number.round() : 0;
}

/// A trial privilege describes what an account could request, not what this
/// particular URL contains. Use the actual trial payload or delivered length.
bool neteaseResponseIsPreview(Map<String, dynamic> row, Duration catalog) {
  if (row['freeTrialInfo'] is Map) return true;
  final delivered = neteaseMilliseconds(row['time']);
  return delivered > 0 && catalog.inMilliseconds > delivered + 3000;
}
