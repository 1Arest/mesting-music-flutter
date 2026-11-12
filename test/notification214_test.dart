import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/notifications/notification_target.dart';
import 'package:mesting_music/features/notifications/notification_sources.dart';
import 'package:mesting_music/features/notifications/notification_models.dart';
import 'package:mesting_music/features/notifications/kugou_notice_history.dart';
import 'package:mesting_music/features/notifications/notification_comment_target.dart';
import 'package:mesting_music/features/music_platform/data/platform_comments_repository.dart';
import 'package:mesting_music/features/music_platform/netease/messages/netease_messages_repository.dart';
import 'package:mesting_music/features/music_platform/netease/footprint/official_report_extras.dart';

class _CommentPage implements PlatformCommentsRepository {
  _CommentPage(this.comments);
  final List<PlatformComment> comments;
  int reads = 0;
  @override
  Future<PlatformCommentPage> load(
    PlatformCommentResource resource, {
    int page = 1,
    PlatformComment? thread,
    String? hottestChildrenId,
  }) async {
    reads++;
    return PlatformCommentPage(comments, false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'Kugou comment opens the exact available floor and never a neighbor',
    () async {
      const comment = PlatformComment(
        id: '42',
        userId: '9',
        nickname: '朋友',
        content: '回复',
        specialId: '73',
      );
      final repository = _CommentPage([
        const PlatformComment(
          id: '41',
          userId: '8',
          nickname: '其他人',
          content: '其他评论',
          specialId: '72',
        ),
        comment,
      ]);
      const resource = PlatformCommentResource(
        kind: PlatformCommentKind.song,
        id: '123',
        name: '歌曲',
      );
      expect(
        await resolveNoticeComment(repository, resource, '42'),
        same(comment),
      );
      await expectLater(
        resolveNoticeComment(repository, resource, '43'),
        throwsFormatException,
      );
      expect(repository.reads, 2);
      const unsupported = PlatformCommentResource(
        kind: PlatformCommentKind.album,
        id: '123',
        name: '专辑',
      );
      await expectLater(
        resolveNoticeComment(repository, unsupported, '42'),
        throwsFormatException,
      );
      expect(repository.reads, 2);
      expect(
        NoticeTarget.fromJson({
          'kind': 'comment',
          'resourceKind': 'song',
          'resourceId': '123',
        }).kind,
        NoticeTargetKind.category,
      );
    },
  );
  test(
    'old private notification retains explicit peer after process death',
    () {
      final route = Uri.parse(
        noticeDestinationRoute({
          'platform': 'netease',
          'scope': 'owner',
          'kind': 'privateMessage',
          'peer': '42',
          'title': '好友',
        }),
      );
      expect(route.path, '/music/notice-content');
      expect(route.queryParameters['kind'], 'conversation');
      expect(route.queryParameters['id'], '42');
      expect(route.queryParameters['scope'], 'owner');
    },
  );
  test(
    'all typed destinations survive persisted notification and URI roundtrip',
    () {
      for (final kind in NoticeTargetKind.values) {
        final row = {
          'platform': 'netease',
          'scope': 'owner',
          'target': jsonEncode(
            NoticeTarget(
              kind: kind,
              id: '42',
              resourceKind: 'song',
              resourceId: '123',
              category: 'artist',
              name: 'A & B',
            ).toJson(),
          ),
        };
        final target = NoticeTarget.fromJson(
          Uri.parse(noticeDestinationRoute(row)).queryParameters,
        );
        expect(target.kind, kind);
        expect(target.name, 'A & B');
        expect(target.category, 'artist');
      }
    },
  );
  test(
    'missing malformed or executable identifiers fall back to their category',
    () {
      for (final id in [
        '',
        '0',
        '-1',
        '../auth',
        'https://example.com',
        '1&route=/auth',
      ]) {
        final target = NoticeTarget.fromJson({
          'kind': 'song',
          'id': id,
          'category': 'recommendation',
        });
        expect(target.kind, NoticeTargetKind.category);
        expect(target.category, 'recommendation');
      }
      expect(
        NoticeTarget.fromJson({'kind': 'comment', 'id': '2'}).kind,
        NoticeTargetKind.category,
      );
    },
  );
  test(
    'NetEase fans, nested comments, resource comments and deleted targets',
    () {
      expect(
        neteaseNoticeTarget(category: 'fans', userId: '42').kind,
        NoticeTargetKind.user,
      );
      final notice = NeteaseMessageNotice.parse({
        'comment': {'commentId': 66, 'threadId': 'R_SO_4_123', 'content': '回复'},
      }, NeteaseNoticeKind.comments);
      final target = neteaseNoticeTarget(
        category: 'comments',
        commentId: notice.commentId,
        threadId: notice.threadId,
      );
      expect(target.id, '66');
      expect(target.resourceId, '123');
      expect(target.resourceKind, 'song');
      for (final prefix in {
        'A_PL_0_': 'playlist',
        'R_AL_3_': 'album',
        'R_MV_5_': 'mv',
        'A_DJ_1_': 'podcast',
      }.entries) {
        expect(
          neteaseNoticeTarget(
            category: 'mentions',
            commentId: '66',
            threadId: '${prefix.key}123',
          ).resourceKind,
          prefix.value,
        );
      }
      final deleted = neteaseNoticeTarget(category: 'mentions');
      expect(deleted.kind, NoticeTargetKind.category);
      expect(deleted.section, 'mentions');
    },
  );
  test(
    'Kugou chat uses server tag; songs require explicit hash, URLs never route',
    () {
      final chat = kugouNoticeTarget(
        {'uid': 42, 'tag': '___CHAT:42:8___'},
        {'title': '好友'},
        MusicNoticeKind.privateMessage,
      );
      expect(chat.kind, NoticeTargetKind.conversation);
      expect(chat.tag, '___CHAT:42:8___');
      final song = kugouNoticeTarget({}, {
        'resource': {'type': 'song', 'hash': 'a' * 32},
      }, MusicNoticeKind.recommendation);
      expect(song.kind, NoticeTargetKind.song);
      expect(song.hash, 'a' * 32);
      final unknown = kugouNoticeTarget({}, {
        'url': 'kugou://open/123',
      }, MusicNoticeKind.artist);
      expect(unknown.kind, NoticeTargetKind.category);
      expect(unknown.category, 'artist');
    },
  );
  test(
    'Kugou conversation rejects business errors and orders message history',
    () {
      expect(
        () => parseKugouNoticeHistory({'status': 0, 'list': []}),
        throwsFormatException,
      );
      final rows = parseKugouNoticeHistory({
        'status': 1,
        'list': [
          {
            'msgid': 2,
            'uid': 42,
            'addtime': 20,
            'message': jsonEncode({'content': '第二条'}),
          },
          {
            'msgid': 1,
            'uid': 8,
            'addtime': 10,
            'message': {'content': '第一条'},
          },
        ],
      });
      expect(rows.map((r) => r.text), ['第一条', '第二条']);
      expect(rows.first.time, 10000);
    },
  );
  test(
    'official sections zip with songItems; percentages do not normalize',
    () {
      final extras = OfficialReportExtras.parse({
        'topAgeBlock': {
          'sections': [
            {'age': 2020},
            {'age': 2010},
            {'age': 2000},
          ],
          'songItems': [
            {
              'songId': 42,
              'picUrl': 'https://example.com/42.jpg',
              'songName': '代表作',
            },
            {'songId': 43, 'picUrl': 'https://example.com/43.jpg'},
          ],
        },
        'topLanguageBlock': {
          'sections': [
            {'language': '华语', 'percent': 74},
            {'language': '英语', 'percent': 30},
            {'language': '粤语', 'percent': 2},
          ],
        },
      });
      expect(extras.ages.map((a) => a.cover), [
        'https://example.com/42.jpg',
        'https://example.com/43.jpg',
        '',
      ]);
      expect(extras.ages.first.id, '42');
      expect(extras.languages.map((l) => l.percent), [74, 30, 2]);
    },
  );
}
