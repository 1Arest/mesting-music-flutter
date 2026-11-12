import 'dart:async';
import '../../../shared/models/track.dart';
import '../../../shared/models/track_page.dart';
import '../../library/data/library_repository.dart';
import 'qishui_api.dart';
import 'qishui_repository.dart';

/// The shared player/favorite tools use the same remote Soda library as Mine.
/// Unimplemented playlist mutations are blocked by the base write guard, never
/// silently converted into local or Kugou cloud writes.
class QishuiLibraryRepository extends LibraryRepository {
  QishuiLibraryRepository(
    super.database, {
    required this.music,
    required String owner,
  }) : super(ownerId: owner, canWrite: () => false);
  final QishuiRepository music;
  final _changes = StreamController<void>.broadcast();
  Future<void> _pending = Future.value();
  bool _disposed = false;
  Future<List<Track>>? _favorites;
  Future<List<Track>> _read() =>
      _favorites ??= music.favorites().catchError((Object error) {
        _favorites = null;
        throw error;
      });
  Stream<T> _watch<T>(Future<T> Function() load) => Stream<T>.multi((sink) {
    var generation = 0;
    var active = true;
    Future<void> emit() async {
      final next = ++generation;
      try {
        final result = await load();
        if (active && !_disposed && music.current && next == generation) {
          sink.add(result);
        }
      } on Object catch (e, s) {
        if (active && !_disposed && next == generation) sink.addError(e, s);
      }
    }

    final listener = _changes.stream.listen((_) => unawaited(emit()));
    sink.onCancel = () {
      active = false;
      ++generation;
      return listener.cancel();
    };
    unawaited(emit());
  });
  @override
  Stream<List<Track>> watchFavorites() => _watch(_read);
  @override
  Stream<TrackPage> watchFavoritePreview() => _watch(() => favoritePage());
  @override
  Future<Set<String>> favoriteIds() async =>
      (await _read()).map((t) => t.id).toSet();
  @override
  Future<bool> isFavorite(String trackId) async =>
      (await favoriteIds()).contains(trackId);
  @override
  Future<TrackPage> favoritePage({
    int offset = 0,
    int limit = 30,
    String query = '',
  }) async {
    final values = (await _read())
        .where(
          (t) =>
              query.trim().isEmpty ||
              '${t.title} ${t.artist}'.toLowerCase().contains(
                query.trim().toLowerCase(),
              ),
        )
        .toList();
    return TrackPage(
      values.skip(offset).take(limit).toList(),
      offset: offset,
      total: values.length,
      hasMore: offset + limit < values.length,
    );
  }

  Future<void> _write(Track track, bool favorite) {
    final operation = _pending.then((_) async {
      if (_disposed || !music.current) {
        throw const QishuiException('账号已变化，请重新操作');
      }
      try {
        await music.setFavorite(track, favorite);
      } finally {
        _favorites = null;
        if (!_disposed) _changes.add(null);
      }
    });
    _pending = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  @override
  Future<void> setFavorite(Track track, {required bool favorite}) =>
      _write(track, favorite);
  @override
  Future<bool> toggleFavorite(Track track) async {
    final next = !await isFavorite(track.id);
    await _write(track, next);
    return next;
  }

  @override
  Future<bool> synchronize({bool forcePull = false}) async {
    _favorites = null;
    await _read();
    if (!_disposed) _changes.add(null);
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_changes.close());
    super.dispose();
  }
}
