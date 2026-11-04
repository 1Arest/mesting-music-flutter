import 'dart:async';
import 'dart:collection';

import 'package:flutter/painting.dart';

import '../utils/media_uri.dart';
import 'persistent_network_image_cache.dart';

/// Identifies image content independently of a CDN thumbnail or expiring URL.
/// Semantic ID/version parameters remain part of the identity.

class ArtworkRefreshRegistration {
  ArtworkRefreshRegistration(this.visible);
  final bool Function() visible;
  String source = '', requestUri = '', cacheKey = 'public-artwork-v1';
  int? width, height;
  PersistentNetworkImageCache cache = persistentNetworkImageCache;
}

class _PreparedFrame {
  _PreparedFrame(this.info, this.until);
  final ImageInfo info;
  DateTime until;
  int get bytes => info.image.width * info.image.height * 4;
}

/// Decouples response publication from image download/first-frame decoding.
/// Existing visible image paths select the replacement covers even after a
/// long list has scrolled. Cold snapshots warm only existing disk files. Work,
/// decoded memory and traversal are bounded; no account headers are involved.
class ArtworkRefreshCoordinator {
  ArtworkRefreshCoordinator({
    this.maxBytes = 24 * 1024 * 1024,
    PersistentNetworkImageCache? cache,
  }) : defaultCache = cache ?? persistentNetworkImageCache;
  final PersistentNetworkImageCache defaultCache;
  final int maxBytes;
  final _frames = <String, _PreparedFrame>{};
  final _registrations = <ArtworkRefreshRegistration>{};
  final _pending = <String, Future<bool>>{};
  final _waiting = Queue<Completer<void>>();
  int _active = 0;

  ArtworkRefreshRegistration register(bool Function() visible) {
    final value = ArtworkRefreshRegistration(visible);
    _registrations.add(value);
    return value;
  }

  void unregister(ArtworkRefreshRegistration entry) =>
      _registrations.remove(entry);

  ImageInfo? take(String uri, {String scope = 'public-artwork-v1'}) {
    final key = '$scope\n${artworkContentIdentity(uri)}';
    final entry = _frames.remove(key);
    if (entry == null) return null;
    _frames[key] = entry;
    return entry.info.clone();
  }

  bool remember(
    String uri,
    ImageInfo info, {
    bool pin = false,
    String scope = 'public-artwork-v1',
  }) {
    final key = '$scope\n${artworkContentIdentity(uri)}';
    final old = _frames[key];
    if (old != null &&
        old.info.image.width >= info.image.width &&
        old.info.image.height >= info.image.height) {
      if (pin) old.until = DateTime.now().add(const Duration(seconds: 2));
      return true;
    }
    final bytes = info.image.width * info.image.height * 4;
    var used =
        _frames.values.fold<int>(0, (n, f) => n + f.bytes) - (old?.bytes ?? 0);
    final now = DateTime.now();
    for (final candidate in _frames.keys.toList()) {
      if (used + bytes <= maxBytes && _frames.length < 32) break;
      final entry = _frames[candidate]!;
      if (candidate == key || entry.until.isAfter(now)) continue;
      used -= entry.bytes;
      _frames.remove(candidate)!.info.dispose();
    }
    if (used + bytes > maxBytes) return false;
    _frames.remove(key)?.info.dispose();
    _frames[key] = _PreparedFrame(
      info.clone(),
      pin ? now.add(const Duration(seconds: 2)) : now,
    );
    return true;
  }

  Future<void> prepareCached(Map<String, dynamic> body) async {
    final pictures = _pictures(body).values.take(12);
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    await Future.wait([
      for (final uri in pictures)
        _ready(uri, null, diskOnly: true, deadline: deadline),
    ]).timeout(const Duration(seconds: 2), onTimeout: () => const <bool>[]);
  }

  Future<bool> prepareRefresh(
    Map<String, dynamic> previous,
    Map<String, dynamic> incoming,
  ) async {
    final old = _pictures(previous),
        fresh = _pictures(incoming, includeEmpty: true);
    final visible = _registrations.where((r) => r.visible()).toList();
    final selected =
        <String, ({String uri, ArtworkRefreshRegistration? registration})>{};
    for (final r in visible) {
      final identity = artworkContentIdentity(r.source);
      for (final item in old.entries) {
        if (artworkContentIdentity(item.value) != identity) continue;
        final next = fresh[item.key];
        if (next != null) {
          selected[artworkContentIdentity(next)] = (uri: next, registration: r);
        }
      }
    }
    // A fast response can arrive before the cached widgets mount. These first
    // visible-sized covers also seed newly inserted rows; the renderer can use
    // their decoded frame while resolving its precise thumbnail dimensions.
    for (final uri
        in fresh.values.where((value) => value.isNotEmpty).take(12)) {
      selected.putIfAbsent(
        artworkContentIdentity(uri),
        () => (uri: uri, registration: null),
      );
    }
    if (selected.length > 64) return false;
    final values = selected.values.toList();
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    final results = await Future.wait([
      for (final entry in values)
        _ready(entry.uri, entry.registration, deadline: deadline),
    ]).timeout(const Duration(seconds: 20), onTimeout: () => const [false]);
    if (results.any((ready) => !ready)) return false;
    // Earlier decodes may have waited behind a slow download and lost their
    // short pin. Recheck the complete set before publishing, then pin it as a
    // group so bounded-memory eviction cannot expose a partially ready page.
    final frames = [
      for (final entry in values)
        _frames['${entry.registration?.cacheKey ?? 'public-artwork-v1'}\n${artworkContentIdentity(entry.uri)}'],
    ];
    if (frames.any((frame) => frame == null)) return false;
    final until = DateTime.now().add(const Duration(seconds: 2));
    for (final frame in frames) {
      frame!.until = until;
    }
    return true;
  }

  /// Prepare one playback picture without holding the audio source resolver.
  /// The view keeps its decoded previous picture until this bounded job ends.
  Future<bool> preparePlaybackArtwork(String uri) => _ready(
    uri,
    null,
    deadline: DateTime.now().add(const Duration(seconds: 20)),
  );

  Future<bool> _ready(
    String source,
    ArtworkRefreshRegistration? registration, {
    bool diskOnly = false,
    DateTime? deadline,
  }) {
    final identity =
        '${registration?.cacheKey ?? 'public-artwork-v1'}\n${artworkContentIdentity(source)}';
    final existing = _frames[identity];
    if (existing != null) {
      existing.until = DateTime.now().add(const Duration(seconds: 2));
      return Future.value(true);
    }
    final request =
        '$identity:${registration?.width}:${registration?.height}:$diskOnly';
    return _pending.putIfAbsent(request, () {
      final future = _load(
        source,
        registration,
        diskOnly: diskOnly,
        deadline: deadline,
      );
      unawaited(future.whenComplete(() => _pending.remove(request)));
      return future;
    });
  }

  Future<bool> _load(
    String source,
    ArtworkRefreshRegistration? registration, {
    required bool diskOnly,
    DateTime? deadline,
  }) async {
    if (_active >= 3) {
      final waiter = Completer<void>();
      _waiting.add(waiter);
      await waiter.future;
    } else {
      _active++;
    }
    ImageStream? stream;
    ImageStreamListener? listener;
    ImageInfo? decoded;
    try {
      if (deadline != null && DateTime.now().isAfter(deadline)) return false;
      var uri = normalizeArtworkUri(source.replaceAll('{size}', '480'));
      final size = Uri.tryParse(
        registration?.requestUri ?? '',
      )?.queryParameters['param'];
      if (Uri.tryParse(uri)?.host.endsWith('.music.126.net') ?? false) {
        uri = Uri.parse(uri)
            .replace(
              queryParameters: {
                ...Uri.parse(uri).queryParameters,
                'param': size ?? '768y768',
              },
            )
            .toString();
      }
      final cache = registration?.cache ?? defaultCache;
      final cacheKey = registration?.cacheKey ?? 'public-artwork-v1';
      final file = diskOnly
          ? cache.peekContent(cacheKey: cacheKey, url: uri)
          : await cache.resolve(cacheKey: cacheKey, url: uri);
      if (file == null) return diskOnly;
      await cache.flush();
      if (deadline != null && DateTime.now().isAfter(deadline)) return false;
      final provider = ResizeImage.resizeIfNeeded(
        registration == null ? 256 : registration.width,
        registration?.height,
        FileImage(file),
      );
      final ready = Completer<ImageInfo>();
      stream = provider.resolve(ImageConfiguration.empty);
      listener = ImageStreamListener(
        (info, _) {
          if (!ready.isCompleted) ready.complete(info.clone());
        },
        onError: (Object error, StackTrace? stack) {
          if (!ready.isCompleted) ready.completeError(error, stack);
        },
      );
      stream.addListener(listener);
      decoded = await ready.future.timeout(const Duration(seconds: 18));
      if (deadline != null && DateTime.now().isAfter(deadline)) return false;
      return remember(source, decoded, pin: true, scope: cacheKey) || diskOnly;
    } on Object {
      return diskOnly;
    } finally {
      if (listener != null) stream?.removeListener(listener);
      decoded?.dispose();
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _active--;
      }
    }
  }

  Map<String, String> _pictures(Object? body, {bool includeEmpty = false}) {
    final found = <String, String>{};
    final stack = <({Object? value, String path, int depth, bool image})>[
      (value: body, path: '', depth: 0, image: false),
    ];
    var visited = 0;
    while (stack.isNotEmpty && visited++ < 100000) {
      final node = stack.removeLast();
      if (node.depth > 18) continue;
      final value = node.value;
      if (value is Map) {
        final children =
            <({Object? value, String path, int depth, bool image})>[];
        for (final item in value.entries) {
          final key = '${item.key}',
              image = RegExp(
                'cover|artwork|avatar|pic|image|img',
                caseSensitive: false,
              ).hasMatch(key);
          children.add((
            value: item.value,
            path: '${node.path}.$key',
            depth: node.depth + 1,
            image: image || node.image && key == 'url',
          ));
        }
        stack.addAll(children.reversed);
      } else if (value is List) {
        for (var i = value.length - 1; i >= 0; i--) {
          stack.add((
            value: value[i],
            path: '${node.path}[$i]',
            depth: node.depth + 1,
            image: node.image,
          ));
        }
      } else if (includeEmpty && node.image && (value == null || value == '')) {
        found[node.path] = '';
      } else if (node.image &&
          value is String &&
          value.length < 8192 &&
          RegExp(r'^https?://').hasMatch(value)) {
        found[node.path] = value;
      }
    }
    return found;
  }

  void dispose() {
    for (final entry in _frames.values) {
      entry.info.dispose();
    }
    _frames.clear();
    _registrations.clear();
  }
}

final artworkRefreshCoordinator = ArtworkRefreshCoordinator();
