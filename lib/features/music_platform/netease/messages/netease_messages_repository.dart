import 'netease_message_reads.dart';
import 'netease_message_counts.dart';
import 'netease_message_card.dart';
import '../../../../core/diagnostics/local_music_diagnostics.dart';
import '../../../../core/persistence/app_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../netease_music_repository.dart';
import '../full/netease_upload_workflows.dart';
import '../../data/music_platform_api.dart';
import '../../platform_backend_providers.dart';

Map<String, dynamic> _map(Object? value) {
  if (value is String) {
    try {
      value = jsonDecode(value);
    } on FormatException {
      return {};
    }
  }
  return NeteaseMusicRepository.object(value);
}

class NeteasePerson {
  const NeteasePerson(this.id, this.name, [this.avatar = '']);
  final String id, name, avatar;
  factory NeteasePerson.parse(Object? value) {
    final row = _map(value);
    return NeteasePerson(
      '${row['userId'] ?? row['id'] ?? ''}',
      '${row['remarkName'] ?? row['nickname'] ?? row['name'] ?? '网易云用户'}',
      '${row['avatarUrl'] ?? row['avatar'] ?? ''}',
    );
  }
}

/// Typed message parsing deliberately stops at the message boundary. A peer's
/// province, birthday and other account fields are never rendered as messages.
class NeteaseChatMessage {
  const NeteaseChatMessage({
    required this.id,
    required this.from,
    required this.to,
    required this.text,
    required this.time,
    this.image = '',
    this.link = '',
    this.resource = const {},
    this.card,
  });
  final String id, text, image, link;
  final NeteasePerson from, to;
  final DateTime time;
  final Map<String, dynamic> resource;
  final NeteaseMessageCard? card;
  factory NeteaseChatMessage.parse(Map<String, dynamic> row) {
    final legacy = _map(row['msg'] ?? row['lastMsg']);
    final content = legacy.isNotEmpty
        ? legacy
        : _map(row['msgBody'] ?? row['body']);
    final card = NeteaseMessageCard.parse({
      ...content,
      // Only message envelope fields cross this boundary. Sender/recipient
      // profiles can contain arbitrary titles or links and are not messages.
      for (final key in [
        'body',
        'data',
        'content',
        'msgBody',
        'json',
        'nativeUrl',
        'msgType',
        'generalMsg',
        'listenTogetherRecord',
        'listenTogetherInfo',
        'listenTogether',
        'extInfo',
        'extJsonInfo',
        'card',
        'cardInfo',
      ])
        if (row[key] != null) key: row[key],
    });
    final pic = _map(
      content['picInfo'] ?? content['picinfo'] ?? content['pic'],
    );
    final image =
        '${pic['picUrl'] ?? pic['url'] ?? content['picUrl'] ?? content['imageUrl'] ?? ''}';
    final res = _map(
      content['song'] ??
          content['playlist'] ??
          content['album'] ??
          content['mv'],
    );
    final raw = row['msg'];
    final text =
        '${content['msg'] ?? content['message'] ?? content['title'] ?? (res.isNotEmpty ? res['name'] : null) ?? (content.isEmpty && raw is String
                ? raw
                : image.isNotEmpty
                ? '[图片]'
                : '[分享内容]')}';
    return NeteaseChatMessage(
      id: '${row['id'] ?? row['msgId'] ?? row['time'] ?? ''}',
      from: NeteasePerson.parse(row['fromUser']),
      to: NeteasePerson.parse(row['toUser']),
      text: card?.summary ?? text,
      image: image,
      link: '${content['url'] ?? content['linkUrl'] ?? ''}',
      resource: res,
      card: card,
      time: DateTime.fromMillisecondsSinceEpoch(
        int.tryParse('${row['time'] ?? row['lastMsgTime']}') ?? 0,
      ),
    );
  }
}

class NeteaseConversation {
  const NeteaseConversation(this.peer, this.last, this.unread);
  final NeteasePerson peer;
  final NeteaseChatMessage last;
  final int unread;
  factory NeteaseConversation.parse(Map<String, dynamic> row, String self) {
    final last = NeteaseChatMessage.parse({
      ...row,
      'msg': row['lastMsg'] ?? row['msg'],
      'time': row['lastMsgTime'] ?? row['time'],
    });
    final peer = last.from.id == self ? last.to : last.from;
    return NeteaseConversation(
      peer,
      last,
      int.tryParse('${row['newMsgCount'] ?? row['unreadCount'] ?? 0}') ?? 0,
    );
  }
}

enum NeteaseNoticeKind { fans, comments, mentions, notices }

class NeteaseChatShare {
  const NeteaseChatShare(this.kind, this.id, this.name);
  final String kind, id, name;
}

class NeteaseMessageNotice {
  const NeteaseMessageNotice(
    this.id,
    this.person,
    this.text,
    this.time, {
    this.resourceId = '',
    this.resourceType = '',
    this.threadId = '',
  });
  final String id, text, resourceId, resourceType, threadId;
  final NeteasePerson person;
  final DateTime time;
  factory NeteaseMessageNotice.parse(
    Map<String, dynamic> row,
    NeteaseNoticeKind kind,
  ) {
    final notice = _map(row['notice'] ?? row['json']);
    final comment = _map(row['comment'] ?? notice['comment']);
    final resource = _map(row['resource'] ?? notice['resource']);
    final event = _map(row['event'] ?? notice['event']);
    final person = NeteasePerson.parse(
      row['user'] ?? notice['user'] ?? comment['user'] ?? row,
    );
    final text =
        '${row['content'] ?? comment['content'] ?? notice['content'] ?? notice['msg'] ?? event['msg'] ?? row['title'] ?? notice['title'] ?? (kind == NeteaseNoticeKind.fans ? '${person.name}关注了你' : '查看消息详情')}';
    return NeteaseMessageNotice(
      '${row['id'] ?? row['commentId'] ?? person.id}',
      person,
      text,
      DateTime.fromMillisecondsSinceEpoch(
        int.tryParse('${row['time'] ?? notice['time']}') ?? 0,
      ),
      resourceId: '${resource['id'] ?? row['resourceId'] ?? ''}',
      resourceType: '${resource['type'] ?? row['resourceType'] ?? ''}',
      threadId: '${row['threadId'] ?? resource['threadId'] ?? ''}',
    );
  }
}

final neteaseMessagesRepositoryProvider = Provider<NeteaseMessagesRepository>((
  ref,
) {
  final music = ref.watch(neteaseMusicRepositoryProvider);
  final prefs = ref.watch(sharedPreferencesProvider);
  final key = 'netease_message_read_v1:${music.api.session?.userId ?? "guest"}';
  Map<String, int> seen = {};
  try {
    seen = Map<String, int>.from(
      jsonDecode(prefs.getString(key) ?? '{}') as Map,
    );
  } catch (_) {
    /* Bad cursors never hide messages. */
  }
  final reads = NeteaseMessageReads(
    restored: seen,
    persist: (value) async {
      await prefs.setString(key, jsonEncode(value));
    },
  );
  final repository = NeteaseMessagesRepository(music, reads: reads);
  ref.onDispose(repository.dispose);
  return repository;
});

final neteaseMessageReadRevisionProvider = StreamProvider<int>((ref) {
  final repository = ref.watch(neteaseMessagesRepositoryProvider);
  return Stream<int>.multi((sink) {
    var revision = 0;
    sink.add(revision);
    final a = repository.reads.changes.listen((_) => sink.add(++revision));
    final b = repository.changes.listen((_) => sink.add(++revision));
    sink.onCancel = () async {
      await a.cancel();
      await b.cancel();
    };
  });
});

/// Every operation uses the account snapshot retained by the music repository.
/// Sends are explicit, single attempts; failed requests are reconciled by
/// reading history before the UI permits a deliberate resend.
class NeteaseMessagesRepository {
  NeteaseMessagesRepository(this.music, {NeteaseMessageReads? reads})
    : reads = reads ?? NeteaseMessageReads();
  final NeteaseMusicRepository music;
  final NeteaseMessageReads reads;
  final _rawConversations = <String, NeteaseConversation>{};
  final _updates = StreamController<void>.broadcast();
  Stream<void> get changes => _updates.stream;
  int get knownRawPrivateUnread => _rawConversations.values.fold(
    0,
    (sum, c) => sum + c.unread.clamp(0, 2147483647),
  );
  void dispose() {
    reads.close();
    unawaited(_updates.close());
  }

  NeteaseConversation visibleConversation(NeteaseConversation value) =>
      NeteaseConversation(
        value.peer,
        value.last,
        reads.includes(value.peer.id, value.last.time) ? 0 : value.unread,
      );
  Map<String, int> visibleCounts(Map<String, int> raw) {
    final suppressed = _rawConversations.values
        .where((c) => reads.includes(c.peer.id, c.last.time))
        .fold<int>(0, (n, c) => n + c.unread);
    final knownVisible = _rawConversations.values
        .map(visibleConversation)
        .fold<int>(0, (sum, c) => sum + c.unread.clamp(0, 2147483647));
    final serverVisible = ((raw['privateMsgCount'] ?? 0) - suppressed).clamp(
      0,
      2147483647,
    );
    return {
      ...raw,
      // The entry and message list must agree. A missing/failed total endpoint
      // cannot erase unread messages that the same account just returned.
      'privateMsgCount': knownVisible > serverVisible
          ? knownVisible
          : serverVisible,
    };
  }

  String get self => music.api.session?.userId ?? '';
  void check() {
    if (music.credential == null ||
        music.api.session?.credentialId != music.credential) {
      throw const MusicPlatformException('账号已变化，请重新打开我的消息');
    }
  }

  Future<Map<String, dynamic>> _request(
    String path,
    Map<String, Object?> data, {
    bool weapi = true,
    bool mobileMessages = false,
  }) {
    check();
    return music.api.request(
      path,
      data,
      weapi: weapi,
      expectedCredential: music.credential,
      mobileMessages: mobileMessages,
    );
  }

  Future<List<NeteaseConversation>> conversations([int offset = 0]) async {
    final r = await _request(
      '/api/msg/private/users',
      {'offset': offset, 'limit': 30, 'total': 'true'},
      weapi: false,
      mobileMessages: true,
    );
    final rows =
        NeteaseMusicRepository.rows(r['msgs'] ?? _map(r['data'])['msgs'])
            .map((row) => NeteaseConversation.parse(row, self))
            .where((c) => c.peer.id.isNotEmpty)
            .toList();
    if (offset == 0) _rawConversations.clear();
    for (final value in rows) {
      _rawConversations[value.peer.id] = value;
    }
    if (!_updates.isClosed) _updates.add(null);
    LocalMusicDiagnostics.record('messages.conversations', {
      'rows': rows.length,
      'knownUnread': knownRawPrivateUnread,
    });
    return rows;
  }

  Future<List<NeteaseChatMessage>> history(
    String peer, [
    int before = 0,
  ]) async {
    final r = await _request(
      '/api/msg/private/history',
      {'userId': peer, 'limit': 30, 'time': before, 'total': 'true'},
      weapi: false,
      mobileMessages: true,
    );
    return NeteaseMusicRepository.rows(
      r['msgs'] ?? _map(r['data'])['msgs'],
    ).map(NeteaseChatMessage.parse).toList();
  }

  Future<Map<String, int>> counts() async {
    final r = await _request('/api/pl/count', {});
    LocalMusicDiagnostics.record('messages.count_schema', {
      'fields': {
        for (final e in r.entries) e.key: e.value?.runtimeType.toString(),
      },
      'dataFields': {
        for (final e in _map(r['data']).entries)
          e.key: e.value?.runtimeType.toString(),
      },
    });
    final parsed = parseNeteaseMessageCounts(r);
    LocalMusicDiagnostics.record('messages.count_values', parsed);
    return parsed;
  }

  Future<List<NeteasePerson>> friends([int offset = 0]) async {
    final r = await music.call('/user/follows', {
      'uid': self,
      'offset': offset,
      'limit': 50,
    });
    return NeteaseMusicRepository.rows(
      r['follow'],
    ).map(NeteasePerson.parse).toList();
  }

  Future<List<NeteaseMessageNotice>> notices(
    NeteaseNoticeKind kind, [
    int before = -1,
    int offset = 0,
  ]) async {
    final path = switch (kind) {
      NeteaseNoticeKind.fans => '/api/user/getfolloweds/$self',
      NeteaseNoticeKind.comments => '/api/v1/user/comments/$self',
      NeteaseNoticeKind.mentions => '/api/forwards/get',
      NeteaseNoticeKind.notices => '/api/msg/notices',
    };
    final data = switch (kind) {
      NeteaseNoticeKind.fans => <String, Object?>{
        'userId': self,
        'limit': 30,
        'offset': offset,
        'time': '0',
        'getcounts': 'true',
      },
      NeteaseNoticeKind.comments => <String, Object?>{
        'uid': self,
        'limit': 30,
        'beforeTime': before,
        'total': 'true',
      },
      NeteaseNoticeKind.mentions => <String, Object?>{
        'limit': 30,
        'offset': offset,
        'total': 'true',
      },
      NeteaseNoticeKind.notices => <String, Object?>{
        'limit': 30,
        'time': before,
      },
    };
    final r = await _request(path, data, weapi: kind != NeteaseNoticeKind.fans);
    final rows =
        r['comments'] ?? r['forwards'] ?? r['notices'] ?? r['followeds'];
    return NeteaseMusicRepository.rows(
      rows,
    ).map((r) => NeteaseMessageNotice.parse(r, kind)).toList();
  }

  Future<List<NeteaseChatMessage>> sendText(String peer, String text) =>
      _send(peer, {'type': 'text', 'msg': text});
  Future<List<NeteaseChatMessage>> sendResource(
    String peer,
    NeteaseChatShare share,
    String text,
  ) {
    if (!{'song', 'album', 'playlist'}.contains(share.kind) ||
        !RegExp(r'^\d+$').hasMatch(share.id)) {
      throw const MusicPlatformException('请选择要分享的歌曲、专辑或歌单');
    }
    return _send(peer, {'type': share.kind, 'id': share.id, 'msg': text});
  }

  Future<List<NeteaseChatMessage>> sendPicture(
    String peer,
    Uint8List bytes,
    int width,
    int height,
  ) async {
    check();
    final uploaded = await NeteaseUploadWorkflows(
      music.api,
      music.credential!,
    ).chatPicture(bytes);
    check();
    return _send(peer, {
      'type': 'pic',
      'picinfo': jsonEncode({
        'picIdStr': uploaded.id,
        'width': width,
        'height': height,
        'format': uploaded.format,
        'type': 0,
      }),
    });
  }

  Future<List<NeteaseChatMessage>> _send(
    String peer,
    Map<String, Object?> body,
  ) async {
    if (!RegExp(r'^\d+$').hasMatch(peer) || peer == self) {
      throw const MusicPlatformException('请选择有效的收件人');
    }
    final r = await _request('/api/msg/private/send', {
      ...body,
      'userIds': jsonEncode([int.parse(peer)]),
    }, weapi: false);
    if ((r['sendblacklist'] as List? ?? const []).isNotEmpty ||
        (r['blacklist'] as List? ?? const []).isNotEmpty) {
      throw const MusicPlatformException('对方暂时无法接收此消息，请核对好友关系');
    }
    return NeteaseMusicRepository.rows(
      r['newMsgs'],
    ).map(NeteaseChatMessage.parse).toList();
  }
}
