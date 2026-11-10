import 'platform_feedback.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/beta_swipe_pages.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/track.dart';
import '../data/linked_music_recordings.dart';
import '../data/music_platform_api.dart';
import '../data/platform_comments_repository.dart';
import '../domain/platform_session.dart';
import '../linked_music_providers.dart';
import '../netease/netease_comments_repository.dart';
import '../source_media_scope.dart';
import 'platform_comments_page.dart';
import 'platform_design.dart';
import 'source_login_prompt.dart';
import '../data/linked_music_mvs.dart';

/// Standalone MV comments also discover counterpart metadata. Opening comments
/// before the player finishes discovery must not permanently omit the other tab.
class LinkedMvCommentsPage extends ConsumerStatefulWidget {
  const LinkedMvCommentsPage({
    required this.track,
    this.mvId,
    this.initialSource,
    this.seedChoices = const [],
    super.key,
  });
  final Track track;
  final String? mvId;
  final TrackSource? initialSource;
  final List<LinkedMvChoice> seedChoices;
  @override
  ConsumerState<LinkedMvCommentsPage> createState() =>
      _LinkedMvCommentsPageState();
}

class _LinkedMvCommentsPageState extends ConsumerState<LinkedMvCommentsPage> {
  late final _known = {for (final c in widget.seedChoices) c.source: c};
  late Stream<LinkedMusicMvs> _stream = _discover();
  Stream<LinkedMusicMvs> _discover() => discoverLinkedMusicMvs(
    widget.track,
    mvId: widget.mvId,
    isCurrent: () => mounted,
    repositories: (s) => ref.read(linkedMvSourceProvider(s).future),
  );
  @override
  Widget build(BuildContext context) => StreamBuilder<LinkedMusicMvs>(
    stream: _stream,
    builder: (context, snapshot) {
      for (final choice in snapshot.data?.choices ?? <LinkedMvChoice>[]) {
        _known[choice.source] = choice;
      }
      if (_known.isNotEmpty) {
        return SourceCommentsPage(
          track: widget.track,
          initialSource: widget.initialSource,
          discoveryLoading:
              snapshot.data?.discovering ??
              snapshot.connectionState == ConnectionState.waiting,
          discoveryMessage: snapshot.hasError
              ? '另一平台MV核对未完成'
              : snapshot.data?.warnings.join('；'),
          retryDiscovery: () => setState(() => _stream = _discover()),
          resources: [
            for (final choice in _known.values)
              SourceCommentRequest(
                Track(
                  id: '${choice.source.name}_mv_${choice.mv.id}',
                  title: choice.mv.title,
                  artist: choice.mv.artist,
                  album: '',
                  duration: choice.mv.duration,
                  audioAsset: '',
                  coverAsset: choice.track.coverAsset,
                  lyricsAsset: '',
                  source: choice.source,
                ),
                kind: PlatformCommentKind.mv,
                mvId: choice.mv.id,
                mvHash: choice.mv.qualities.first.hash,
              ),
          ],
        );
      }
      final loading = snapshot.connectionState != ConnectionState.done;
      return PlatformPageFrame(
        musicChrome: false,
        title: 'MV评论',
        subtitle: widget.track.title,
        child: Center(
          child: loading
              ? const CupertinoActivityIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      snapshot.hasError ||
                              snapshot.data?.warnings.isNotEmpty == true
                          ? 'MV评论资源暂时无法核对'
                          : '暂时没有可核对的MV评论区',
                    ),
                    TextButton(
                      onPressed: () => setState(() => _stream = _discover()),
                      child: const Text('重试'),
                    ),
                  ],
                ),
        ),
      );
    },
  );
}

/// Public source identity only. Song recording IDs, MV IDs and video hashes
/// remain distinct; a song's comments are never substituted for an MV's pool.
class SourceCommentRequest {
  const SourceCommentRequest(
    this.track, {
    this.kind = PlatformCommentKind.song,
    this.mvId = '',
    this.mvHash = '',
  });
  final Track track;
  final PlatformCommentKind kind;
  final String mvId, mvHash;
  Object get identity => (track.source, track.id, kind, mvId, mvHash);
  @override
  bool operator ==(Object other) =>
      other is SourceCommentRequest && identity == other.identity;
  @override
  int get hashCode => identity.hashCode;
}

class SourceCommentBinding {
  const SourceCommentBinding(this.repository, this.resource, this.current);
  final PlatformCommentsRepository repository;
  final PlatformCommentResource resource;
  final bool Function() current;
}

final sourceCommentBindingProvider = FutureProvider.autoDispose
    .family<SourceCommentBinding, SourceCommentRequest>((ref, request) async {
      final scope = await ref.watch(
        sourceMediaScopeProvider(request.track.source).future,
      );
      if (!ref.mounted || !scope.isCurrent()) {
        throw const MusicPlatformException('来源账号已变化');
      }
      final owner = scope.session;
      // This blank marker is never installed in an API jar or secure storage.
      // Anonymous reads pass null expectedSession; requireWritable rejects writes.
      final displayIdentity =
          owner ??
          PlatformSession(
            userId: '',
            token: '',
            platform: request.track.source == TrackSource.netease
                ? MusicPlatform.netease
                : MusicPlatform.kugou,
          );
      final repository = scope.music != null
          ? NeteaseCommentsRepository(
              scope.api,
              displayIdentity,
              scope.music!,
              readOnly: owner == null,
            )
          : PlatformCommentsRepository(
              scope.api,
              displayIdentity,
              readOnly: owner == null,
            );
      final resource = request.kind == PlatformCommentKind.mv
          ? PlatformCommentResource(
              kind: PlatformCommentKind.mv,
              id: request.mvId,
              hash: request.mvHash,
              name: request.track.title,
            )
          : await repository.songResource(request.track);
      if (!ref.mounted || !scope.isCurrent()) {
        throw const MusicPlatformException('来源账号已变化');
      }
      if (resource.id.isEmpty && resource.hash.isEmpty) {
        throw const MusicPlatformException('平台未提供可核对的评论标识');
      }
      return SourceCommentBinding(repository, resource, scope.isCurrent);
    }, retry: (_, _) => null);

/// Each platform retains its own list, cursor, drafts and loading state. The
/// current source opens immediately while counterpart discovery runs separately.
class SourceCommentsPage extends ConsumerStatefulWidget {
  const SourceCommentsPage({
    required this.track,
    this.resources,
    this.initialSource,
    this.discoveryLoading = false,
    this.discoveryMessage,
    this.retryDiscovery,
    super.key,
  });
  final Track track;
  final List<SourceCommentRequest>? resources;
  final TrackSource? initialSource;
  final bool discoveryLoading;
  final String? discoveryMessage;
  final VoidCallback? retryDiscovery;
  @override
  ConsumerState<SourceCommentsPage> createState() => _SourceCommentsPageState();
}

class _SourceCommentsPageState extends ConsumerState<SourceCommentsPage> {
  final _visited = <TrackSource>{};
  late TrackSource _selected =
      widget.initialSource ??
      actualSourceRecording(widget.track)?.source ??
      widget.track.source;
  @override
  Widget build(BuildContext context) {
    final discovery = widget.resources == null
        ? ref.watch(linkedMusicRecordingsProvider(widget.track))
        : null;
    final requests = <TrackSource, SourceCommentRequest>{};
    if (widget.resources != null) {
      for (final request in widget.resources!) {
        requests[request.track.source] = request;
      }
    } else {
      final primary = actualSourceRecording(widget.track);
      if (primary != null &&
          [TrackSource.netease, TrackSource.kugou].contains(primary.source)) {
        requests[primary.source] = SourceCommentRequest(primary);
      }
      for (final track in discovery?.value?.recordings ?? <Track>[]) {
        requests[track.source] = SourceCommentRequest(track);
      }
    }
    if (requests.isEmpty) {
      return PlatformPageFrame(
        musicChrome: false,
        title: '评论',
        subtitle: widget.track.title,
        child: const Center(child: Text('当前音源未提供可核对的评论区')),
      );
    }
    final sources = [
      for (final source in [TrackSource.netease, TrackSource.kugou])
        if (requests.containsKey(source)) source,
    ];
    final selected = requests.containsKey(_selected)
        ? _selected
        : sources.first;
    _visited.add(selected);
    final selector = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: sources.length == 1
                ? const SizedBox.shrink()
                : CupertinoSlidingSegmentedControl<TrackSource>(
                    groupValue: selected,
                    children: {
                      for (final source in sources)
                        source: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 12,
                          ),
                          child: Text(
                            source == TrackSource.netease ? '网易云' : '酷狗',
                          ),
                        ),
                    },
                    onValueChanged: (source) {
                      if (source != null) {
                        FocusScope.of(context).unfocus();
                        setState(() => _selected = source);
                      }
                    },
                  ),
          ),
          if (discovery?.isLoading == true || widget.discoveryLoading)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('正在核对另一平台的对应评论'),
            ),
          if (widget.discoveryMessage?.isNotEmpty == true)
            TextButton(
              onPressed: widget.retryDiscovery,
              child: Text('${widget.discoveryMessage}，点此重试'),
            ),
          if (discovery?.hasError == true ||
              discovery?.value?.warnings.isNotEmpty == true)
            TextButton(
              onPressed: () =>
                  ref.invalidate(linkedMusicRecordingsProvider(widget.track)),
              child: const Text('另一平台资源核对未完成，点此重试'),
            ),
        ],
      ),
    );
    // The route frame and selector exist once, outside the moving viewport.
    // Fixed source slots survive asynchronous counterpart discovery; each
    // retained content page owns its own list, pagination and composer draft.
    const slots = [TrackSource.netease, TrackSource.kugou];
    return PlatformPageFrame(
      key: const ValueKey('source-comments-frame'),
      musicChrome: false,
      title: requests[selected]!.kind == PlatformCommentKind.mv
          ? 'MV评论'
          : '歌曲评论',
      subtitle: widget.track.title,
      child: Column(
        children: [
          selector,
          Expanded(
            child: BetaSwipePages(
              key: const ValueKey('source-comments-content'),
              index: slots.indexOf(selected),
              length: slots.length,
              swipeEnabled: sources.length > 1,
              onChanged: (index) {
                final source = slots[index];
                if (requests.containsKey(source) && _selected != source) {
                  FocusScope.of(context).unfocus();
                  setState(() => _selected = source);
                }
              },
              itemBuilder: (context, index) {
                final source = slots[index];
                return KeyedSubtree(
                  key: ValueKey(source),
                  child:
                      _visited.contains(source) && requests.containsKey(source)
                      ? _SourceCommentBody(
                          key: ValueKey(requests[source]!.identity),
                          request: requests[source]!,
                        )
                      : const SizedBox.shrink(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceCommentBody extends ConsumerWidget {
  const _SourceCommentBody({required this.request, super.key});
  final SourceCommentRequest request;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(sourceCommentBindingProvider(request));
    final binding = value.value;
    if (binding != null && binding.current()) {
      return PlatformCommentsPage(
        key: ObjectKey(binding),
        resource: binding.resource,
        repository: binding.repository,
        sourceCurrent: binding.current,
        embedded: true,
        onSourceLogin: () async {
          try {
            await ensureSourceLogin(
              context,
              ref,
              request.track.source,
              forPlayback: false,
            );
          } catch (error) {
            if (context.mounted) showPlatformFailure(context, error);
          }
        },
      );
    }
    return Center(
      child: value.isLoading
          ? const CupertinoActivityIndicator()
          : PlatformFeedbackState(
              message: value.error is MusicPlatformException
                  ? (value.error as MusicPlatformException).message
                  : '评论暂时无法加载',
              retry: () =>
                  ref.invalidate(sourceCommentBindingProvider(request)),
            ),
    );
  }
}
