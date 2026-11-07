import 'dart:async';
import '../../../core/cache/cached_browse_loader.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/track.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_page_motion.dart';
import '../../../shared/widgets/music_activity_indicator.dart';
import '../../../shared/widgets/music_feature_page.dart';
import 'qishui_artist_page.dart';
import 'qishui_catalog_providers.dart';
import 'qishui_catalog_widgets.dart';
import 'qishui_page_scope.dart';
import 'qishui_search_catalog.dart';

/// Search is a secondary page with independent keyword/type/request state.
/// Changing keyword or type aborts its previous read; late results never paint
/// over the new search or another account's page.
class QishuiSearchPage extends ConsumerStatefulWidget {
  const QishuiSearchPage({super.key});
  @override
  ConsumerState<QishuiSearchPage> createState() => _QishuiSearchPageState();
}

class _QishuiSearchPageState extends ConsumerState<QishuiSearchPage>
    with QishuiOwnedPage<QishuiSearchPage> {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  final _browse = CachedBrowseLoader();
  late final _catalog = ref.read(qishuiSearchCatalogProvider);
  QishuiSearchKind _kind = QishuiSearchKind.tracks;
  QishuiCatalogAccumulator<Track>? _tracks;
  QishuiCatalogAccumulator<QishuiArtist>? _artists;
  Completer<void>? _requestAbort;
  String _submitted = '';
  bool _busy = false;
  Object? _error;
  int _generation = 0;

  int get _length => _kind == QishuiSearchKind.tracks
      ? _tracks?.items.length ?? 0
      : _artists?.items.length ?? 0;
  bool get _hasMore => _kind == QishuiSearchKind.tracks
      ? _tracks?.hasMore ?? false
      : _artists?.hasMore ?? false;
  String? get _continuationProblem => _kind == QishuiSearchKind.tracks
      ? _tracks?.continuationProblem
      : _artists?.continuationProblem;

  void _cancelRead() {
    final abort = _requestAbort;
    if (abort != null && !abort.isCompleted) abort.complete();
    _requestAbort = null;
  }

  @override
  void dispose() {
    ++_generation;
    _cancelRead();
    _browse.dispose();
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _submit(String text) {
    _cancelRead();
    _browse.reset();
    ++_generation;
    final keyword = text.trim();
    final searchId = QishuiSearchCatalog.newSearchId();
    setState(() {
      _submitted = keyword;
      _tracks = QishuiCatalogAccumulator(
        keyOf: (track) => track.id,
        searchId: searchId,
      );
      _artists = QishuiCatalogAccumulator(
        keyOf: (artist) => artist.id,
        searchId: searchId,
      );
      _busy = false;
      _error = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (keyword.isNotEmpty) {
      FocusManager.instance.primaryFocus?.unfocus();
      unawaited(_loadMore());
    }
  }

  void _selectKind(QishuiSearchKind kind) {
    if (kind == _kind) return;
    _kind = kind;
    _submit(_query.text);
  }

  Future<void> _loadMore() async {
    if (_busy || !_hasMore || _submitted.isEmpty || !ownerCurrent) return;
    final generation = _generation;
    final kind = _kind;
    final keyword = _submitted;
    final abort = Completer<void>();
    _requestAbort = abort;
    final cancellation = Future.any<void>([pageAbort, abort.future]);
    setState(() {
      _busy = true;
      _error = null;
    });
    bool current() =>
        ownerCurrent && generation == _generation && !abort.isCompleted;
    try {
      if (kind == QishuiSearchKind.tracks) {
        final values = _tracks!;
        final cursor = values.nextCursor, searchId = values.searchId;
        final page = await _browse.load<QishuiCatalogPage<Track>>(
          key: (kind, cursor),
          request: () => _catalog.searchTracks(
            keyword,
            cursor: cursor,
            searchId: searchId,
            abortTrigger: cancellation,
          ),
          onUpdate: (_, next) {
            if (current()) setState(() => values.replace(next));
          },
        );
        if (!current()) return;
        setState(() => values.accept(page));
      } else {
        final values = _artists!;
        final cursor = values.nextCursor, searchId = values.searchId;
        final page = await _browse.load<QishuiCatalogPage<QishuiArtist>>(
          key: (kind, cursor),
          request: () => _catalog.searchArtists(
            keyword,
            cursor: cursor,
            searchId: searchId,
            abortTrigger: cancellation,
          ),
          onUpdate: (_, next) {
            if (current()) setState(() => values.replace(next));
          },
        );
        if (!current()) return;
        setState(() => values.accept(page));
      }
    } on Object catch (error) {
      if (current()) setState(() => _error = error);
    } finally {
      if (current()) setState(() => _busy = false);
      if (identical(_requestAbort, abort)) _requestAbort = null;
    }
  }

  Widget _results() {
    if (_submitted.isEmpty) {
      return const MusicFeatureMessage(message: '输入关键词，查找歌曲或歌手');
    }
    if (_busy && _length == 0) {
      return const Center(child: MusicActivityIndicator());
    }
    if (_error != null && _length == 0) {
      return MusicFeatureMessage(message: '$_error', onRetry: _loadMore);
    }
    final tracks = _tracks?.items ?? const <Track>[];
    final artists = _artists?.items ?? const <QishuiArtist>[];
    return ListView.builder(
      key: ValueKey('qishui-search-${_kind.pathName}-results'),
      controller: _scroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(
        bottom: BetaContentInsets.musicBottomOf(context),
      ),
      itemCount: _length + 1,
      itemBuilder: (context, index) {
        if (index == _length) {
          return Column(
            children: [
              if (_length == 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 36, 24, 12),
                  child: Text('没有找到${_kind.label}，试试其他关键词'),
                ),
              QishuiCatalogFooter(
                loading: _busy,
                hasMore: _hasMore,
                error: _error,
                continuationProblem: _continuationProblem,
                loadMore: _loadMore,
              ),
            ],
          );
        }
        if (_kind == QishuiSearchKind.tracks) {
          return QishuiCatalogTrackTile(track: tracks[index]);
        }
        final artist = artists[index];
        return ListTile(
          key: ValueKey('qishui-artist-${artist.id}'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 8,
          ),
          leading: ClipOval(
            child: SizedBox.square(
              dimension: 54,
              child: artist.artwork.isEmpty
                  ? ColoredBox(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.person_outline),
                    )
                  : ArtworkImage(uri: artist.artwork),
            ),
          ),
          title: Text(
            artist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            artist.trackCount == null ? '歌手' : '${artist.trackCount} 首歌曲',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(
            context,
          ).push(betaContentRoute<void>(QishuiArtistPage(artist: artist))),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!watchOwner()) return changedAccount();
    return MusicFeaturePage(
      title: '搜索汽水音乐',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: BetaGlassField(
              child: TextField(
                key: const ValueKey('qishui-catalog-search-field'),
                controller: _query,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: _submit,
                decoration: InputDecoration(
                  labelText: '歌曲、歌手',
                  suffixIcon: IconButton(
                    tooltip: '搜索',
                    onPressed: () => _submit(_query.text),
                    icon: const Icon(Icons.search),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: SegmentedButton<QishuiSearchKind>(
              showSelectedIcon: false,
              segments: [
                for (final kind in QishuiSearchKind.values)
                  ButtonSegment(value: kind, label: Text(kind.label)),
              ],
              selected: {_kind},
              onSelectionChanged: (selection) => _selectKind(selection.single),
            ),
          ),
          Expanded(child: _results()),
        ],
      ),
    );
  }
}
