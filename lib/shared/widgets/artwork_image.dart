import '../utils/media_uri.dart';
import '../media/artwork_refresh_coordinator.dart';
import 'retained_artwork_frame.dart';
import 'package:flutter/rendering.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../media/persistent_network_image_cache.dart';
import '../media/artwork_network_image.dart';
import '../../core/diagnostics/local_music_diagnostics.dart';
import '../../core/platform/distribution_channel.dart';

const _legacyArtworkAssetAliases = <String, String>{
  'assets/branding/dress-midnight-launch.png':
      'assets/branding/dress-midnight-launch-v2.webp',
  'assets/branding/dress-midnight-launch-v2.png':
      'assets/branding/dress-midnight-launch-v2.webp',
  'assets/branding/dress-morning-launch.png':
      'assets/branding/dress-morning-launch.webp',
  'assets/images/themes/shinchan_progress.png':
      'assets/images/theme_gallery/shinchan-avatar-v2.png',
  'assets/images/themes/shinchan_sunny.png':
      'assets/images/theme_gallery/motion-walk-shinchan-scene.webp',
  'assets/images/theme_gallery/shinchan-progress-head.png':
      'assets/images/theme_gallery/shinchan-avatar-v2.png',
};

String canonicalArtworkUri(String value) =>
    normalizeArtworkUri(_legacyArtworkAssetAliases[value] ?? value);

class ArtworkImage extends StatefulWidget {
  const ArtworkImage({
    required this.uri,
    this.width,
    this.height,
    this.decodeWidth,
    this.decodeHeight,
    this.fit = BoxFit.cover,
    this.retryOnNetworkError = false,
    this.persistentNetworkCacheKey,
    this.networkImageCache,
    this.onNetworkError,
    this.frameOwner,
    super.key,
  });

  final String uri;
  final double? width;
  final double? height;
  final double? decodeWidth;
  final double? decodeHeight;
  final BoxFit fit;
  final bool retryOnNetworkError;
  final String? persistentNetworkCacheKey;
  final PersistentNetworkImageCache? networkImageCache;
  final VoidCallback? onNetworkError;

  /// Stable song identity prevents the previous song's retained pixels from
  /// following a recycled player widget during a rapid recording change.
  final String? frameOwner;

  @override
  State<ArtworkImage> createState() => _ArtworkImageState();
}

class _ArtworkImageState extends State<ArtworkImage> {
  static const _maxNetworkRetries = 3;

  ArtworkRefreshRegistration? _registration;
  Timer? _retryTimer;
  int _networkRetry = 0;
  File? _persistentNetworkFile;
  String? _persistentNetworkIdentity;
  bool _persistentNetworkFailed = false;
  bool _handlingBrokenFile = false;
  String get _requestUri => sizedArtworkUri(
    canonicalArtworkUri(widget.uri),
    width: _thumbnailSize,
    height: _thumbnailSize,
  );

  /// Search/mini-player share one thumbnail bucket; the foreground cover and
  /// its blurred background share an HD bucket. Widget-specific decoding stays
  /// bounded below, but must not create a new HTTP download for every dp size.
  int get _thumbnailSize {
    final width = widget.decodeWidth ?? widget.width ?? 256;
    final height = widget.decodeHeight ?? widget.height ?? width;
    final edge = (width > height ? width : height) * 3;
    for (final size in const [192, 384, 768, 1024]) {
      if (edge <= size) return size;
    }
    return 1024;
  }

  @override
  void initState() {
    super.initState();
    _resetPersistentNetworkImage();
  }

  @override
  void didUpdateWidget(covariant ArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri == widget.uri &&
        oldWidget.retryOnNetworkError == widget.retryOnNetworkError &&
        oldWidget.persistentNetworkCacheKey ==
            widget.persistentNetworkCacheKey &&
        oldWidget.networkImageCache == widget.networkImageCache &&
        oldWidget.width == widget.width &&
        oldWidget.height == widget.height &&
        oldWidget.decodeWidth == widget.decodeWidth &&
        oldWidget.decodeHeight == widget.decodeHeight) {
      return;
    }
    _retryTimer?.cancel();
    _retryTimer = null;
    _networkRetry = 0;
    _resetPersistentNetworkImage();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    if (_registration != null) {
      artworkRefreshCoordinator.unregister(_registration!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uri = _requestUri;
    final hasExplicitDecodeSize =
        widget.decodeWidth != null || widget.decodeHeight != null;
    final cacheWidth = artworkCacheDimension(
      context,
      widget.decodeWidth ?? (hasExplicitDecodeSize ? null : widget.width),
    );
    final cacheHeight = artworkCacheDimension(
      context,
      widget.decodeHeight ?? (hasExplicitDecodeSize ? null : widget.height),
    );
    Widget errorBuilder(
      BuildContext context,
      Object error,
      StackTrace? stackTrace,
    ) {
      return _ArtworkPlaceholder(width: widget.width, height: widget.height);
    }

    if (uri.startsWith('http://') || uri.startsWith('https://')) {
      if (DistributionChannel.isBeta) {
        final registration = _registration ??= artworkRefreshCoordinator
            .register(() {
              if (!mounted) return false;
              final box = context.findRenderObject();
              if (box is! RenderBox || !box.attached || !box.hasSize) {
                return false;
              }
              final viewport = RenderAbstractViewport.maybeOf(box);
              if (viewport != null) {
                final rect = MatrixUtils.transformRect(
                  box.getTransformTo(viewport),
                  Offset.zero & box.size,
                );
                return rect.overlaps(viewport.paintBounds);
              }
              return (box.localToGlobal(Offset.zero) & box.size).overlaps(
                Offset.zero & MediaQuery.sizeOf(context),
              );
            });
        registration
          ..source = canonicalArtworkUri(widget.uri)
          ..requestUri = uri
          ..width = cacheWidth
          ..height = cacheHeight
          ..cache = widget.networkImageCache ?? persistentNetworkImageCache
          ..cacheKey = widget.persistentNetworkCacheKey ?? 'public-artwork-v1';
      }
      Widget frame(
        ImageProvider<Object>? provider, {
        void Function(Object, StackTrace?)? onError,
      }) => RetainedArtworkFrame(
        key: const ValueKey('retained-artwork-frame'),
        uri: uri,
        owner: widget.frameOwner,
        scope: widget.persistentNetworkCacheKey ?? 'public-artwork-v1',
        image: provider,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        fallback: _ArtworkPlaceholder(
          width: widget.width,
          height: widget.height,
        ),
        onError: onError,
      );
      Widget directNetwork() {
        final provider = ResizeImage.resizeIfNeeded(
          cacheWidth,
          cacheHeight,
          networkArtworkProvider(uri),
        );
        return frame(
          provider,
          onError: (error, stackTrace) {
            LocalMusicDiagnostics.record('artwork.decode_network_failed', {
              ...LocalMusicDiagnostics.artwork(uri),
              'type': error.runtimeType.toString(),
              if (error is NetworkImageLoadException)
                'status': error.statusCode,
            });
            widget.onNetworkError?.call();
            _scheduleNetworkRetry(provider);
          },
        );
      }

      final persistentImage = _persistentNetworkConfig;
      if (persistentImage != null) {
        final file = _persistentNetworkFile;
        if (file == null) {
          if (!_persistentNetworkFailed) {
            return frame(null);
          }
          // A failed disk cache must not leave a permanently empty cover. Let
          // Flutter load the same public image directly while the bounded cache
          // retry runs; this also works when app-private storage is unavailable.
          return directNetwork();
        }
        return frame(
          ResizeImage.resizeIfNeeded(cacheWidth, cacheHeight, FileImage(file)),
          onError: (error, stackTrace) {
            LocalMusicDiagnostics.record('artwork.decode_file_failed', {
              ...LocalMusicDiagnostics.artwork(uri),
              'type': error.runtimeType.toString(),
            });
            _recoverBrokenFile(file);
          },
        );
      }
      return directNetwork();
    }
    if (uri.isEmpty) {
      return _ArtworkPlaceholder(width: widget.width, height: widget.height);
    }
    final localFile = _localFile(uri);
    if (localFile != null) {
      return Image.file(
        localFile,
        width: widget.width,
        height: widget.height,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        fit: widget.fit,
        errorBuilder: errorBuilder,
      );
    }
    return Image.asset(
      uri,
      width: widget.width,
      height: widget.height,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      fit: widget.fit,
      errorBuilder: errorBuilder,
    );
  }

  void _recoverBrokenFile(File file) {
    if (_handlingBrokenFile) return;
    _handlingBrokenFile = true;
    final identity = _persistentNetworkIdentity;
    final config = _persistentNetworkConfig;
    unawaited(FileImage(file).evict());
    if (config != null) {
      unawaited(
        config.cache.invalidate(cacheKey: config.cacheKey, url: config.uri),
      );
    }
    // Image error builders can run during build. Repair state after this frame
    // and keep the new network child visible while a bounded disk retry runs.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handlingBrokenFile = false;
      if (!mounted || identity != _persistentNetworkIdentity) return;
      setState(() {
        _persistentNetworkFile = null;
        _persistentNetworkFailed = true;
      });
      _schedulePersistentNetworkRetry();
    });
  }

  void _scheduleNetworkRetry(ImageProvider<Object> provider) {
    if (!widget.retryOnNetworkError ||
        _networkRetry >= _maxNetworkRetries ||
        _retryTimer != null) {
      return;
    }
    final nextRetry = _networkRetry + 1;
    _retryTimer = Timer(Duration(milliseconds: 650 * nextRetry), () async {
      _retryTimer = null;
      await provider.evict();
      if (!mounted) return;
      setState(() => _networkRetry = nextRetry);
    });
  }

  ({PersistentNetworkImageCache cache, String cacheKey, String uri})?
  get _persistentNetworkConfig {
    final cache = widget.networkImageCache ?? persistentNetworkImageCache;
    final cacheKey =
        widget.persistentNetworkCacheKey?.trim() ??
        (DistributionChannel.isBeta && cache.initialized
            ? 'public-artwork-v1'
            : null);
    final uri = _requestUri;
    if (cacheKey == null ||
        cacheKey.isEmpty ||
        (!uri.startsWith('http://') && !uri.startsWith('https://'))) {
      return null;
    }
    return (cache: cache, cacheKey: cacheKey, uri: uri);
  }

  void _resetPersistentNetworkImage() {
    _persistentNetworkFile = null;
    _persistentNetworkFailed = false;
    final config = _persistentNetworkConfig;
    _persistentNetworkIdentity = config == null
        ? null
        : '${config.cacheKey}\n${config.uri}';
    if (config == null) return;

    final exact = config.cache.peek(cacheKey: config.cacheKey, url: config.uri);
    final cached =
        exact ??
        config.cache.peekContent(cacheKey: config.cacheKey, url: config.uri);
    _persistentNetworkFile = cached;
    if (exact != null) {
      return;
    }
    // The first build immediately resolves the existing thumbnail. Upgrading
    // its bytes never replaces it with a null provider or a placeholder.
    _loadPersistentNetworkImage();
  }

  void _loadPersistentNetworkImage() {
    final identity = _persistentNetworkIdentity;
    final config = _persistentNetworkConfig;
    if (identity == null || config == null) return;

    config.cache.resolve(cacheKey: config.cacheKey, url: config.uri).then((
      file,
    ) {
      if (!mounted || identity != _persistentNetworkIdentity) return;
      if (file != null) {
        setState(() {
          _persistentNetworkFile = file;
          _persistentNetworkFailed = false;
        });
        return;
      }
      setState(() => _persistentNetworkFailed = true);
      _schedulePersistentNetworkRetry();
    });
  }

  void _schedulePersistentNetworkRetry() {
    if (!widget.retryOnNetworkError ||
        _networkRetry >= _maxNetworkRetries ||
        _retryTimer != null) {
      return;
    }
    final nextRetry = _networkRetry + 1;
    _retryTimer = Timer(Duration(milliseconds: 650 * nextRetry), () {
      _retryTimer = null;
      if (!mounted) return;
      setState(() {
        _networkRetry = nextRetry;
        _persistentNetworkFile = null;
      });
      _loadPersistentNetworkImage();
    });
  }

  File? _localFile(String value) {
    File? file;
    if (value.startsWith('file://')) {
      file = File.fromUri(Uri.parse(value));
    } else if (value.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value)) {
      file = File(value);
    }
    return file != null && file.existsSync() ? file : null;
  }
}

int? artworkCacheDimension(BuildContext context, double? logicalPixels) {
  if (logicalPixels == null || !logicalPixels.isFinite || logicalPixels <= 0) {
    return null;
  }
  final physicalPixels =
      (logicalPixels * MediaQuery.devicePixelRatioOf(context)).ceil();
  return physicalPixels.clamp(1, 2048);
}

class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder({this.width, this.height});

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFFE9EDFF),
      alignment: Alignment.center,
      child: const Icon(Icons.album_rounded, color: Color(0xFF4B63D0)),
    );
  }
}
