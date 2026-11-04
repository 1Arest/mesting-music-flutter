import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../../core/performance/background_json.dart';

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import '../../auth/domain/auth_models.dart';
import '../domain/listen_together.dart';
import '../domain/social_models.dart';
import 'listen_together_repository.dart';
import 'social_repository.dart';

class CloudBaseSocialRepository
    implements
        SocialRepository,
        ListenTogetherRepository,
        SocialMediaUrlResolver {
  CloudBaseSocialRepository({
    String? environmentId,
    String? apiBaseUrl,
    required AuthSessionProvider sessionProvider,
    AuthSessionRefresher? sessionRefresher,
    http.Client? client,
    String functionName = 'social-api',
    String? actionPath,
    Duration requestTimeout = const Duration(seconds: 10),
  }) : assert(
         (apiBaseUrl != null && apiBaseUrl.trim().isNotEmpty) ||
             (environmentId != null && environmentId.trim().isNotEmpty),
       ),
       _baseUrl = (apiBaseUrl != null && apiBaseUrl.trim().isNotEmpty)
           ? apiBaseUrl.replaceFirst(RegExp(r'/$'), '')
           : 'https://${environmentId!.trim()}.api.tcloudbasegateway.com',
       _sessionProvider = sessionProvider,
       _sessionRefresher = sessionRefresher,
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _actionPath = actionPath ?? '/v1/functions/$functionName?webfn=true',
       _requestTimeout = requestTimeout;

  final String _baseUrl;
  final AuthSessionProvider _sessionProvider;
  final AuthSessionRefresher? _sessionRefresher;
  final http.Client _client;
  final bool _ownsClient;
  final String _actionPath;
  final Duration _requestTimeout;
  final Map<String, String> _resolvedMediaUrls = <String, String>{};
  final _messageSnapshots = <String, (String, List<SocialMessage>)>{};

  @override
  Future<SocialSummary> summary() async {
    return SocialSummary.fromJson(await _call('summary'));
  }

  @override
  Future<SocialStatus> getStatus() async {
    final payload = await _call('getStatus');
    return SocialStatus.fromJson(_map(payload['status']));
  }

  @override
  Future<SocialStatus> setStatus(SocialStatus status) async {
    final payload = await _call('setStatus', status.toJson());
    return SocialStatus.fromJson(_map(payload['status']));
  }

  @override
  Future<SocialUser> updateProfileDetails({
    required int? age,
    required String zodiac,
  }) async {
    final payload = await _call('setProfileDetails', {
      'age': age,
      'zodiac': zodiac.trim(),
    });
    return SocialUser.fromJson(_map(payload['user']));
  }

  @override
  Future<List<SocialUser>> searchUsers(String query) async {
    final payload = await _call('searchUsers', {'query': query.trim()});
    return _usersAsync(payload['users']);
  }

  @override
  Future<SocialUser> getUser(String uid) async {
    final payload = await _call('getUser', {'uid': uid});
    return SocialUser.fromJson(_map(payload['user']));
  }

  @override
  Future<List<SocialUser>> listConnections(SocialConnectionKind kind) async {
    final payload = await _call('listConnections', {'kind': kind.name});
    return _usersAsync(payload['users']);
  }

  @override
  Future<SocialUser> setFollowing(String uid, {required bool following}) async {
    final payload = await _call('setFollowing', {
      'uid': uid,
      'following': following,
    });
    return SocialUser.fromJson(_map(payload['user']));
  }

  @override
  Future<SocialUser> setRemark(String uid, String remark) async {
    final payload = await _call('setRemark', {
      'uid': uid,
      'remark': remark.trim(),
    });
    return SocialUser.fromJson(_map(payload['user']));
  }

  @override
  Future<void> removeFollower(String uid) =>
      _call('removeFollower', {'uid': uid});

  @override
  Future<void> setBlocked(String uid, {required bool blocked}) =>
      _call('setBlocked', {'uid': uid, 'blocked': blocked});

  @override
  Future<List<SocialConversation>> listConversations() async {
    final payload = await _call('listConversations');
    final rows = _list(payload['conversations']);
    return rows.length < 100
        ? _conversationRows(rows)
        : compute(_conversationRows, rows, debugLabel: 'chat-conversations');
  }

  @override
  Future<List<SocialMessage>> listMessages(String uid) async {
    final payload = await _call('listMessages', {'uid': uid});
    final encoded = await encodeJsonValue(payload['messages']);
    final cached = _messageSnapshots[uid];
    if (cached?.$1 == encoded) return cached!.$2;
    final rows = _list(payload['messages']);
    final messages = rows.length < 100
        ? _messageRows(rows)
        : await compute(
            _messageRows,
            rows,
            debugLabel: 'chat-message-snapshot',
          );
    if (_messageSnapshots.length >= 4) {
      _messageSnapshots.remove(_messageSnapshots.keys.first);
    }
    _messageSnapshots[uid] = (encoded, messages);
    return messages;
  }

  @override
  Future<SocialMessage> sendMessage(
    String uid, {
    required SocialMessageKind kind,
    String text = '',
    String? mediaUrl,
    String? thumbnailUrl,
  }) async {
    final payload = await _call('sendMessage', {
      'uid': uid,
      'kind': kind.name,
      'text': text.trim(),
      'media_url': ?mediaUrl,
      'thumbnail_url': ?thumbnailUrl,
    });
    return SocialMessage.fromJson(_map(payload['message']));
  }

  @override
  Future<SocialMessage> recallMessage(String uid, String messageId) async {
    final payload = await _call('recallMessage', {
      'uid': uid,
      'message_id': messageId,
    });
    return SocialMessage.fromJson(_map(payload['message']));
  }

  @override
  Future<void> deleteMessage(String uid, String messageId) =>
      _call('deleteMessage', {'uid': uid, 'message_id': messageId});

  @override
  Future<void> markRead(String uid) => _call('markRead', {'uid': uid});

  @override
  Future<ListenTogetherSession?> getListenTogetherSession() async {
    final payload = await _call('getListenTogetherSession');
    final rawSession = payload['session'];
    if (rawSession == null) return null;
    return ListenTogetherSession.fromJson(_map(rawSession));
  }

  @override
  Future<ListenTogetherSession> inviteToListenTogether(
    String uid, {
    required ListenTogetherPlayback playback,
  }) async {
    final payload = await _call('inviteToListenTogether', {
      'uid': uid,
      ...playback.toRequest(baseRevision: 0),
    });
    return ListenTogetherSession.fromJson(_map(payload['session']));
  }

  @override
  Future<ListenTogetherSession> respondToListenTogetherInvite(
    String invitationId, {
    required bool accept,
  }) async {
    final payload = await _call('respondToListenTogetherInvite', {
      'invitation_id': invitationId,
      'accept': accept,
    });
    return ListenTogetherSession.fromJson(_map(payload['session']));
  }

  @override
  Future<ListenTogetherSession> updateListenTogetherPlayback(
    ListenTogetherPlayback playback, {
    required int baseRevision,
  }) async {
    final payload = await _call(
      'updateListenTogetherPlayback',
      playback.toRequest(baseRevision: baseRevision),
    );
    return ListenTogetherSession.fromJson(_map(payload['session']));
  }

  @override
  Future<ListenTogetherSession> leaveListenTogether() async {
    final payload = await _call('leaveListenTogether');
    return ListenTogetherSession.fromJson(_map(payload['session']));
  }

  @override
  Future<List<ListenTogetherTrackRecord>> listListenTogetherRecords(
    String uid,
  ) async {
    final payload = await _call('listListenTogetherRecords', {'uid': uid});
    return _list(payload['records'])
        .map((item) => ListenTogetherTrackRecord.fromJson(_map(item)))
        .toList(growable: false);
  }

  @override
  Future<SocialUpload> uploadMedia({
    required String path,
    required SocialMessageKind kind,
  }) async {
    if (kind != SocialMessageKind.image &&
        kind != SocialMessageKind.video &&
        kind != SocialMessageKind.voice) {
      throw const SocialRequestException('这种消息不需要上传媒体文件');
    }
    final session = await _requireSession();
    final file = File(path);
    if (!await file.exists()) {
      throw const SocialRequestException('选择的文件已经不存在，请重新选择');
    }
    final length = await file.length();
    final limit = switch (kind) {
      SocialMessageKind.image => 10 << 20,
      SocialMessageKind.video => 100 << 20,
      SocialMessageKind.voice => 20 << 20,
      _ => 0,
    };
    if (length <= 0 || length > limit) {
      throw SocialRequestException(switch (kind) {
        SocialMessageKind.image => '图片不能超过 10 MB',
        SocialMessageKind.video => '视频不能超过 100 MB',
        SocialMessageKind.voice => '语音不能超过 20 MB',
        _ => '媒体文件无效',
      });
    }
    final extension = _safeExtension(path, kind);
    final mimeType = _mimeType(extension, kind);
    if (_actionPath == '/v1/social/actions') {
      return _uploadMediaToCustomApi(path: path, kind: kind, session: session);
    }
    final safeUid = session.user.uid.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final objectId =
        'social-media/$safeUid/${DateTime.now().microsecondsSinceEpoch}$extension';
    final records = await _storagePost('/v1/storages/get-objects-upload-info', [
      {'objectId': objectId},
    ], accessToken: session.accessToken);
    if (records.isEmpty || records.first is! Map) {
      throw const SocialRequestException('云端没有返回上传凭据，请稍后重试');
    }
    final info = Map<String, Object?>.from(records.first! as Map);
    final uploadUrl = _text(info['uploadUrl']);
    final authorization = _text(info['authorization']);
    final token = _text(info['token']);
    final meta = _text(info['cloudObjectMeta']);
    final cloudObjectId = _text(info['cloudObjectId']);
    final downloadUrl =
        _text(info['downloadUrl']) ?? _text(info['downloadUrlEncoded']);
    if (uploadUrl == null ||
        authorization == null ||
        token == null ||
        meta == null ||
        cloudObjectId == null ||
        downloadUrl == null) {
      throw const SocialRequestException('媒体上传凭据不完整，请稍后重试');
    }
    late final http.Response response;
    try {
      response = await _client
          .put(
            Uri.parse(uploadUrl),
            headers: {
              'authorization': authorization,
              'x-cos-security-token': token,
              'x-cos-meta-fileid': meta,
              'content-type': mimeType,
            },
            body: await file.readAsBytes(),
          )
          .timeout(const Duration(seconds: 90));
    } on HandshakeException {
      throw const SocialRequestException('安全连接建立失败，请切换网络后重试');
    } on SocketException {
      throw const SocialRequestException('网络连接不可用，媒体尚未上传');
    } on TimeoutException {
      throw const SocialRequestException('媒体上传超时，请稍后重试');
    } on http.ClientException {
      throw const SocialRequestException('暂时无法上传媒体，请稍后重试');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const SocialRequestException('媒体上传失败，请稍后重试');
    }
    return SocialUpload(cloudObjectId: cloudObjectId, downloadUrl: downloadUrl);
  }

  @override
  Future<String?> resolveMediaUrl(
    String value, {
    bool forceRefresh = false,
  }) async {
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    if (!normalized.startsWith('cloud://')) return normalized;
    final cached = forceRefresh ? null : _resolvedMediaUrls[normalized];
    if (cached != null) return cached;

    // The Java/MySQL API returns download URLs when a message is sent. It does
    // not expose the CloudBase storage gateway, so only resolve legacy IDs on
    // the CloudBase channel.
    if (_actionPath == '/v1/social/actions') return null;
    try {
      final objectId = Uri.parse(normalized).pathSegments.join('/');
      if (objectId.isEmpty) return null;
      final session = await _requireSession();
      final records = await _storagePost(
        '/v1/storages/get-objects-download-info',
        [
          {'objectId': objectId},
        ],
        accessToken: session.accessToken,
      );
      if (records.isEmpty || records.first is! Map) return null;
      final info = Map<String, Object?>.from(records.first! as Map);
      final downloadUrl =
          _text(info['downloadUrl']) ?? _text(info['downloadUrlEncoded']);
      if (downloadUrl != null) _resolvedMediaUrls[normalized] = downloadUrl;
      return downloadUrl;
    } on Object {
      // The text collection remains available if a private file URL cannot be
      // refreshed right now. A later rebuild can try again.
      return null;
    }
  }

  Future<SocialUpload> _uploadMediaToCustomApi({
    required String path,
    required SocialMessageKind kind,
    required AuthSession session,
  }) async {
    try {
      final request =
          http.MultipartRequest('POST', Uri.parse('$_baseUrl/v1/media/upload'))
            ..headers.addAll({
              'accept': 'application/json',
              'authorization': 'Bearer ${session.accessToken}',
            })
            ..fields['kind'] = kind.name
            ..files.add(await http.MultipartFile.fromPath('media', path));
      final response = await http.Response.fromStream(
        await request.send(),
      ).timeout(const Duration(seconds: 90));
      final payload = await _decode(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SocialRequestException(
          _text(payload['message']) ?? '媒体上传失败，请稍后重试',
          code: _text(payload['code']),
        );
      }
      final data = _map(payload['data']);
      final cloudObjectId = _text(data['cloud_object_id']);
      final downloadUrl = _text(data['download_url']);
      if (cloudObjectId == null || downloadUrl == null) {
        throw const SocialRequestException('媒体上传返回的数据不完整');
      }
      return SocialUpload(
        cloudObjectId: cloudObjectId,
        downloadUrl: downloadUrl,
      );
    } on TimeoutException {
      throw const SocialRequestException('媒体上传超时，请稍后重试');
    } on SocketException {
      throw const SocialRequestException('网络连接不可用，媒体尚未上传');
    } on http.ClientException {
      throw const SocialRequestException('暂时无法上传媒体，请稍后重试');
    }
  }

  Future<Map<String, Object?>> _call(
    String action, [
    Map<String, Object?> data = const {},
  ]) {
    return _callWithSessionRefresh(action, data, allowRefresh: true);
  }

  Future<Map<String, Object?>> _callWithSessionRefresh(
    String action,
    Map<String, Object?> data, {
    required bool allowRefresh,
  }) async {
    final session = await _requireSession();
    late final http.Response response;
    try {
      final uri = Uri.parse('$_baseUrl$_actionPath');
      final headers = {
        'content-type': 'application/json; charset=utf-8',
        'accept': 'application/json',
        'authorization': 'Bearer ${session.accessToken}',
      };
      final body = jsonEncode({'action': action, ...data});
      Future<http.Response> send(http.Client client) {
        return client
            .post(uri, headers: headers, body: body)
            .timeout(_requestTimeout);
      }

      try {
        response = await send(_client);
      } on HandshakeException {
        // TLS failed before the HTTP request was delivered, so one short
        // retry cannot duplicate a status, follow, or message mutation. Use a
        // fresh client when this repository owns its connection pool so the
        // retry does not reuse a broken proxy/TLS connection.
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (_ownsClient) {
          final retryClient = http.Client();
          try {
            response = await send(retryClient);
          } finally {
            retryClient.close();
          }
        } else {
          response = await send(_client);
        }
      }
    } on HandshakeException {
      throw const SocialRequestException('安全连接建立失败，请切换网络后重试');
    } on SocketException {
      throw const SocialRequestException('网络连接不可用，请检查网络后重试');
    } on TimeoutException {
      throw const SocialRequestException('好友服务响应较慢，请稍后重试');
    } on http.ClientException {
      throw const SocialRequestException('暂时无法连接好友服务，请稍后重试');
    }
    final payload = await _decode(response);
    final failed =
        response.statusCode < 200 ||
        response.statusCode >= 300 ||
        payload['success'] == false;
    if (failed &&
        allowRefresh &&
        _sessionRefresher != null &&
        _isAuthenticationFailure(response.statusCode, payload)) {
      final refreshed = await _refreshSessionAfterUnauthorized();
      if (refreshed != null &&
          !refreshed.isExpired &&
          refreshed.accessToken != session.accessToken) {
        return _callWithSessionRefresh(action, data, allowRefresh: false);
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SocialRequestException(
        _friendlyMessage(payload),
        code: _text(payload['code']),
      );
    }
    if (payload['success'] == false) {
      throw SocialRequestException(
        _friendlyMessage(payload),
        code: _text(payload['code']),
      );
    }
    return payload['data'] is Map ? _map(payload['data']) : payload;
  }

  Future<AuthSession?> _refreshSessionAfterUnauthorized() async {
    try {
      return await _sessionRefresher?.call();
    } on AuthRequestException catch (error) {
      throw SocialRequestException(error.message, code: error.code);
    }
  }

  bool _isAuthenticationFailure(int statusCode, Map<String, Object?> payload) {
    if (statusCode == 401) return true;
    final code = _text(payload['code'])?.toLowerCase();
    return const {
      'unauthenticated',
      'missing_credentials',
      'invalid_credentials',
      'invalid_token',
      'invalid_access_token',
      '16',
    }.contains(code);
  }

  Future<AuthSession> _requireSession() async {
    final session = await _sessionProvider();
    if (session == null) {
      throw const SocialRequestException('登录后才能使用好友与消息功能');
    }
    if (session.isExpired) {
      throw const SocialRequestException('登录状态已过期，请重新登录');
    }
    return session;
  }

  Future<Map<String, Object?>> _decode(http.Response response) async {
    if (response.bodyBytes.isEmpty) return const {};
    try {
      final decoded = await decodeJsonBytes(response.bodyBytes);
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } on Object {
      // Fall through to the safe error below.
    }
    throw const SocialRequestException('好友服务返回了无法识别的数据');
  }

  String _friendlyMessage(Map<String, Object?> payload) {
    final code = _text(payload['code'])?.toLowerCase();
    final safeServerMessage = _chineseMessage(payload['message']);
    return switch (code) {
      'not_mutual_follow' => '双方互相关注后才能发送消息',
      'blocked' => '当前无法与该用户互动',
      'together_busy' => '你或好友正在其他一起听会话中',
      'together_invite_expired' => '这条一起听邀请已经失效',
      'together_not_active' => '当前没有正在进行的一起听',
      'together_conflict' => '好友刚刚更新了播放状态，正在重新同步',
      'not_found' => '没有找到该用户',
      'unauthenticated' ||
      'missing_credentials' ||
      'invalid_credentials' ||
      'invalid_token' => '登录状态已失效，请重新登录',
      'rate_limited' => '操作太频繁，请稍后再试',
      'function_not_found' ||
      'resource_not_found' ||
      'functionnotfound' => '好友服务尚未完成配置，请稍后再试',
      _ => safeServerMessage ?? '好友服务暂时不可用，请稍后重试',
    };
  }

  Future<List<Object?>> _storagePost(
    String path,
    List<Map<String, Object?>> body, {
    required String accessToken,
  }) async {
    late final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {
              'content-type': 'application/json; charset=utf-8',
              'accept': 'application/json',
              'authorization': 'Bearer $accessToken',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
    } on HandshakeException {
      throw const SocialRequestException('安全连接建立失败，请切换网络后重试');
    } on SocketException {
      throw const SocialRequestException('网络连接不可用，请检查网络后重试');
    } on TimeoutException {
      throw const SocialRequestException('云存储响应较慢，请稍后重试');
    } on http.ClientException {
      throw const SocialRequestException('暂时无法连接云存储，请稍后重试');
    }
    Object? decoded;
    try {
      decoded = await decodeJsonBytes(response.bodyBytes);
    } on Object {
      throw const SocialRequestException('云存储返回了无法识别的数据');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const SocialRequestException('无法获取媒体上传凭据');
    }
    if (decoded is List) return List<Object?>.from(decoded);
    if (decoded is Map && decoded['data'] is List) {
      return List<Object?>.from(decoded['data']! as List);
    }
    throw const SocialRequestException('云存储返回的数据格式不完整');
  }
}

List<SocialMessage> _messageRows(List<Object?> rows) => rows
    .map((item) => SocialMessage.fromJson(_map(item)))
    .toList(growable: false);

List<SocialConversation> _conversationRows(List<Object?> rows) => rows
    .map((item) => SocialConversation.fromJson(_map(item)))
    .toList(growable: false);

Future<List<SocialUser>> _usersAsync(Object? value) => _list(value).length < 100
    ? Future.value(_users(value))
    : compute(_users, value, debugLabel: 'social-users');

List<SocialUser> _users(Object? value) => _list(value)
    .map((item) => SocialUser.fromJson(_map(item)))
    .where((user) => user.uid.isNotEmpty)
    .toList(growable: false);

List<Object?> _list(Object? value) =>
    value is List ? List<Object?>.from(value) : const [];

Map<String, Object?> _map(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : const <String, Object?>{};

String? _text(Object? value) {
  final result = value?.toString().trim();
  return result == null || result.isEmpty ? null : result;
}

String? _chineseMessage(Object? value) {
  final message = _text(value);
  if (message == null || !RegExp(r'[\u3400-\u9FFF]').hasMatch(message)) {
    return null;
  }
  return message;
}

String _safeExtension(String path, SocialMessageKind kind) {
  final match = RegExp(r'\.[A-Za-z0-9]{2,5}$').firstMatch(path);
  final extension = match?.group(0)?.toLowerCase();
  if (kind == SocialMessageKind.image &&
      const {'.jpg', '.jpeg', '.png', '.webp', '.gif'}.contains(extension)) {
    return extension!;
  }
  if (kind == SocialMessageKind.video &&
      const {'.mp4', '.mov', '.webm', '.m4v'}.contains(extension)) {
    return extension!;
  }
  if (kind == SocialMessageKind.voice &&
      const {'.m4a', '.aac', '.mp3', '.wav'}.contains(extension)) {
    return extension!;
  }
  return switch (kind) {
    SocialMessageKind.image => '.jpg',
    SocialMessageKind.video => '.mp4',
    SocialMessageKind.voice => '.m4a',
    _ => '.bin',
  };
}

String _mimeType(String extension, SocialMessageKind kind) {
  if (kind == SocialMessageKind.video) {
    return extension == '.mov' ? 'video/quicktime' : 'video/mp4';
  }
  if (kind == SocialMessageKind.voice) {
    return switch (extension) {
      '.aac' => 'audio/aac',
      '.mp3' => 'audio/mpeg',
      '.wav' => 'audio/wav',
      _ => 'audio/mp4',
    };
  }
  return switch (extension) {
    '.png' => 'image/png',
    '.webp' => 'image/webp',
    '.gif' => 'image/gif',
    _ => 'image/jpeg',
  };
}
