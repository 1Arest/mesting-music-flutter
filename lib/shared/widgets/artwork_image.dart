import '../utils/media_uri.dart';
import '../media/artwork_refresh_coordinator.dart';
import 'retained_artwork_frame.dart';
import 'artwork_reveal_boundary.dart';
import 'beta_glass_controls.dart' show BetaActivityIndicator;
import 'package:flutter/rendering.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../media/persistent_network_image_cache.dart';
import '../media/artwork_network_image.dart';
import '../../core/diagnostics/local_music_diagnostics.dart';
import '../../core/platform/distribution_channel.dart';
import '../../features/themes/music_typography.dart';

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
    this.onLoadFailure,
    this.onRetry,
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

  /// Optional metadata recovery after any final image failure (disk or HTTP).
  final VoidCallback? onLoadFailure;
  final VoidCallback? onRetry;

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
  int _resolutionRevision = 0;
  ImageProvider<Object>? _directNetworkProvider;
  File? _persistentNetworkFile;
  String? _persistentNetworkIdentity;
  bool _persistentNetworkFailed = false;
  bool _handlingBrokenFile = false;
  ArtworkRevealEntry? _reveal;
  ArtworkRevealController? _revealController;
  bool _decoded = false, _everFailed = false, _initialized = false;
  bool _active = true;
  Timer? _initialDeadline;
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled) {
      _initialDeadline?.cancel();
      _initialDeadline = null;
    }
    final controller = ArtworkRevealBoundary.of(context);
    if (_revealController != controller) {
      _reveal?.dispose();
      _revealController = controller;
      _reveal = controller?.register(() {
        if (!mounted || !_active) return null;
        final render = context.findRenderObject();
        return render is RenderBox ? render : null;
      });
    }
    _reportReadiness();
    _startDeadline();
    if (!_initialized) {
      _initialized = true;
      _resetPersistentNetworkImage();
    } else if (TickerMode.valuesOf(context).enabled &&
        _persistentNetworkFile == null &&
        !_persistentNetworkFailed) {
      _loadPersistentNetworkImage();
    }
  }

  void _reportReadiness() {
    _reveal?.identity =
        '${widget.persistentNetworkCacheKey ?? 'public-artwork-v1'}\n${widget.frameOwner ?? artworkContentIdentity(widget.uri)}';
    _reveal?.update(
      ready: _decoded || _everFailed || canonicalArtworkUri(widget.uri).isEmpty,
      enabled: TickerMode.valuesOf(context).enabled,
    );
  }

  void _failed() {
    if (!mounted || _everFailed) return;
    _everFailed = true;
    _initialDeadline?.cancel();
    // Image stream failures can arrive during build. Build the explicit error
    // state next frame before releasing the surrounding content gate.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
        widget.onLoadFailure?.call();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _startDeadline() {
    if (_decoded || _everFailed || !TickerMode.valuesOf(context).enabled) {
      return;
    }
    final uri = canonicalArtworkUri(widget.uri);
    if (uri.startsWith('http://') || uri.startsWith('https://')) {
      _initialDeadline ??= Timer(const Duration(seconds: 20), _failed);
    }
  }

  Widget _pendingOrError() {
    if (!DistributionChannel.isBeta) {
      return _ArtworkPlaceholder(width: widget.width, height: widget.height);
    }
    if (!_everFailed && widget.uri.trim().isNotEmpty) {
      if (_reveal != null) {
        // The viewport owns the only loading animation. Hidden rows must not
        // each run another ticker while their bytes/first frame are prepared.
        return SizedBox(width: widget.width, height: widget.height);
      }
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: const Center(child: BetaActivityIndicator()),
      );
    }
    final empty = widget.uri.trim().isEmpty;
    return Tooltip(
      message: empty ? '暂无封面' : '封面加载失败，点击重试',
      child: Semantics(
        button: !empty,
        label: empty ? '暂无封面' : '重试加载封面',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: empty ? null : _retryFailedImage,
          child: SizedBox(
            width: widget.width,
            height: widget.height,
            child: Center(
              child: Text(
                empty ? '无封面' : '重试',
                style: TextStyle(
                  fontSize: MusicTypography.smallCaptionSize,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant ArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri == widget.uri &&
        oldWidget.frameOwner == widget.frameOwner &&
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
    if (oldWidget.frameOwner != widget.frameOwner ||
        oldWidget.persistentNetworkCacheKey !=
            widget.persistentNetworkCacheKey ||
        artworkContentIdentity(oldWidget.uri) !=
            artworkContentIdentity(widget.uri)) {
      _decoded = false;
      _everFailed = false;
      _initialDeadline?.cancel();
      _initialDeadline = null;
      _reportReadiness();
    }
    _resetPersistentNetworkImage();
    _startDeadline();
  }

  @override
  void deactivate() {
    // Lazy slivers deactivate recycled elements before the end-of-frame
    // disposal pass. Their BuildContext must not be queried while painting.
    _active = false;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
  }

  @override
  void dispose() {
    _initialDeadline?.cancel();
    _reveal?.dispose();
    _retryTimer?.cancel();
    if (_registration != null) {
      artworkRefreshCoordinator.unregister(_registration!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Publish failures only when their explicit retry UI is built, so a page
    // can never reveal the previous frame's per-image loading indicator.
    _reportReadiness();
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
      _failed();
      return _pendingOrError();
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
        retryRevision: _resolutionRevision,
        owner: widget.frameOwner ?? artworkContentIdentity(widget.uri),
        onReadinessChanged: (value) {
          _decoded = value;
          if (value) _initialDeadline?.cancel();
          _reportReadiness();
        },
        scope: widget.persistentNetworkCacheKey ?? 'public-artwork-v1',
        image: provider,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        fallback: _pendingOrError(),
        onError: onError,
      );
      Widget directNetwork() {
        final provider = ResizeImage.resizeIfNeeded(
          cacheWidth,
          cacheHeight,
          networkArtworkProvider(uri),
        );
        _directNetworkProvider = provider;
        return frame(
          provider,
          onError: (error, stackTrace) {
            _failed();
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
            _failed();
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
      return _pendingOrError();
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
        frameBuilder: (context, child, frame, sync) {
          if (frame != null) {
            _decoded = true;
            _reportReadiness();
          }
          return child;
        },
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
      frameBuilder: (context, child, frame, sync) {
        if (frame != null) {
          _decoded = true;
          _reportReadiness();
        }
        return child;
      },
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
    final identity = _requestUri;
    _retryTimer = Timer(Duration(milliseconds: 650 * nextRetry), () async {
      _retryTimer = null;
      await provider.evict();
      if (!mounted || identity != _requestUri) return;
      setState(() {
        _networkRetry = nextRetry;
        _resolutionRevision++;
      });
      _startDeadline();
    });
  }

  /// Explicit retry evicts the precise resized provider. A plain rebuild of
  /// an equal provider never reconnects RetainedArtworkFrame's failed stream.
  Future<void> _retryFailedImage() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    final identity = _requestUri;
    await _directNetworkProvider?.evict();
    if (!mounted || identity != _requestUri) return;
    setState(() {
      _networkRetry = 0;
      _resolutionRevision++;
      _initialDeadline?.cancel();
      _initialDeadline = null;
      _resetPersistentNetworkImage();
    });
    _startDeadline();
    widget.onRetry?.call();
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
    if (!TickerMode.valuesOf(context).enabled) return;
    _startDeadline();

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
      _failed();
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
