/// Bounded business details only. Never display a raw response, URL, request
/// body, device identifier or credential. Known sensitive values are removed
/// before generic phone/OTP/token patterns, including mixed wire encodings.
String qishuiAuthDetail(Object? raw, {Iterable<String> secrets = const []}) {
  if (raw is! String || raw.length > 2048) return '';
  var text = raw;
  for (final secret
      in secrets.where((s) => s.isNotEmpty).toList()
        ..sort((a, b) => b.length.compareTo(a.length))) {
    text = text.replaceAll(secret, '[已隐藏]');
  }
  text = text
      .replaceAll(
        RegExp(r'https?://[^\s<>"\x27]+', caseSensitive: false),
        '[链接已隐藏]',
      )
      .replaceAll(
        RegExp(
          r'(?:cookie|session\w*|token|authorization|sms_code_key|mobile|phone|code|验证码|手机号)\s*[:=：]\s*[^\s,;，；]+',
          caseSensitive: false,
        ),
        '[敏感字段已隐藏]',
      )
      .replaceAll(RegExp(r'[a-zA-Z0-9_+/=\-]{12,}'), '[已隐藏]')
      .replaceAll(RegExp(r'\+?\d[\d\s\-]{3,}\d'), '[已隐藏]')
      .replaceAll(RegExp(r'\d{4,}'), '[已隐藏]')
      .replaceAll(RegExp(r'[\x00-\x1f\x7f<>`{}\[\]]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return text.length > 120 ? '${text.substring(0, 120)}…' : text;
}

String qishuiAuthCode(Map<String, dynamic> value) {
  final data = value['data'] is Map ? value['data'] as Map : const {};
  final raw =
      '${data['error_code'] ?? value['error_code'] ?? value['status_code'] ?? ''}';
  return raw.isEmpty || RegExp(r'^-?\d{1,12}$').hasMatch(raw) ? raw : 'invalid';
}

String qishuiAuthDescription(
  Map<String, dynamic> value, {
  Iterable<String> secrets = const [],
}) {
  final data = value['data'] is Map ? value['data'] as Map : const {};
  return qishuiAuthDetail(
    data['description'] ??
        data['error_msg'] ??
        data['error_message'] ??
        value['description'] ??
        value['error_msg'],
    secrets: secrets,
  );
}
