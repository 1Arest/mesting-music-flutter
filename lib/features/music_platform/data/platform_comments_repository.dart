import '../../../shared/models/track.dart';
import '../domain/platform_session.dart';
import 'music_platform_api.dart';
import 'platform_song_identity.dart';

enum PlatformCommentKind {
  song,
  playlist,
  album,
  mv,
  podcast,
  video,
  event,
  radio,
}

enum PlatformCommentSort { hottest, newest, oldest }

enum PlatformCommentScope { all, singer, mine }

class PlatformCommentResource {
  const PlatformCommentResource({
    required this.kind,
    required this.id,
    required this.name,
    this.hash = '',
  });
  final PlatformCommentKind kind;

  /// A song mixsongid or playlist global_collection_id, never a local UUID.
  final String id;
  final String name;
  final String hash;
  String get code => kind == PlatformCommentKind.song
      ? 'fc4be23b4e972707f36b8a828a93ba8a'
      : 'ca53b96fe5a1d9c22d71c8f522ef7c4f';
}

class PlatformComment {
  const PlatformComment({
    required this.id,
    required this.userId,
    required this.nickname,
    required this.content,
    this.avatar = '',
    this.specialId = '',
    this.replies = 0,
    this.likes = 0,
    this.liked = false,
    this.isSinger = false,
    this.time,
  });
  final String id;
  final String userId;
  final String nickname;
  final String content;
  final String avatar;
  final String specialId;
  final int replies;
  final int likes;
  final bool liked;
  final bool isSinger;
  final DateTime? time;

  factory PlatformComment.fromJson(
    Map<String, dynamic> row, {
    String childrenId = '',
  }) {
    final user = MusicPlatformApi.objectMap(row['user']);
    final like = MusicPlatformApi.objectMap(row['like']);
    final vinfo = MusicPlatformApi.objectMap(row['vinfo9']);
    final rawTime = row['createtime'] ?? row['addtime'] ?? row['time'];
    final stamp = int.tryParse('$rawTime');
    return PlatformComment(
      id: '${row['commentid'] ?? row['id'] ?? row['comment_id'] ?? ''}',
      userId:
          '${row['user_id'] ?? row['userid'] ?? row['kugouid'] ?? user['userid'] ?? user['id'] ?? ''}',
      nickname:
          '${row['user_name'] ?? row['username'] ?? row['nickname'] ?? user['name'] ?? user['nickname'] ?? '酷狗用户'}',
      avatar: PlatformSession.picture(
        row['user_pic'] ??
            row['user_img'] ??
            row['avatar'] ??
            user['avatar'] ??
            user['pic'],
      ),
      content: '${row['content'] ?? row['comment_text'] ?? ''}',
      specialId:
          '${row['special_child_id'] ?? row['special_id'] ?? row['childrenid'] ?? childrenId}',
      replies:
          int.tryParse('${row['reply_num'] ?? row['reply_count'] ?? 0}') ?? 0,
      likes:
          int.tryParse(
            '${like['count'] ?? row['like_count'] ?? row['likes'] ?? row['like_num'] ?? row['reply_like_count'] ?? 0}',
          ) ??
          0,
      liked: '${like['is_like'] ?? row['is_like'] ?? row['liked'] ?? 0}' == '1',
      isSinger:
          [
            true,
            1,
            '1',
          ].contains(row['isAuthor'] ?? row['is_author'] ?? row['is_star']) ||
          '${vinfo['singer_status']}' == '4',
      time: stamp != null && stamp > 0
          ? DateTime.fromMillisecondsSinceEpoch(
              stamp > 100000000000 ? stamp : stamp * 1000,
            )
          : DateTime.tryParse('$rawTime'),
    );
  }
}

class PlatformCommentPage {
  const PlatformCommentPage(
    this.comments,
    this.hasMore, {
    this.childrenId = '',
    this.total,
    this.singerComments = const [],
  });
  final List<PlatformComment> comments;
  final bool hasMore;
  final String childrenId;
  final int? total;
  final List<PlatformComment> singerComments;
}

/// The repository is pinned to a real platform credential. Mesting credentials
/// are not accepted here. Remote permission checks remain authoritative; local
/// ownership checks additionally keep delete controls off other users' comments.
class PlatformCommentsRepository {
  PlatformCommentsRepository(this.api, this.identity);
  final MusicPlatformApi api;
  final PlatformSession identity;
  final _repairedSongIds = <String, String>{};

  Future<PlatformCommentResource> songResource(Track track) async {
    if (track.source != TrackSource.kugou || !track.id.startsWith('kugou_')) {
      throw const MusicPlatformException('此歌曲不属于酷狗评论区');
    }
    var id = (int.tryParse(track.platformSongId) ?? 0) > 0
        ? track.platformSongId
        : '';
    // Older saved rows have only a hash. Resolve structured metadata without
    // guessing a numeric ID from that hash or from a same-title recording.
    if (id.isEmpty) {
      final result = await api.get(
        '/audio',
        query: {'hash': track.id.substring(6)},
        expectedSession: identity,
      );
      id = PlatformSongIdentity.fromPayload(result);
    }
    if (id.isEmpty) {
      final result = await api.get(
        '/song/url',
        query: {'hash': track.id.substring(6), 'quality': '128'},
        expectedSession: identity,
        allowBusinessError: true,
      );
      id = PlatformSongIdentity.fromPayload(result);
    }
    if (id.isEmpty) {
      throw const MusicPlatformException('平台未返回歌曲评论标识，请稍后重试');
    }
    return PlatformCommentResource(
      kind: PlatformCommentKind.song,
      id: id,
      name: track.title,
      hash: track.id.substring(6),
    );
  }

  Future<PlatformCommentPage> load(
    PlatformCommentResource resource, {
    int page = 1,
    PlatformComment? thread,
    String? hottestChildrenId,
  }) async {
    final reply = thread != null;
    if (reply && thread.specialId.isEmpty) {
      throw const MusicPlatformException('此评论缺少回复标识，请刷新评论区');
    }
    final path = hottestChildrenId != null
        ? '/comment/music/topliked'
        : reply
        ? '/comment/floor'
        : resource.kind == PlatformCommentKind.song
        ? '/comment/music'
        : '/comment/playlist';
    final query = <String, String>{
      'page': '$page',
      'pagesize': '30',
      if (hottestChildrenId != null)
        'childrenid': hottestChildrenId
      else if (reply) ...{
        'special_id': thread.specialId,
        'tid': thread.id,
        'resource_type': resource.kind.name,
        'code': resource.code,
      } else if (resource.kind == PlatformCommentKind.song)
        'mixsongid': _repairedSongIds[resource.hash] ?? resource.id
      else
        'id': resource.id,
    };
    Future<Map<String, dynamic>> request() =>
        api.get(path, query: query, expectedSession: identity);
    Map<String, dynamic> payload;
    try {
      payload = await request();
    } on MusicPlatformException catch (error) {
      if (error.code == '20028') {
        // Same documented device-registration recovery used for playback.
        // This is a bounded read retry; comment writes are never retried.
        await api.registerDevice();
        payload = await request();
      } else if (!reply &&
          hottestChildrenId == null &&
          resource.kind == PlatformCommentKind.song &&
          resource.hash.isNotEmpty &&
          error.code != '20017' &&
          error.code != '20018' &&
          error.code != '60045') {
        final metadata = await api.get(
          '/audio',
          query: {'hash': resource.hash},
          expectedSession: identity,
        );
        final repaired = PlatformSongIdentity.fromPayload(metadata);
        if (repaired.isEmpty || repaired == resource.id) rethrow;
        query['mixsongid'] = repaired;
        payload = await request();
        _repairedSongIds[resource.hash] = repaired;
      } else {
        rethrow;
      }
    }
    final data = MusicPlatformApi.objectMap(payload['data'] ?? payload);
    final raw = data['list'] ?? data['comments'] ?? const [];
    if (raw is! List) throw const MusicPlatformException('评论数据格式异常，请重试');
    final childrenId =
        '${data['childrenid'] ?? payload['childrenid'] ?? hottestChildrenId ?? thread?.specialId ?? ''}';
    final comments = raw
        .whereType<Map>()
        .map(
          (row) => PlatformComment.fromJson(
            MusicPlatformApi.objectMap(row),
            childrenId: childrenId,
          ),
        )
        .where((row) => row.id.isNotEmpty)
        .toList();
    final total = int.tryParse(
      '${data['total'] ?? data['count'] ?? data['comment_count'] ?? data['comments_num'] ?? ''}',
    );
    return PlatformCommentPage(
      comments,
      total == null ? raw.length == 30 : page * 30 < total,
      childrenId: childrenId,
      total: total,
      singerComments: _singers(data),
    );
  }

  static List<PlatformComment> _singers(Map<String, dynamic> data) {
    final result = <String, PlatformComment>{};
    for (final key in [
      'star_cmts',
      'star_comment',
      'weight_list',
      'hot_list',
    ]) {
      final candidate = data[key];
      final rows = candidate is Map ? candidate['list'] : candidate;
      if (rows is! List) continue;
      for (final row in rows.whereType<Map>()) {
        final parsed = PlatformComment.fromJson({
          ...MusicPlatformApi.objectMap(row),
          if (key.startsWith('star')) 'is_star': 1,
        }, childrenId: '${data['childrenid'] ?? ''}');
        if (parsed.id.isNotEmpty &&
            (key.startsWith('star') || parsed.isSinger)) {
          result[parsed.id] = parsed;
        }
      }
    }
    return result.values.toList();
  }

  Future<void> _write(String path, Map<String, String> query) async {
    final result = await api.post(
      path,
      query: query,
      expectedSession: identity,
    );
    final code = '${result['error_code'] ?? result['err_code'] ?? '0'}';
    if ('${result['status']}' == '1' && code == '0') return;
    // Do not echo upstream text: it may contain credentials or request content.
    if (code == '20028' || code == '60045') {
      throw const MusicPlatformException('酷狗要求安全验证，请先在酷狗客户端完成验证后重试');
    }
    if (code == '20018' || code == '20017') {
      throw const MusicPlatformException('酷狗登录状态已失效，请退出后重新登录');
    }
    throw MusicPlatformException('酷狗未确认此次操作成功（错误码 $code），请刷新后核对，勿连续重复提交');
  }

  Future<void> send(
    PlatformCommentResource resource,
    String content, {
    PlatformComment? replyTo,
    PlatformComment? thread,
  }) async {
    final text = content.trim();
    if (text.isEmpty || text.length > 1000) {
      throw const MusicPlatformException('评论请输入 1 至 1000 个字符');
    }
    final root = thread ?? replyTo;
    if (root != null && root.specialId.isEmpty) {
      throw const MusicPlatformException('缺少回复标识，请刷新评论区');
    }
    await _write(
      root != null
          ? '/comment/floor/send'
          : resource.kind == PlatformCommentKind.song
          ? '/comment/music/send'
          : '/comment/playlist/send',
      {
        'content': text,
        'name': resource.name,
        if (root != null) ...{
          'special_id': root.specialId,
          'tid': root.id,
          'resource_type': resource.kind.name,
          'code': resource.code,
          if (thread != null && replyTo != null && replyTo.id != thread.id)
            'pid': replyTo.id,
        } else if (resource.kind == PlatformCommentKind.song)
          'mixsongid': resource.id
        else
          'id': resource.id,
      },
    );
  }

  Future<void> delete(
    PlatformCommentResource resource,
    PlatformComment comment, {
    PlatformComment? thread,
  }) async {
    if (comment.userId.isEmpty || comment.userId != identity.userId) {
      throw const MusicPlatformException('只能删除当前酷狗账号发布的评论');
    }
    if (comment.specialId.isEmpty) {
      throw const MusicPlatformException('缺少删除标识，请刷新评论区');
    }
    await _write('/comment/music/del', {
      'cid': comment.id,
      'special_id': comment.specialId,
      'resource_type': resource.kind.name,
      'code': resource.code,
      if (thread != null) 'tid': thread.id,
      if (resource.kind == PlatformCommentKind.song) 'mixsongid': resource.id,
    });
  }
}
