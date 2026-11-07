import '../../core/network/system_music_io_client.dart';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import '../utils/media_uri.dart';

/// Keep Flutter's normal provider for other hosts and signed image URLs.
/// NetEase needs the same HTTP header replacement as the persistent cache.
ImageProvider<Object> networkArtworkProvider(String url) =>
    artworkRequestHeaders(url) == null
    ? NetworkImage(url)
    : ArtworkNetworkImage(url);

/// Flutter's IO NetworkImage adds headers to HttpClient's existing defaults.
/// That produces two User-Agent values here; the public CDN on the test phone
/// rejects this with 403 even though the single app identifier returns 200.
/// package:http's IO transport replaces each header instead. Keep that change
/// local to artwork, without global HttpOverrides or any account credentials.
@immutable
class ArtworkNetworkImage extends ImageProvider<ArtworkNetworkImage> {
  const ArtworkNetworkImage(this.url, {this.client});

  final String url;

  /// Injection is only needed by local transport/decoder regression tests.
  final http.Client? client;
  static final _sharedClient = SystemMusicIoClient();

  @override
  Future<ArtworkNetworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    ArtworkNetworkImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(key, decode),
    scale: 1,
    debugLabel: 'Public artwork',
  );

  Future<ui.Codec> _load(
    ArtworkNetworkImage key,
    ImageDecoderCallback decode,
  ) async {
    try {
      final uri = Uri.parse(key.url);
      final response = await (key.client ?? _sharedClient)
          .get(uri, headers: artworkRequestHeaders(key.url))
          .timeout(const Duration(seconds: 18));
      if (response.statusCode != 200) {
        throw NetworkImageLoadException(
          statusCode: response.statusCode,
          uri: uri,
        );
      }
      if (response.bodyBytes.isEmpty) {
        throw StateError('The artwork response is empty');
      }
      return await decode(
        await ui.ImmutableBuffer.fromUint8List(response.bodyBytes),
      );
    } catch (_) {
      // A temporary rejection must not poison Flutter's image cache forever.
      // Let the widget's existing bounded retry resolve the same URL again.
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ArtworkNetworkImage &&
      other.url == url &&
      identical(other.client, client);

  @override
  int get hashCode => Object.hash(url, client);
}
