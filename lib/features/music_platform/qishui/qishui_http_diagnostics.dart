import 'dart:convert';

import 'qishui_diagnostics.dart';

/// Classify only the supported Soda operations. Paths, object IDs and request
/// bodies are never retained by the diagnostic buffer or returned to the UI.
QishuiDiagnosticFeature? qishuiDiagnosticFeatureForRequest(
  String path, {
  Map<String, Object?> body = const {},
}) {
  if (path == '/luna/me' || path == '/luna/pc/me') {
    return QishuiDiagnosticFeature.socialStats;
  }
  if (RegExp(r'^/luna/users/[0-9]{1,30}/following$').hasMatch(path)) {
    return QishuiDiagnosticFeature.following;
  }
  if (RegExp(r'^/luna/users/[0-9]{1,30}/follower$').hasMatch(path)) {
    return QishuiDiagnosticFeature.followers;
  }
  return switch (path) {
    '/luna/user/info' => QishuiDiagnosticFeature.userInfo,
    '/luna/me/follow' => QishuiDiagnosticFeature.userFollow,
    '/luna/me/unfollow' => QishuiDiagnosticFeature.userUnfollow,
    '/luna/me/collection/artist' || '/luna/me/collection/artist/delete' =>
      QishuiDiagnosticFeature.artistCollection,
    '/luna/me/music_wall' => QishuiDiagnosticFeature.officialListening,
    '/luna/video/uploader' => QishuiDiagnosticFeature.coverUpload,
    '/luna/me/playlist/update' || '/luna/pc/me/playlist/update'
        when body.containsKey('cover_uri') =>
      QishuiDiagnosticFeature.playlistCover,
    _ => null,
  };
}

/// A bounded error-body decoder, not an export API. The caller immediately
/// passes this transient object to the closed diagnostic schema. Raw text and
/// decoding exceptions are never persisted, displayed or sent elsewhere.
Object? qishuiDiagnosticJson(List<int> bytes) {
  if (bytes.isEmpty || bytes.length > 65536) return null;
  try {
    return jsonDecode(utf8.decode(bytes));
  } on Object {
    return null;
  }
}

/// Inspect the known numeric business-code locations without changing the
/// existing request's acceptance rules. A 200 transport receipt is independent
/// from both the business receipt and the subsequent DTO parsing result.
Object? qishuiDiagnosticBusinessCode(Object? value) {
  if (value is! Map) return null;
  final status = value['status_info'];
  final data = value['data'];
  return value['status_code'] ??
      value['error_code'] ??
      (status is Map ? status['code'] ?? status['status_code'] : null) ??
      (data is Map ? data['error_code'] ?? data['status_code'] : null) ??
      value['code'];
}
