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
    super.key,
  });
  final String uri;
  final String scope;
  final String? owner;
  final ValueChanged<bool>? onReadinessChanged;
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
        oldWidget.image != widget.image) {
      _resolve();
    }
  }

  void _resolve() {
    _detach();
    final prepared = artworkRefreshCoordinator.take(
      widget.uri,
      scope: widget.scope,
    );
    if (prepared != null) _replace(prepared, rebuild: false);
    if (widget.image == null || !TickerMode.valuesOf(context).enabled) return;
    final stream = widget.image!.resolve(
      createLocalImageConfiguration(
        context,
        size: widget.width != null && widget.height != null
            ? Size(widget.width!, widget.height!)
            : null,
      ),
    );
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
