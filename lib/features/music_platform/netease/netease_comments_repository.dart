import '../../../shared/models/track.dart';
import '../data/music_platform_api.dart';
import '../data/platform_comments_repository.dart';
import 'netease_music_repository.dart';

class NeteaseCommentsRepository extends PlatformCommentsRepository {
  NeteaseCommentsRepository(
    super.api,
    super.identity,
    this.music, {
    super.readOnly,
  });
  final NeteaseMusicRepository music;
  final _replyCursors = <String, int>{};
  final _listCursors = <String, String>{};
  String _thread(PlatformCommentResource resource) =>
      '${switch (resource.kind) {
        PlatformCommentKind.song => 'R_SO_4_',
        PlatformCommentKind.playlist => 'A_PL_0_',
        PlatformCommentKind.album => 'R_AL_3_',
        PlatformCommentKind.mv => 'R_MV_5_',
        PlatformCommentKind.podcast => 'A_DJ_1_',
        PlatformCommentKind.video => 'R_VI_62_',
        PlatformCommentKind.event => 'A_EV_2_',
        PlatformCommentKind.radio => 'A_DR_14_',
      }}${resource.id}';

  @override
  Future<PlatformCommentResource> songResource(Track track) async {
    if (track.source != TrackSource.netease) {
      throw const MusicPlatformException('请选择当前平台的歌曲评论');
    }
    return PlatformCommentResource(
      kind: PlatformCommentKind.song,
      id: NeteaseMusicRepository.songId(track.id),
      name: track.title,
    );
  }

  PlatformComment _comment(Map<String, dynamic> row) {
    final user = NeteaseMusicRepository.object(row['user']);
    return PlatformComment(
      id: '${row['commentId']}',
      userId: '${user['userId'] ?? ''}',
      nickname: '${user['nickname'] ?? ''}',
      content: '${row['content'] ?? ''}',
      avatar: '${user['avatarUrl'] ?? ''}',
      specialId: '${row['commentId']}',
      likes: int.tryParse('${row['likedCount']}') ?? 0,
      liked: row['liked'] == true,
      replies: int.tryParse('${row['replyCount']}') ?? 0,
      time: DateTime.fromMillisecondsSinceEpoch(
        int.tryParse('${row['time']}') ?? 0,
      ),
    );
  }

  @override
  Future<PlatformCommentPage> load(
    PlatformCommentResource resource, {
    int page = 1,
    PlatformComment? thread,
    String? hottestChildrenId,
  }) => loadSorted(
    resource,
    page: page,
    thread: thread,
    sort: hottestChildrenId == null
        ? PlatformCommentSort.newest
        : PlatformCommentSort.hottest,
  );

  Future<PlatformCommentPage> loadSorted(
    PlatformCommentResource resource, {
    int page = 1,
    PlatformComment? thread,
    required PlatformCommentSort sort,
  }) async {
    final cursorKey = '${_thread(resource)}:${sort.name}';
    final payload = await music
        .call(thread == null ? '/comment/new' : '/comment/floor', {
          'threadId': _thread(resource),
          'page': page,
          'pageSize': platformCommentPageSize,
          'sortType': sort == PlatformCommentSort.hottest ? 2 : 3,
          'cursor': page == 1
              ? '0'
              : _listCursors['$cursorKey:${page - 1}'] ?? '0',
          if (thread != null) 'parentId': thread.id,
          if (thread != null)
            'time': page == 1
                ? -1
                : _replyCursors['${thread.id}:${page - 1}'] ?? -1,
        });
    final data = NeteaseMusicRepository.object(payload['data']);
    final rows = NeteaseMusicRepository.rows(data['comments']);
    _listCursors['$cursorKey:$page'] =
        '${data['cursor'] ?? (rows.isEmpty ? '0' : rows.last['time'])}';
    if (thread != null && rows.isNotEmpty) {
      _replyCursors['${thread.id}:$page'] =
          int.tryParse('${rows.last['time']}') ?? -1;
    }
    return PlatformCommentPage(
      rows.map(_comment).toList(),
      data['hasMore'] == true,
      total: int.tryParse('${data['totalCount'] ?? data['total']}'),
    );
  }

  Future<void> like(
    PlatformCommentResource resource,
    PlatformComment comment,
  ) async {
    requireWritable();
    await music.call('/comment/like', {
      'threadId': _thread(resource),
      'commentId': comment.id,
      'like': !comment.liked,
    });
  }

  Future<void> hug(
    PlatformCommentResource resource,
    PlatformComment comment,
  ) async {
    requireWritable();
    await music.api.request('/api/v2/resource/comments/hug/listener', {
      'targetUserId': comment.userId,
      'commentId': comment.id,
      'threadId': _thread(resource),
    }, expectedCredential: music.credential);
  }

  Future<Map<String, dynamic>> hugs(
    PlatformCommentResource resource,
    PlatformComment comment, {
    int page = 1,
    String cursor = '-1',
    String idCursor = '-1',
  }) => music.api.request('/api/v2/resource/comments/hug/list', {
    'targetUserId': comment.userId,
    'commentId': comment.id,
    'threadId': _thread(resource),
    'pageNo': page,
    'cursor': cursor,
    'idCursor': idCursor,
    'pageSize': 30,
  }, expectedCredential: music.credential);

  @override
  Future<void> send(
    PlatformCommentResource resource,
    String content, {
    PlatformComment? replyTo,
    PlatformComment? thread,
  }) async {
    requireWritable();
    final text = content.trim();
    if (text.isEmpty || text.length > 1000) {
      throw const MusicPlatformException('评论请输入 1 至 1000 个字符');
    }
    final reply = replyTo ?? thread;
    await music.call('/comment/write', {
      'threadId': _thread(resource),
      'action': reply == null ? 'add' : 'reply',
      'content': text,
      if (reply != null) 'commentId': reply.id,
    });
  }

  @override
  Future<void> delete(
    PlatformCommentResource resource,
    PlatformComment comment, {
    PlatformComment? thread,
  }) async {
    requireWritable();
    if (comment.userId != identity.userId) {
      throw const MusicPlatformException('只能删除当前账号发布的评论');
    }
    await music.call('/comment/write', {
      'threadId': _thread(resource),
      'action': 'delete',
      'commentId': comment.id,
    });
  }
}
