import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/playback_providers.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/music_feature_page.dart';
import '../presentation/platform_feedback.dart';
import 'qishui_catalog_providers.dart';
import 'qishui_catalog_widgets.dart';
import 'qishui_page_scope.dart';
import 'qishui_search_catalog.dart';

/// Artist metadata and works have independent reads. A missing optional profile
/// cannot hide already available songs, and the queue action states that it
/// replaces the queue with the loaded songs rather than an unverified total.
class QishuiArtistPage extends ConsumerStatefulWidget {
  const QishuiArtistPage({required this.artist, super.key});
  final QishuiArtist artist;
  @override
  ConsumerState<QishuiArtistPage> createState() => _QishuiArtistPageState();
}

class _QishuiArtistPageState extends ConsumerState<QishuiArtistPage>
    with QishuiOwnedPage<QishuiArtistPage> {
  late final _catalog = ref.read(qishuiSearchCatalogProvider);
  late QishuiArtist _artist = widget.artist;
  QishuiCatalogAccumulator<Track> _tracks = QishuiCatalogAccumulator(
    keyOf: (t) => t.id,
  );
  bool _loading = false, _profileLoading = false, _playing = false;
  Object? _error, _profileError;
  int _playIntent = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProfile());
    unawaited(_loadTracks());
  }

  Future<void> _loadProfile() async {
    if (_profileLoading || !ownerCurrent) return;
    setState(() {
      _profileLoading = true;
      _profileError = null;
    });
    try {
      final result = await _catalog.artistDetail(
        _artist.id,
        abortTrigger: pageAbort,
      );
      if (ownerCurrent) setState(() => _artist = _artist.merge(result));
    } on Object catch (error) {
      if (ownerCurrent) setState(() => _profileError = error);
    } finally {
      if (ownerCurrent) setState(() => _profileLoading = false);
    }
  }

  Future<void> _loadTracks() async {
    if (_loading || !_tracks.hasMore || !ownerCurrent) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _catalog.artistTracks(
        _artist.id,
        cursor: _tracks.nextCursor,
        abortTrigger: pageAbort,
      );
      if (ownerCurrent) setState(() => _tracks.accept(page));
    } on Object catch (error) {
      if (ownerCurrent) setState(() => _error = error);
    } finally {
      if (ownerCurrent) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    if (_loading || !ownerCurrent) return;
    setState(() => _tracks = QishuiCatalogAccumulator(keyOf: (t) => t.id));
    await Future.wait([_loadProfile(), _loadTracks()]);
  }

  Future<void> _playLoaded() async {
    if (_playing || !ownerCurrent || _tracks.items.isEmpty) return;
    final intent = ++_playIntent;
    final values = _tracks.items;
    setState(() => _playing = true);
    bool current() => ownerCurrent && intent == _playIntent;
    try {
      await ref
          .read(audioHandlerProvider)
          .replaceQueue(values, togetherGuard: current);
    } on Object catch (error) {
      if (!mounted || !current()) return;
      showPlatformFailure(context, error);
    } finally {
      if (current()) setState(() => _playing = false);
    }
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipOval(
              child: SizedBox.square(
                dimension: 88,
                child: _artist.artwork.isEmpty
                    ? ColoredBox(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.person_outline, size: 40),
                      )
                    : ArtworkImage(uri: _artist.artwork),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _artist.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  if (_artist.trackCount != null)
                    Text('${_artist.trackCount} 首歌曲'),
                  if (_artist.albumCount != null)
                    Text('${_artist.albumCount} 张专辑'),
                ],
              ),
            ),
          ],
        ),
        if (_artist.description.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            _artist.description,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        if (_profileError != null)
          TextButton(
            onPressed: _profileLoading ? null : _loadProfile,
            child: const Text('歌手资料暂未更新，点此重试'),
          ),
        const SizedBox(height: 20),
        BetaGlassButton(
          onPressed: _playing || _tracks.items.isEmpty ? null : _playLoaded,
          accent: true,
          child: Text(
            _playing ? '正在准备播放' : '播放已加载的 ${_tracks.items.length} 首歌曲',
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!watchOwner()) return changedAccount();
    final values = _tracks.items;
    return MusicFeaturePage(
      title: '歌手',
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            bottom: BetaContentInsets.musicBottomOf(context),
          ),
          itemCount: values.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) return _header();
            if (index <= values.length) {
              return QishuiCatalogTrackTile(track: values[index - 1]);
            }
            return Column(
              children: [
                if (!_loading && _error == null && values.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('暂无可显示的歌曲'),
                  ),
                QishuiCatalogFooter(
                  loading: _loading,
                  hasMore: _tracks.hasMore,
                  error: _error,
                  continuationProblem: _tracks.continuationProblem,
                  loadMore: _loadTracks,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
