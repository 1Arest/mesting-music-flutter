/// Request-local identity for modern private-message reads. Keep every version
/// field together: changing only the User-Agent leaves the encrypted header
/// advertising an older client and can still select a compatibility response.
/// Public reference: api-enhanced util/request.js, Android 9.5.61 identity.
/// This identity is never persisted to the account or used for message writes.
abstract final class NeteaseMessageProtocol {
  static const appVersion = '9.5.61';
  static const versionCode = '9005061';
  static const osVersion = '12';
  static const userAgent =
      'NeteaseMusic/9.5.61.260802021928(9005061);Dalvik/2.1.0 '
      '(Linux; U; Android 12; HBN-AL00 Build/cd737a2.0)';
}
