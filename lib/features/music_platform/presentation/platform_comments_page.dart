import 'source_comments_page.dart';
import '../../../shared/widgets/beta_page_motion.dart';
import 'platform_lazy_list.dart';
import '../../../shared/widgets/music_refresh_indicator.dart';
import '../../../shared/widgets/music_activity_indicator.dart';
import 'package:flutter/cupertino.dart';
import '../domain/platform_session.dart';
import '../platform_backend_providers.dart';
import '../netease/netease_comments_repository.dart';
import '../netease/netease_comment_hugs_page.dart';
import '../../../shared/widgets/beta_anchored_menu.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/cache/cached_browse_loader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/track.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_content_reveal.dart';
import '../../../shared/widgets/keyboard_visibility_builder.dart';
import '../data/platform_comments_repository.dart';
import '../data/music_platform_api.dart';
import '../music_platform_providers.dart';
import '../../auth/account_capabilities.dart';
import 'platform_comment_card.dart';
import 'platform_feedback.dart';
import 'platform_design.dart';
import 'platform_comment_composer.dart';
import '../../themes/music_theme_tokens.dart';
import '../../themes/music_typography.dart';

Future<void> openPlatformSongComments(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  if (!ref.read(showPlatformFeaturesProvider)) return;
  await Navigator.of(context, rootNavigator: true).push(
    MestingPageRoute<void>(builder: (_) => SourceCommentsPage(track: track)),
  );
}

/// Open the route immediately. Resolving old hash-only rows is visible and
/// retryable, rather than silently preventing entry with a toast.
class PlatformSongCommentsPage extends StatefulWidget {
  const PlatformSongCommentsPage({
    required this.track,
    required this.repository,
    super.key,
  });
  final Track track;
  final PlatformCommentsRepository repository;
  @override
  State<PlatformSongCommentsPage> createState() =>
      _PlatformSongCommentsPageState();
}

class _PlatformSongCommentsPageState extends State<PlatformSongCommentsPage> {
  late Future<PlatformCommentResource> _resource;
  @override
  void initState() {
    super.initState();
    _resource = widget.repository.songResource(widget.track);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<PlatformCommentResource>(
    future: _resource,
    builder: (context, snapshot) => snapshot.hasData
        ? PlatformCommentsPage(
            resource: snapshot.data!,
            repository: widget.repository,
          )
        : PlatformPageFrame(
            title: '歌曲评论',
            subtitle: widget.track.title,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: snapshot.hasError
                    ? PlatformFeedbackState(
                        loading: !snapshot.hasError,
                        message: snapshot.error is MusicPlatformException
                            ? (snapshot.error as MusicPlatformException).message
                            : '评论暂时无法加载',
                        retry: snapshot.hasError
                            ? () => setState(() {
                                _resource = widget.repository.songResource(
                                  widget.track,
                                );
                              })
                            : null,
                      )
                    : const BetaActivityIndicator(),
              ),
            ),
          ),
  );
}

void openPlatformPlaylistComments(
  BuildContext context,
  WidgetRef ref, {
  required String id,
  required String name,
}) {
  final session = ref.read(platformAccountProvider).value;
  if (!ref.read(showPlatformFeaturesProvider) || session == null) return;
  if (id.isEmpty) {
    showPlatformFailure(context, const MusicPlatformException('平台未返回歌单评论标识'));
    return;
  }
  // The source route may be replaced or disposed before a pushed page builds.
  // Capture its account-scoped repository now; a route builder cannot retain
  // the originating WidgetRef and read it after that element is deactivated.
  final repository = session.platform == MusicPlatform.netease
      ? NeteaseCommentsRepository(
          ref.read(musicPlatformApiProvider),
          session,
          ref.read(neteaseMusicRepositoryProvider),
        )
      : PlatformCommentsRepository(ref.read(musicPlatformApiProvider), session);
  Navigator.of(context, rootNavigator: true).push(
    MestingPageRoute<void>(
      builder: (_) => PlatformCommentsPage(
        resource: PlatformCommentResource(
          kind: PlatformCommentKind.playlist,
          id: id,
          name: name,
        ),
        repository: repository,
      ),
    ),
  );
}

/// Independent opaque route so account/mini-player surfaces cannot show
/// through. No write is issued until the user presses its explicit action.
class PlatformCommentsPage extends ConsumerStatefulWidget {
  const PlatformCommentsPage({
    required this.resource,
    required this.repository,
    this.thread,
    this.sourceCurrent,
    this.embedded = false,
    this.onSourceLogin,
    super.key,
  });
  final PlatformCommentResource resource;
  final PlatformCommentsRepository repository;
  final PlatformComment? thread;
  final bool Function()? sourceCurrent;

  /// Source tabs supply their single fixed frame. Standalone playlist/reply
  /// routes continue to own a complete frame through the default value.
  final bool embedded;
  final VoidCallback? onSourceLogin;
  @override
  ConsumerState<PlatformCommentsPage> createState() =>
      _PlatformCommentsPageState();
}

class _PlatformCommentsPageState extends ConsumerState<PlatformCommentsPage> {
  final _browse = CachedBrowseLoader();
  final _text = TextEditingController();
  List<PlatformComment> _comments = [];
  // Data revisions keep composer/focus/loading rebuilds from sorting the whole
  // loaded collection. In-place cache refreshes increment the revision too.
  int _commentRevision = 0, _derivedRevision = -1;
  PlatformCommentSort? _derivedSort;
  PlatformCommentScope? _derivedScope;
  List<PlatformComment> _derivedComments = const [];
  Map<Key, int> _derivedCommentIndices = const {};
  int _page = 0;
  int _generation = 0;
  bool _loading = false;
  bool _writing = false;
  bool _hasMore = false;
  bool _silentLoading = false;
  String? _error;
  PlatformComment? _reply;
  PlatformCommentSort _sort = PlatformCommentSort.hottest;
  PlatformCommentScope _scope = PlatformCommentScope.all;
  List<PlatformComment> _singers = [];
  String _childrenId = '';
  bool _nativeHot = false;
  String? _sortNotice;
  final _scroll = ScrollController();

  bool get _current =>
      ref.read(showPlatformFeaturesProvider) &&
      (widget.sourceCurrent?.call() ??
          (ref.read(platformAccountProvider).value?.ownerId ==
                  widget.repository.identity.ownerId &&
              ref.read(platformAccountProvider).value?.token ==
                  widget.repository.identity.token));

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients &&
          _scroll.position.extentAfter < 300 &&
          _hasMore &&
          _error == null) {
        _load();
      }
    });
    _load(reset: true);
  }

  @override
  void dispose() {
    _browse.dispose();
    _generation++;
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false, bool silent = false}) async {
    if (!_current || (_loading && !reset)) return;
    final generation = reset ? ++_generation : _generation;
    if (reset) _browse.reset();
    final page = reset ? 1 : _page + 1;
    setState(() {
      _loading = true;
      _silentLoading = silent;
      _error = null;
    });
    try {
      final requestedSort = _sort;
      var singers = _singers;
      var childrenId = _childrenId;
      var nativeHot = _nativeHot;
      String? sortNotice;
      final hotCursor = !reset && _nativeHot ? _childrenId : null;
      final resultPage = await _browse.load(
        key: page,
        request: () async {
          var result = widget.repository is NeteaseCommentsRepository
              ? await (widget.repository as NeteaseCommentsRepository)
                    .loadSorted(
                      widget.resource,
                      page: page,
                      thread: widget.thread,
                      sort: requestedSort,
                    )
              : await widget.repository.load(
                  widget.resource,
                  page: page,
                  thread: widget.thread,
                  hottestChildrenId: hotCursor,
                );
          if (reset) {
            singers = result.singerComments;
            childrenId = result.childrenId.isNotEmpty
                ? result.childrenId
                : result.comments.isNotEmpty
                ? result.comments.first.specialId
                : '';
            nativeHot =
                widget.repository is NeteaseCommentsRepository &&
                requestedSort == PlatformCommentSort.hottest;
            if (requestedSort == PlatformCommentSort.hottest &&
                widget.repository is! NeteaseCommentsRepository &&
                widget.thread == null &&
                widget.resource.kind == PlatformCommentKind.song &&
                childrenId.isNotEmpty) {
              try {
                result = await widget.repository.load(
                  widget.resource,
                  hottestChildrenId: childrenId,
                );
                nativeHot = true;
              } catch (_) {
                sortNotice = '最热列表暂不可用，当前按已加载评论的赞数排序';
              }
            }
          }
          return result;
        },
        onUpdate: (previous, current) {
          if (!mounted || generation != _generation || !_current) return;
          setState(() {
            replaceBrowsePage(
              _comments,
              previous.comments,
              current.comments,
              (comment) => comment.id,
              fallbackIndex: (page - 1) * 30,
            );
            if (page == 1) {
              _singers = singers;
              _childrenId = childrenId;
              _nativeHot = nativeHot;
              _sortNotice = sortNotice;
            }
            if (page == _page) _hasMore = current.hasMore;
            _commentRevision++;
          });
        },
      );
      final result = resultPage;
      if (!mounted || generation != _generation || !_current) return;
      setState(() {
        _singers = singers;
        _childrenId = childrenId;
        _nativeHot = nativeHot;
        if (reset) _sortNotice = sortNotice;
        final merged = <String, PlatformComment>{
          for (final row in reset ? <PlatformComment>[] : _comments)
            row.id: row,
        };
        for (final row in result.comments) {
          merged[row.id] = row;
        }
        final progressed = reset || merged.length > _comments.length;
        _comments = merged.values.toList();
        _page = page;
        _hasMore = result.hasMore && progressed;
        _commentRevision++;
      });
    } catch (error) {
      if (mounted && generation == _generation && !silent) {
        setState(
          () => _error = error is MusicPlatformException
              ? error.message
              : '评论暂时无法加载，请重试',
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _send() async {
    if (widget.repository.readOnly) return;
    if (_writing || !_current || _text.text.trim().isEmpty) return;
    setState(() => _writing = true);
    try {
      await widget.repository.send(
        widget.resource,
        _text.text,
        replyTo: _reply,
        thread: widget.thread,
      );
      if (!mounted || !_current) return;
      _text.clear();
      setState(() => _reply = null);
      // A committed write is already successful. Readback must neither delay
      // that acknowledgement nor insert an initial-loading panel in the list.
      showMusicNotice(
        context,
        icon: Icons.check_rounded,
        title: '已发送',
        message: '',
      );
      unawaited(_load(reset: true, silent: true));
    } catch (error) {
      if (mounted) showPlatformFailure(context, error);
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  Future<void> _delete(PlatformComment comment) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(
          '删除这条${widget.repository.identity.platformLabel}评论？',
          style: MusicTypography.titleEmphasis,
        ),
        content: Text('将删除你在${widget.repository.identity.platformLabel}发布的评论。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消', style: MusicTypography.regularText),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除', style: MusicTypography.regularText),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_current || _writing) return;
    setState(() => _writing = true);
    try {
      await widget.repository.delete(
        widget.resource,
        comment,
        thread: widget.thread,
      );
      await _load(reset: true);
    } catch (error) {
      if (mounted) showPlatformFailure(context, error);
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  Widget _commentRow(BuildContext context, PlatformComment comment) =>
      BetaContentReveal(
        key: ValueKey('comment-reveal-${comment.id}'),
        child: PlatformCommentCard(
          comment: comment,
          onHug:
              widget.repository is NeteaseCommentsRepository &&
                  !_writing &&
                  !widget.repository.readOnly
              ? () => Navigator.of(context, rootNavigator: true).push(
                  MestingPageRoute<void>(
                    builder: (_) => NeteaseCommentHugsPage(
                      repository:
                          widget.repository as NeteaseCommentsRepository,
                      resource: widget.resource,
                      comment: comment,
                    ),
                  ),
                )
              : null,
          onReaction:
              widget.repository is NeteaseCommentsRepository &&
                  !_writing &&
                  !widget.repository.readOnly
              ? () async {
                  if (!_current) return;
                  setState(() => _writing = true);
                  try {
                    await (widget.repository as NeteaseCommentsRepository).like(
                      widget.resource,
                      comment,
                    );
                    if (mounted && _current) {
                      await _load(reset: true, silent: true);
                    }
                  } catch (e) {
                    if (context.mounted) {
                      showPlatformFailure(context, e);
                    }
                  } finally {
                    if (mounted) {
                      setState(() => _writing = false);
                    }
                  }
                }
              : null,
          onReply: _writing || widget.repository.readOnly
              ? null
              : () => setState(() => _reply = comment),
          onDelete:
              !_writing &&
                  !widget.repository.readOnly &&
                  comment.userId == widget.repository.identity.userId
              ? () => _delete(comment)
              : null,
          onThread:
              widget.thread == null &&
                  (widget.resource.kind != PlatformCommentKind.mv ||
                      widget.repository is NeteaseCommentsRepository)
              ? () => Navigator.of(context, rootNavigator: true).push(
                  MestingPageRoute<void>(
                    builder: (_) => PlatformCommentsPage(
                      resource: widget.resource,
                      repository: widget.repository,
                      thread: comment,
                      sourceCurrent: widget.sourceCurrent,
                      onSourceLogin: widget.onSourceLogin,
                    ),
                  ),
                )
              : null,
        ),
      );

  List<PlatformComment> get _visibleComments {
    if (_derivedRevision == _commentRevision &&
        _derivedSort == _sort &&
        _derivedScope == _scope) {
      return _derivedComments;
    }
    final singerIds = _singers.map((row) => row.id).toSet();
    final entries =
        <String, PlatformComment>{
              if (widget.thread == null)
                for (final row in _singers) row.id: row,
              for (final row in _comments) row.id: row,
            }.values
            .where(
              (row) => switch (_scope) {
                PlatformCommentScope.all => true,
                PlatformCommentScope.singer =>
                  row.isSinger || singerIds.contains(row.id),
                PlatformCommentScope.mine =>
                  row.userId == widget.repository.identity.userId,
              },
            )
            .toList();
    // Like upstream, time sorting and scope filters cover loaded pages only.
    // Song hottest uses the dedicated global ranking endpoint when available.
    entries.sort(
      (a, b) => switch (_sort) {
        PlatformCommentSort.hottest => b.likes.compareTo(a.likes),
        PlatformCommentSort.newest => (b.time ?? DateTime(1970)).compareTo(
          a.time ?? DateTime(1970),
        ),
        PlatformCommentSort.oldest => (a.time ?? DateTime(1970)).compareTo(
          b.time ?? DateTime(1970),
        ),
      },
    );
    _derivedRevision = _commentRevision;
    _derivedSort = _sort;
    _derivedScope = _scope;
    _derivedCommentIndices = {
      for (var index = 0; index < entries.length; index++)
        ValueKey('comment-reveal-${entries[index].id}'): index,
    };
    return _derivedComments = List.unmodifiable(entries);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(showPlatformFeaturesProvider);
    ref.watch(platformAccountProvider);
    final entries = _visibleComments;
    final body = !_current
        ? const Center(child: Text('账号已变化，请返回当前账号页面'))
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        BetaAnchoredMenu<PlatformCommentSort>(
                          tooltip: '评论排序',
                          value: _sort,
                          values: widget.repository is NeteaseCommentsRepository
                              ? [
                                  PlatformCommentSort.hottest,
                                  PlatformCommentSort.newest,
                                ]
                              : PlatformCommentSort.values,
                          label: (sort) => switch (sort) {
                            PlatformCommentSort.hottest => '最热',
                            PlatformCommentSort.newest => '最新',
                            PlatformCommentSort.oldest => '最早',
                          },
                          onSelected: (sort) {
                            if (_sort != sort) {
                              setState(() => _sort = sort);
                              _load(reset: true);
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        BetaAnchoredMenu<PlatformCommentScope>(
                          tooltip: '评论范围',
                          value: _scope,
                          values: widget.repository is NeteaseCommentsRepository
                              ? [
                                  PlatformCommentScope.all,
                                  if (!widget.repository.readOnly)
                                    PlatformCommentScope.mine,
                                ]
                              : [
                                  for (final scope
                                      in PlatformCommentScope.values)
                                    if (!widget.repository.readOnly ||
                                        scope != PlatformCommentScope.mine)
                                      scope,
                                ],
                          label: (scope) => switch (scope) {
                            PlatformCommentScope.all => '全部',
                            PlatformCommentScope.singer => '歌手',
                            PlatformCommentScope.mine => '我的',
                          },
                          onSelected: (scope) => setState(() => _scope = scope),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _sortNotice ??
                          (_sort != PlatformCommentSort.hottest ||
                                  !_nativeHot ||
                                  _scope != PlatformCommentScope.all
                              ? '排序与筛选作用于已加载评论，可继续向下加载'
                              : '按平台最热评论排序'),
                      style: TextStyle(
                        fontSize: MusicTypography.smallCaptionSize,
                        color: context.musicThemeTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: MusicRefreshIndicator(
                        onRefresh: () => _load(reset: true),
                        child: buildPlatformLazyList(
                          controller: _scroll,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(18, 8, 18, 170),
                          header: [
                            if (widget.thread != null)
                              PlatformPanel(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.thread!.nickname,
                                      style: const TextStyle(
                                        fontWeight: MusicTypography.titleWeight,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(widget.thread!.content),
                                  ],
                                ),
                              ),
                            if (_loading &&
                                !_silentLoading &&
                                _comments.isEmpty)
                              const Padding(
                                key: ValueKey('comments-initial-loading'),
                                padding: EdgeInsets.symmetric(vertical: 36),
                                child: Center(child: BetaActivityIndicator()),
                              ),
                            if (_error != null)
                              PlatformFeedbackState(
                                message: _error!,
                                retry: () => _load(reset: _page == 0),
                              ),
                            if (!_loading && _error == null && entries.isEmpty)
                              PlatformFeedbackState(
                                message: _scope == PlatformCommentScope.all
                                    ? '暂时没有评论，来写下你的感受'
                                    : '已加载评论中暂无此类内容',
                              ),
                          ],
                          itemCount: entries.length,
                          findItemIndex: (key) => _derivedCommentIndices[key],
                          itemBuilder: (context, index) =>
                              _commentRow(context, entries[index]),
                          footer: [
                            if (_loading &&
                                !_silentLoading &&
                                _comments.isNotEmpty)
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(
                                  child: MusicActivityIndicator(
                                    independent: true,
                                  ),
                                ),
                              ),
                            if (_hasMore && !_loading)
                              TextButton.icon(
                                onPressed: _load,
                                icon: const Icon(Icons.expand_more_rounded),
                                label: const Text('加载更多'),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: widget.repository.readOnly
                          ? Material(
                              // A wrapped accessibility label must not
                              // overlap the scrolling comments beneath it.
                              color: Theme.of(context).colorScheme.surface,
                              child: SafeArea(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: TextButton.icon(
                                    onPressed: widget.onSourceLogin,
                                    icon: const Icon(Icons.login),
                                    label: Text(
                                      '登录${widget.repository.identity.platformLabel}后参与评论',
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : KeyboardVisibilityBuilder(
                              builder: (context, keyboardVisible) =>
                                  PlatformCommentComposer(
                                    keyboardVisible: keyboardVisible,
                                    controller: _text,
                                    sending: _writing,
                                    onSend: _send,
                                    reply: _reply?.nickname,
                                    onCancelReply: () =>
                                        setState(() => _reply = null),
                                  ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          );
    if (widget.embedded) return body;
    return PlatformPageFrame(
      musicChrome: false,
      title: widget.thread != null
          ? '评论回复'
          : widget.repository.identity.platform == MusicPlatform.netease
          ? '网易云评论'
          : '酷狗评论',
      subtitle: widget.resource.name,
      child: body,
    );
  }
}
