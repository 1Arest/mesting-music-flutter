class OnlineMusicConfig {
  const OnlineMusicConfig._();

  static const kugouApiBaseUrl = String.fromEnvironment('KUGOU_API_BASE_URL');
  static const neteaseApiBaseUrl = String.fromEnvironment(
    'NETEASE_API_BASE_URL',
  );
  static const enableNeteaseSource = bool.fromEnvironment(
    'ENABLE_NETEASE_SOURCE',
    defaultValue: true,
  );

  static String normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }
}
