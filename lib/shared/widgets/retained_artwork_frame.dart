import 'package:flutter/material.dart';

import '../media/artwork_refresh_coordinator.dart';

/// Owns the last fully decoded frame, including while the source/provider is
/// replaced. A response-prepared frame can be displayed before the precise
/// sized FileImage resolves. Ownership uses ImageInfo clones, never raw files
/// or a growing tree of old Image widgets.
class RetainedArtworkFrame extends StatefulWidget {
  const RetainedArtworkFrame({
    required this.uri,
    this.scope = 'public-artwork-v1',
    required this.image,
    required this.fallback,
    required this.fit,
    this.width,
    this.height,
    this.onError,
    this.owner,
    this.onReadinessChanged,
    this.retryRevision = 0,
    super.key,
  });
  final String uri;
  final String scope;
  final String? owner;
  final ValueChanged<bool>? onReadinessChanged;

  /// Re-resolve an evicted provider even when its URL/size are unchanged.
  /// Keeping this widget's identity preserves its last successful frame.
  final int retryRevision;
  final ImageProvider<Object>? image;
  final Widget fallback;
  final double? width, height;
  final BoxFit fit;
  final void Function(Object error, StackTrace? stack)? onError;
  @override
  State<RetainedArtworkFrame> createState() => _RetainedArtworkFrameState();
}

class _RetainedArtworkFrameState extends State<RetainedArtworkFrame> {
  ImageInfo? _frame;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageProvider<Object>? _resolvedImage;
  ImageConfiguration? _configuration;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant RetainedArtworkFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope || oldWidget.owner != widget.owner) {
      final old = _frame;
      _frame = null;
      widget.onReadinessChanged?.call(false);
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
    }
    if (oldWidget.scope != widget.scope ||
        oldWidget.owner != widget.owner ||
        oldWidget.uri != widget.uri ||
        oldWidget.retryRevision != widget.retryRevision ||
        oldWidget.width != widget.width ||
        oldWidget.height != widget.height ||
        oldWidget.image != widget.image) {
      _resolve(force: true);
    }
  }

  void _resolve({bool force = false}) {
    // Insets, text scaling, theme and the retained-tab visibility signals can
    // notify this element without changing its decoder configuration. Keep
    // the existing stream/listener in that case: re-attaching an already ready
    // image clones pixels, reports readiness and queues disposal every time.
    // Hidden tabs detach their listener but retain the last painted pixels.
    if (!TickerMode.valuesOf(context).enabled) {
      _detach();
      return;
    }
    final configuration = createLocalImageConfiguration(
      context,
      size: widget.width != null && widget.height != null
          ? Size(widget.width!, widget.height!)
          : null,
    );
    if (!force &&
        _stream != null &&
        _resolvedImage == widget.image &&
        _configuration == configuration) {
      return;
    }
    _detach();
    final prepared = artworkRefreshCoordinator.take(
      widget.uri,
      scope: widget.scope,
    );
    if (prepared != null) _replace(prepared, rebuild: false);
    if (widget.image == null) return;
    _configuration = configuration;
    _resolvedImage = widget.image;
    final stream = widget.image!.resolve(configuration);
    _stream = stream;
    _listener = ImageStreamListener(
      (info, sync) {
        if (!mounted || _stream != stream) return;
        artworkRefreshCoordinator.remember(
          widget.uri,
          info,
          scope: widget.scope,
        );
        _replace(info.clone(), rebuild: !sync);
      },
      onError: (Object error, StackTrace? stack) {
        if (mounted && _stream == stream) widget.onError?.call(error, stack);
      },
    );
    stream.addListener(_listener!);
  }

  void _replace(ImageInfo info, {required bool rebuild}) {
    final old = _frame;
    widget.onReadinessChanged?.call(true);
    if (rebuild) {
      setState(() => _frame = info);
    } else {
      _frame = info;
    }
    // RawImage from the current frame may still be in the layer tree.
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  void _detach() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _stream = null;
    _listener = null;
    _resolvedImage = null;
    _configuration = null;
  }

  @override
  void dispose() {
    _detach();
    _frame?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _frame == null
      ? widget.fallback
      : RawImage(
          image: _frame!.image,
          scale: _frame!.scale,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          filterQuality: FilterQuality.medium,
        );
}
