import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/media/artwork_refresh_coordinator.dart';
import '../domain/platform_session.dart';
import '../music_platform_providers.dart';

/// Credentials are used only as an in-memory equality boundary. They never
/// become a disk key, diagnostic label, image request header or exported value.
typedef PlatformDisplayOwner = (String?, String?);

PlatformDisplayOwner platformDisplayOwner(PlatformSession? session) =>
    (session?.ownerId, session?.token);

class _DisplaySnapshot {
  _DisplaySnapshot(this.value, this.covers);
  final Object value;
  final List<String> covers;
}

/// Retains typed presentation data across unmount/platform changes without
/// keeping hidden pages, provider subscriptions or network clients alive.
/// A slot names a specific shelf, not its widget position or Dart runtime type.
class PlatformDisplaySnapshots {
  PlatformDisplaySnapshots({ArtworkRefreshCoordinator? artwork})
    : artwork = artwork ?? artworkRefreshCoordinator;
  final ArtworkRefreshCoordinator artwork;
  final _values = <(PlatformDisplayOwner, String), _DisplaySnapshot>{};
  final _frames = <(PlatformDisplayOwner, String), ImageInfo>{};
  static const _maxSlots = 96;
  static const _maxFrameBytes = 16 * 1024 * 1024;

  T? read<T>(PlatformDisplayOwner owner, String slot) {
    final value = _values[(owner, slot)]?.value;
    return value is T ? value : null;
  }

  void remember<T extends Object>(
    PlatformDisplayOwner owner,
    String slot,
    T value,
    Iterable<String> covers,
  ) {
    final key = (owner, slot);
    _values.remove(key);
    _values[key] = _DisplaySnapshot(
      value,
      covers.where((v) => v.isNotEmpty).take(12).toList(),
    );
    while (_values.length > _maxSlots) {
      _values.remove(_values.keys.first);
    }
  }

  /// Called before a switch while the departing page still owns its decoded
  /// frames. Clones share image storage, but their retained memory is bounded.
  void captureArtwork(PlatformDisplayOwner owner) {
    for (final entry in _values.entries.where((e) => e.key.$1 == owner)) {
      for (final uri in entry.value.covers) {
        final frame = artwork.take(uri);
        if (frame == null) continue;
        final key = (owner, uri);
        _frames.remove(key)?.dispose();
        _frames[key] = frame;
      }
    }
    var bytes = _frames.values.fold<int>(
      0,
      (n, v) => n + v.image.width * v.image.height * 4,
    );
    while (bytes > _maxFrameBytes && _frames.isNotEmpty) {
      final old = _frames.remove(_frames.keys.first)!;
      bytes -= old.image.width * old.image.height * 4;
      old.dispose();
    }
  }

  /// Seed the shared renderer synchronously before mounting the cached shelf.
  /// Frames belonging to another account are never considered as fallbacks.
  void seedArtwork(PlatformDisplayOwner owner, String slot) {
    for (final uri in _values[(owner, slot)]?.covers ?? const <String>[]) {
      final frame = _frames[(owner, uri)];
      if (frame != null) {
        artwork.remember(uri, frame, pin: true);
      }
    }
  }

  /// Disk-only preparation covers evicted first-screen pixels. It never waits
  /// for fresh recommendations, signs media or performs account writes.
  Future<void> prepareHomeArtwork(PlatformDisplayOwner owner) async {
    final covers = <String>{};
    for (final entry in _values.entries.where((e) => e.key.$1 == owner)) {
      seedArtwork(owner, entry.key.$2);
      covers.addAll(entry.value.covers.take(4));
      if (covers.length >= 12) break;
    }
    await artwork.prepareCached({'covers': covers.take(12).toList()});
  }

  Future<bool> prepareReplacement(
    Iterable<String> oldCovers,
    Iterable<String> nextCovers,
  ) => artwork.prepareRefresh(
    {'covers': oldCovers.toList()},
    {'covers': nextCovers.toList()},
  );

  /// Logout/credential replacement invalidates that identity, whereas changing
  /// platforms deliberately retains each independently authenticated identity.
  void forget(PlatformDisplayOwner owner) {
    _values.removeWhere((key, _) => key.$1 == owner);
    for (final key in _frames.keys.where((key) => key.$1 == owner).toList()) {
      _frames.remove(key)!.dispose();
    }
  }

  void dispose() {
    for (final frame in _frames.values) {
      frame.dispose();
    }
    _frames.clear();
    _values.clear();
  }
}

final platformDisplaySnapshotsProvider = Provider<PlatformDisplaySnapshots>((
  ref,
) {
  final snapshots = PlatformDisplaySnapshots();
  ref.listen(platformAccountProvider, (before, after) {
    if (after.isLoading || after.hasError) return;
    final previous = before?.value;
    final next = after.value;
    if (previous != null &&
        (next == null ||
            (previous.ownerId == next.ownerId &&
                previous.token != next.token))) {
      snapshots.forget(platformDisplayOwner(previous));
    }
  });
  ref.onDispose(snapshots.dispose);
  return snapshots;
});
