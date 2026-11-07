import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/mesting_audio_handler.dart';
import '../../core/audio/playback_providers.dart';
import '../../shared/models/track.dart';
import 'audiobook_models.dart';
import 'audiobook_repository.dart';
import 'audiobook_resume.dart';

/// Watch once from the Beta app root. Progress continues saving while the
/// listener leaves the book page and while the media service plays backstage.
final audiobookProgressBindingProvider = Provider<AudiobookPlaybackBinding>((
  ref,
) {
  final binding = AudiobookPlaybackBinding(
    ref.watch(audioHandlerProvider),
    ref.watch(audiobookRepositoryProvider),
    ref.watch(audiobookResumeStoreProvider),
  );
  ref.onDispose(binding.dispose);
  return binding;
});

class AudiobookPlaybackBinding with WidgetsBindingObserver {
  AudiobookPlaybackBinding(this.handler, this.repository, this.store) {
    WidgetsBinding.instance.addObserver(this);
    _subscriptions.add(handler.mediaItem.listen((item) => _select(item?.id)));
    _subscriptions.add(
      handler.positionStream.listen((position) {
        _lastPosition = position;
      }),
    );
    _subscriptions.add(
      handler.playbackState.listen((state) {
        if (!state.playing) unawaited(_save());
      }),
    );
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_save());
      unawaited(_extend());
    });
  }
  final MestingAudioHandler handler;
  final AudiobookRepository repository;
  final AudiobookResumeStore store;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  Timer? _timer;
  Track? _lastTrack;
  Duration _lastPosition = Duration.zero;
  BookAlbum? _album;
  int _nextPage = 2;
  bool _hasMore = false, _extending = false, _disposed = false;
  Map<String, int> _pages = {};
  int _generation = 0;
  String? saveError, continuationError;

  void begin(
    BookAlbum album,
    List<BookChapter> chapters, {
    required int firstPage,
    required int nextPage,
    required bool hasMore,
    Map<String, int>? chapterPages,
  }) {
    _generation++;
    _album = album;
    _nextPage = nextPage;
    _hasMore = hasMore;
    _pages = chapterPages == null
        ? {
            for (var i = 0; i < chapters.length; i++)
              chapters[i].track.id: firstPage + i ~/ 50,
          }
        : Map.of(chapterPages);
    _lastTrack = handler.trackForId(handler.mediaItem.value?.id ?? '');
    _lastPosition = handler.currentPosition;
    continuationError = null;
    unawaited(_save());
  }

  void _select(String? id) {
    if (_disposed || id == _lastTrack?.id) return;
    // The cached old position belongs to the old media item. Reading the
    // engine here can already yield the new chapter's zero position instead.
    unawaited(_save());
    _lastTrack = id == null ? null : handler.trackForId(id);
    _lastPosition = Duration.zero;
    final identity = _lastTrack == null ? null : bookIdentity(_lastTrack!);
    if (identity == null) {
      _album = null;
      _generation++;
      return;
    }
    if (_album?.id != identity.albumId) {
      _generation++;
      final resume = store.forAlbum(identity.albumId);
      _album =
          resume?.album ??
          BookAlbum(
            id: identity.albumId,
            name: _lastTrack!.album,
            author: _lastTrack!.artist,
            cover: _lastTrack!.coverAsset,
          );
      _nextPage = resume?.nextPage ?? 2;
      _hasMore = resume?.hasMore ?? false;
      _pages = {...?resume?.pages};
    }
  }

  Future<void> _save() async {
    final track = _lastTrack, album = _album;
    if (_disposed ||
        track == null ||
        album == null ||
        bookIdentity(track)?.albumId != album.id) {
      return;
    }
    final position =
        track.duration > Duration.zero && _lastPosition > track.duration
        ? track.duration
        : _lastPosition;
    if (position < Duration.zero) return;
    final pages = Map<String, int>.fromEntries(
      _pages.entries.toList().reversed.take(200).toList().reversed,
    );
    try {
      await store.save(
        BookResume(
          album: album,
          track: track,
          position: position,
          updatedAt: DateTime.now(),
          nextPage: _nextPage,
          hasMore: _hasMore,
          chapterPage: _pages[track.id] ?? 1,
          pages: pages,
        ),
      );
      saveError = null;
    } catch (_) {
      saveError = '听书进度暂未保存，请检查可用存储空间';
    }
  }

  Future<void> _extend() async {
    final album = _album;
    if (_disposed ||
        _extending ||
        !_hasMore ||
        album == null ||
        continuationError != null) {
      return;
    }
    final current = handler.trackForId(handler.mediaItem.value?.id ?? '');
    if (current == null ||
        bookIdentity(current)?.albumId != album.id ||
        handler.upcomingQueue.length > 3) {
      return;
    }
    // An explicitly queued music track keeps its priority. Do not put more
    // chapters ahead of it or alter a queue that the listener has replaced.
    if (handler.upcomingQueue.any(
      (item) =>
          bookIdentity(handler.trackForId(item.id) ?? current)?.albumId !=
          album.id,
    )) {
      return;
    }
    final generation = _generation, requestedPage = _nextPage;
    _extending = true;
    try {
      final result = await repository.chapters(album, page: requestedPage);
      if (_disposed || generation != _generation || _album?.id != album.id) {
        return;
      }
      final known = handler.persistedQueue.map((t) => t.id).toSet();
      for (final chapter in result.items.where(
        (c) => c.canPlay && known.add(c.track.id),
      )) {
        if (_disposed || generation != _generation) return;
        await handler.appendToUpcomingQueue(chapter.track);
        _pages[chapter.track.id] = requestedPage;
      }
      _nextPage = requestedPage + 1;
      _hasMore = result.hasMore;
      await _save();
    } catch (_) {
      continuationError = '后续章节暂未加载，请在专辑页重试';
    } finally {
      _extending = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_save());
    } else {
      continuationError = null;
      unawaited(_extend());
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    WidgetsBinding.instance.removeObserver(this);
  }
}
