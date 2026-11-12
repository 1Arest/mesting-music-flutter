import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/track.dart';
import '../../shared/widgets/artwork_image.dart';
import '../../shared/widgets/beta_glass_controls.dart';
import '../../shared/widgets/beta_glass_scroll_body.dart';
import '../music_platform/data/embedded_kugou_music_source.dart';
import '../music_platform/data/platform_category_search.dart';
import '../music_platform/data/platform_comments_repository.dart';
import '../music_platform/domain/platform_search_user.dart';
import '../music_platform/domain/platform_session.dart';
import '../music_platform/music_platform_providers.dart';
import '../music_platform/platform_backend_providers.dart';
import '../music_platform/netease/netease_comments_repository.dart';
import '../music_platform/netease/netease_features_page.dart';
import '../music_platform/netease/netease_features_repository.dart';
import '../music_platform/netease/netease_music_repository.dart';
import '../music_platform/netease/netease_user_page.dart';
import '../music_platform/netease/messages/netease_messages_page.dart';
import '../music_platform/netease/messages/netease_messages_repository.dart';
import '../music_platform/presentation/platform_catalog_detail_page.dart';
import '../music_platform/presentation/platform_recommendations_page.dart';
import '../music_platform/presentation/platform_comments_page.dart';
import '../music_platform/presentation/platform_design.dart';
import '../player/presentation/beta_playback_actions.dart';
import 'kugou_notice_history.dart';
import 'notification_pages.dart';
import 'notification_sources.dart';
import 'notification_target.dart';
import 'notification_comment_target.dart';

/// Cold/warm notifications share this destination. Account verification happens
/// before the page is constructed and after awaited metadata resolves; changing
/// a login while it is open never displays the previous account's conversation.
class MusicNoticeContentPage extends ConsumerStatefulWidget {
  const MusicNoticeContentPage({
    required this.platform,
    required this.scope,
    required this.target,
    super.key,
  });
  final MusicPlatform platform;
  final String scope;
  final NoticeTarget target;
  @override
  ConsumerState<MusicNoticeContentPage> createState() => _NoticeContentState();
}

class _NoticeContentState extends ConsumerState<MusicNoticeContentPage> {
  late Future<Widget> page = _load();
  bool _current() {
    final identity = ref.read(platformAccountProvider).value;
    return identity != null &&
        identity.platform == widget.platform &&
        NoticeAccount(identity).scope == widget.scope;
  }

  Future<Widget> _load() async {
    final retained = await readNoticeAccount(widget.platform);
    if (!mounted || retained?.scope != widget.scope || !_current()) {
      throw const FormatException('Retired notification');
    }
    final target = widget.target;
    if (target.kind == NoticeTargetKind.conversation) {
      if (widget.platform == MusicPlatform.netease) {
        return NeteaseChatPage(
          peer: NeteasePerson(
            target.id,
            target.name.isEmpty ? '网易云好友' : target.name,
          ),
        );
      }
      if (target.tag.isNotEmpty) {
        return _KugouNoticeChatPage(account: retained!, target: target);
      }
    }
    if (target.kind == NoticeTargetKind.user &&
        widget.platform == MusicPlatform.netease) {
      return NeteaseUserProfilePage(
        user: PlatformSearchUser(
          id: target.id,
          nickname: target.name.isEmpty ? '网易云用户' : target.name,
        ),
      );
    }
    if (target.kind == NoticeTargetKind.comment ||
        target.kind == NoticeTargetKind.event) {
      if (target.kind == NoticeTargetKind.event &&
          widget.platform == MusicPlatform.kugou) {
        throw const FormatException('Unsupported event destination');
      }
      final kind = target.kind == NoticeTargetKind.event
          ? PlatformCommentKind.event
          : PlatformCommentKind.values.firstWhere(
              (k) => k.name == target.resourceKind,
            );
      final resource = PlatformCommentResource(
        kind: kind,
        id: target.kind == NoticeTargetKind.event
            ? target.id
            : target.resourceId,
        name: target.name.isEmpty ? '消息相关内容' : target.name,
      );
      final session = ref.read(platformAccountProvider).value!;
      final PlatformCommentsRepository repository =
          widget.platform == MusicPlatform.netease
          ? NeteaseCommentsRepository(
              ref.read(musicPlatformApiProvider),
              session,
              ref.read(neteaseMusicRepositoryProvider),
            )
          : PlatformCommentsRepository(
              ref.read(musicPlatformApiProvider),
              session,
            );
      PlatformComment? thread;
      if (target.kind == NoticeTargetKind.comment) {
        thread = await resolveNoticeComment(repository, resource, target.id);
      }
      if (!mounted || !_current()) {
        throw const FormatException('Retired notification');
      }
      return PlatformCommentsPage(
        resource: resource,
        repository: repository,
        thread: thread,
        sourceCurrent: _current,
      );
    }
    if (target.kind == NoticeTargetKind.song) {
      final track = await _song(target);
      if (!mounted || !_current()) {
        throw const FormatException('Retired notification');
      }
      return _NoticeSongPage(track: track);
    }
    if ([
      NoticeTargetKind.album,
      NoticeTargetKind.playlist,
      NoticeTargetKind.artist,
    ].contains(target.kind)) {
      final kind = switch (target.kind) {
        NoticeTargetKind.album => PlatformSearchKind.albums,
        NoticeTargetKind.playlist => PlatformSearchKind.playlists,
        _ => PlatformSearchKind.artists,
      };
      return PlatformCatalogDetailPage(
        hit: PlatformSearchHit(
          kind: kind,
          id: target.id,
          globalId: kind == PlatformSearchKind.playlists ? target.id : '',
          title: target.name.isEmpty ? kind.label : target.name,
        ),
      );
    }
    if (target.kind == NoticeTargetKind.daily) {
      return const PlatformRecommendationDetail(title: '每日推荐');
    }
    return MusicNoticeCategoryPage(
      platform: widget.platform,
      target: target,
      reason: target.kind == NoticeTargetKind.daily
          ? ''
          : '这条消息暂时无法定位具体内容，已打开对应消息分类。',
    );
  }

  Future<Track> _song(NoticeTarget target) async {
    final id = target.id;
    if (widget.platform == MusicPlatform.netease) {
      final response = await ref.read(neteaseMusicRepositoryProvider).call(
        '/song/detail',
        {
          'ids': [id],
        },
      );
      final tracks = NeteaseMusicRepository.tracks(response['songs']);
      final track = tracks
          .where((t) => t.platformSongId == id || t.id == 'netease_$id')
          .firstOrNull;
      if (track != null) return track;
    } else if (target.hash.isNotEmpty) {
      // Kugou audio metadata requires its explicit hash, not a numeric ID.
      // Never search by title and accidentally open another recording.
      final response = await ref
          .read(musicPlatformApiProvider)
          .get(
            '/audio',
            query: {'hash': target.hash},
            expectedSession: ref.read(platformAccountProvider).value,
          );
      for (final row in sourceRows(response['data'])) {
        final track = EmbeddedKugouMusicSource.platformTrack(row);
        if (track != null && track.id.toLowerCase() == 'kugou_${target.hash}') {
          return track;
        }
      }
    }
    throw const FormatException('Song no longer available');
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(platformAccountProvider).value;
    if (identity == null ||
        identity.platform != widget.platform ||
        NoticeAccount(identity).scope != widget.scope) {
      return const PlatformPageFrame(
        title: '消息',
        child: Center(child: Text('账号已变化，请返回消息列表。')),
      );
    }
    return FutureBuilder<Widget>(
      future: page,
      builder: (context, snapshot) {
        if (snapshot.hasData) return snapshot.data!;
        if (snapshot.hasError) {
          return MusicNoticeCategoryPage(
            platform: widget.platform,
            target: widget.target,
            reason: '内容可能已删除或暂时无法读取，已打开对应消息分类。',
          );
        }
        return const PlatformPageFrame(
          title: '消息',
          child: Center(child: CupertinoActivityIndicator()),
        );
      },
    );
  }
}

/// The explicit fallback retains the source and category; it never jumps to an
/// unrelated home page, another account, or the official application's Intent.
class MusicNoticeCategoryPage extends StatelessWidget {
  const MusicNoticeCategoryPage({
    required this.platform,
    required this.target,
    this.reason = '',
    super.key,
  });
  final MusicPlatform platform;
  final NoticeTarget target;
  final String reason;
  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (platform == MusicPlatform.netease) {
      if (target.category == 'privateMessage') {
        child = const NeteaseMessagesPage();
      } else if (target.category == 'artist') {
        child = const NeteaseFeaturesPage(feed: NeteaseFeed.artistNewSongs);
      } else if (target.category == 'recommendation') {
        child = const PlatformRecommendationDetail(title: '每日推荐');
      } else {
        child = NeteaseNoticesPage(
          initial:
              NeteaseNoticeKind.values
                  .where((k) => k.name == target.section)
                  .firstOrNull ??
              NeteaseNoticeKind.notices,
        );
      }
    } else {
      child = MusicNotificationInboxPage(
        platform: platform.name,
        category: target.category,
      );
    }
    return Column(
      children: [
        if (reason.isNotEmpty)
          SafeArea(
            bottom: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Text(
                reason,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        Expanded(child: child),
      ],
    );
  }
}

class _NoticeSongPage extends ConsumerWidget {
  const _NoticeSongPage({required this.track});
  final Track track;
  @override
  Widget build(BuildContext context, WidgetRef ref) => PlatformPageFrame(
    title: track.title,
    child: BetaGlassScrollBody(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: ArtworkImage(uri: track.coverAsset, fit: BoxFit.cover),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(track.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(track.artist, style: Theme.of(context).textTheme.titleMedium),
        if (track.album.isNotEmpty) Text(track.album),
        const SizedBox(height: 24),
        BetaGlassButton(
          red: true,
          onPressed: () => playBetaSelection(context, ref, track),
          child: const Text('播放歌曲'),
        ),
        const SizedBox(height: 14),
        BetaGlassButton(
          blue: true,
          onPressed: () => openPlatformSongComments(context, ref, track),
          child: const Text('查看评论'),
        ),
      ],
    ),
  );
}

class _KugouNoticeChatPage extends StatefulWidget {
  const _KugouNoticeChatPage({required this.account, required this.target});
  final NoticeAccount account;
  final NoticeTarget target;
  @override
  State<_KugouNoticeChatPage> createState() => _KugouNoticeChatState();
}

class _KugouNoticeChatState extends State<_KugouNoticeChatPage> {
  late Future<List<KugouNoticeChatMessage>> messages = _load();
  Future<List<KugouNoticeChatMessage>> _load() async {
    final rows = await readKugouNoticeHistory(widget.account, widget.target);
    if ((await readNoticeAccount(MusicPlatform.kugou))?.scope !=
        widget.account.scope) {
      throw const FormatException('Retired conversation');
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) => PlatformPageFrame(
    title: widget.target.name.isEmpty ? '酷狗好友' : widget.target.name,
    child: FutureBuilder<List<KugouNoticeChatMessage>>(
      future: messages,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return MusicNoticeCategoryPage(
            platform: MusicPlatform.kugou,
            target: widget.target,
            reason: '会话暂时无法读取，已打开私信分类。',
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CupertinoActivityIndicator());
        }
        final rows = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async {
            setState(() => messages = _load());
            await messages;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 160),
            children: [
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('暂时没有可读取的聊天记录'),
                ),
              for (final row in rows)
                Align(
                  alignment: row.sender == widget.account.identity.userId
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    constraints: const BoxConstraints(maxWidth: 420),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: SelectableText(row.text),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}
