import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;

import '../../core/platform/distribution_channel.dart';

/// A live content viewport, not a screenshot or an eager image preload. Lazy
/// lists keep laying out their normal cache extent while unresolved rows stay
/// behind one loading surface. Existing rows above the pending batch remain
/// painted, interactive and at their original scroll coordinates.
class ArtworkRevealBoundary extends StatefulWidget {
  const ArtworkRevealBoundary({required this.child, super.key});
  final Widget child;

  static ArtworkRevealController? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_ArtworkRevealScope>()
      ?.controller;

  @override
  State<ArtworkRevealBoundary> createState() => _ArtworkRevealBoundaryState();
}

class _ArtworkRevealBoundaryState extends State<ArtworkRevealBoundary> {
  final controller = ArtworkRevealController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!DistributionChannel.isBeta) return widget.child;
    return _ArtworkRevealScope(
      controller: controller,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          controller.invalidate();
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (event) {
            if (event is ScrollUpdateNotification && event.scrollDelta != 0) {
              controller.scrolled = true;
            }
            controller.invalidate();
            return false;
          },
          child: _ArtworkViewport(
            controller: controller,
            background: Theme.of(context).colorScheme.surface,
            children: [
              widget.child,
              ValueListenableBuilder<bool>(
                valueListenable: controller.pending,
                builder: (_, active, child) =>
                    TickerMode(enabled: active, child: child!),
                child: SizedBox.square(
                  dimension: 32,
                  child: Center(
                    child: Semantics(
                      label: '正在加载内容',
                      liveRegion: true,
                      child: CupertinoActivityIndicator(
                        animating: !MediaQuery.disableAnimationsOf(context),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Include an unresolved data section in the same visible-batch gate as its
/// covers. It keeps the real layout extent, while its individual spinner is
/// paused behind the viewport's single indicator. Action/button progress must
/// stay outside this wrapper so an operation never hides already usable rows.
class ArtworkPendingContent extends StatefulWidget {
  const ArtworkPendingContent({required this.child, super.key});
  final Widget child;
  @override
  State<ArtworkPendingContent> createState() => _ArtworkPendingContentState();
}

class _ArtworkPendingContentState extends State<ArtworkPendingContent> {
  ArtworkRevealController? _controller;
  ArtworkRevealEntry? _entry;
  bool _active = true;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = ArtworkRevealBoundary.of(context);
    if (_controller != controller) {
      _entry?.dispose();
      _controller = controller;
      _entry = controller?.register(() {
        if (!mounted || !_active) return null;
        final box = context.findRenderObject();
        return box is RenderBox ? box : null;
      });
      _entry?.identity = 'content-pending-${identityHashCode(this)}';
    }
    _entry?.update(ready: false, enabled: TickerMode.valuesOf(context).enabled);
  }

  @override
  void deactivate() {
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
    _entry?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _controller == null
      ? widget.child
      : TickerMode(enabled: false, child: widget.child);
}

class ArtworkRevealEntry {
  ArtworkRevealEntry(this.box, this.controller);
  final RenderBox? Function() box;
  final ArtworkRevealController controller;
  bool ready = false, enabled = true;
  String identity = '';
  void update({required bool ready, required bool enabled}) {
    if (this.ready == ready && this.enabled == enabled) return;
    this.ready = ready;
    this.enabled = enabled;
    controller.invalidate();
  }

  void dispose() => controller.remove(this);
}

/// Image state reports readiness directly to painting/semantics. It does not
/// rebuild every list or attach providers to playback-position/animation ticks.
class ArtworkRevealController {
  final entries = <ArtworkRevealEntry>{};
  final pending = ValueNotifier(true);
  final _refreshes = <Object, RenderBox? Function()?>{};
  bool get refreshing => _refreshes.isNotEmpty;
  void refreshActivity(
    Object owner,
    bool active, {
    RenderBox? Function()? box,
  }) {
    if (_disposed) return;
    final changed = active
        ? !_refreshes.containsKey(owner)
        : _refreshes.containsKey(owner);
    if (active) {
      _refreshes[owner] = box;
    } else {
      _refreshes.remove(owner);
    }
    if (changed) invalidate();
  }

  bool scrolled = false;
  VoidCallback? repaint;
  bool _disposed = false, _scheduled = false;
  bool? _nextPending;
  ArtworkRevealEntry register(RenderBox? Function() box) {
    final entry = ArtworkRevealEntry(box, this);
    entries.add(entry);
    invalidate();
    return entry;
  }

  void remove(ArtworkRevealEntry entry) {
    entries.remove(entry);
    invalidate();
  }

  void invalidate() {
    if (!_disposed) repaint?.call();
  }

  void reportPending(bool value) {
    if (_disposed || pending.value == value && !_scheduled) return;
    _nextPending = value;
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed && pending.value != _nextPending) {
        pending.value = _nextPending!;
      }
    });
  }

  void dispose() {
    _disposed = true;
    repaint = null;
    entries.clear();
    _refreshes.clear();
    pending.dispose();
  }
}

class _ArtworkRevealScope extends InheritedWidget {
  const _ArtworkRevealScope({required this.controller, required super.child});
  final ArtworkRevealController controller;
  @override
  bool updateShouldNotify(_ArtworkRevealScope old) =>
      old.controller != controller;
}

class _ArtworkViewport extends MultiChildRenderObjectWidget {
  const _ArtworkViewport({
    required this.controller,
    required this.background,
    required super.children,
  });
  final ArtworkRevealController controller;
  final Color background;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderArtworkViewport(controller, background);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderArtworkViewport renderObject,
  ) {
    renderObject.background = background;
  }
}

class _ArtworkParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderArtworkViewport extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ArtworkParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ArtworkParentData> {
  _RenderArtworkViewport(this.controller, this._background);
  final ArtworkRevealController controller;
  Color _background;
  set background(Color value) {
    if (value == _background) return;
    _background = value;
    markNeedsPaint();
  }

  double _cutoff = 0;
  bool _presented = false;
  final _committed = <String>{};
  RenderBox get content => firstChild!;
  RenderBox get loader => lastChild!;
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ArtworkParentData) {
      child.parentData = _ArtworkParentData();
    }
  }

  void _invalidate() {
    if (attached) {
      markNeedsPaint();
      markNeedsSemanticsUpdate();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    controller.repaint = _invalidate;
  }

  @override
  void detach() {
    controller.repaint = null;
    super.detach();
  }

  @override
  void performLayout() {
    content.layout(constraints, parentUsesSize: true);
    size = constraints.constrain(content.size);
    loader.layout(
      BoxConstraints.loose(
        Size(size.width.clamp(0, 32), size.height.clamp(0, 32)),
      ),
      parentUsesSize: true,
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      content.getDryLayout(constraints);

  /// Prefer the complete song row/card, including text above its cover. Never
  /// lift the anchor to an entire long Column or to another reveal viewport.
  Rect? _visibleRow(ArtworkRevealEntry entry) {
    if (!entry.enabled) return null;
    final box = entry.box();
    if (box == null || !box.attached || !box.hasSize || box.size.isEmpty) {
      return null;
    }
    RenderBox anchor = box;
    for (RenderObject? p = box.parent; p != null && p != this; p = p.parent) {
      if (p is RenderOffstage && p.offstage) return null;
      if (p is RenderFlex && p.hasSize) {
        if (p.direction == Axis.horizontal) {
          anchor = p;
          break;
        }
        if (p.size.height <= box.size.height + 120) anchor = p;
      }
    }
    final imageRect = MatrixUtils.transformRect(
      box.getTransformTo(this),
      Offset.zero & box.size,
    );
    if (!imageRect.overlaps(Offset.zero & size)) return null;
    return MatrixUtils.transformRect(
      anchor.getTransformTo(this),
      Offset.zero & anchor.size,
    );
  }

  double _refreshTop() {
    for (final read in controller._refreshes.values) {
      final box = read?.call();
      if (box == null || !box.attached || !box.hasSize) continue;
      RenderObject? ancestor = box;
      while (ancestor != null && ancestor != this) {
        ancestor = ancestor.parent;
      }
      if (ancestor == null) continue;
      final rect = MatrixUtils.transformRect(
        box.getTransformTo(this),
        Offset.zero & box.size,
      );
      if (rect.overlaps(Offset.zero & size)) {
        return rect.top.clamp(0, size.height);
      }
    }
    return 0;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    var pendingTop = size.height;
    var visible = false, blocked = false;
    var batchTop = size.height;
    for (final entry in controller.entries) {
      final rect = _visibleRow(entry);
      if (rect == null) continue;
      visible = true;
      if (!_committed.contains(entry.identity) && rect.top < batchTop) {
        batchTop = rect.top;
      }
      if (!entry.ready) {
        blocked = true;
        if (rect.top < pendingTop) pendingTop = rect.top;
      }
    }
    _presented = _presented || controller.scrolled;
    _cutoff = blocked
        ? (_presented
              ? (batchTop < pendingTop ? batchTop : pendingTop).clamp(
                  0,
                  size.height,
                )
              : 0)
        : size.height;
    if (visible && !blocked) {
      _presented = true;
      for (final entry in controller.entries) {
        if (entry.ready && _visibleRow(entry) != null) {
          _committed.remove(entry.identity);
          _committed.add(entry.identity);
        }
      }
      while (_committed.length > 512) {
        _committed.remove(_committed.first);
      }
    }
    final loading = blocked || controller.refreshing;
    controller.reportPending(loading);
    if (_cutoff > 0) {
      context.pushClipRect(
        needsCompositing,
        offset,
        Rect.fromLTWH(0, 0, size.width, _cutoff),
        (context, offset) => context.paintChild(content, offset),
      );
    }
    if (blocked) {
      context.canvas.drawRect(
        Rect.fromLTWH(
          offset.dx,
          offset.dy + _cutoff,
          size.width,
          size.height - _cutoff,
        ),
        Paint()..color = _background,
      );
    }
    if (loading) {
      final top = controller.refreshing && !blocked
          ? _refreshTop() + 18.0
          : _cutoff == 0
          ? (size.height - loader.size.height) / 2
          : _cutoff + 14;
      final data = loader.parentData! as _ArtworkParentData;
      data.offset = Offset(
        (size.width - loader.size.width) / 2,
        top.clamp(0, (size.height - loader.size.height).clamp(0, size.height)),
      );
      context.paintChild(loader, offset + data.offset);
    }
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      child == content ? Rect.fromLTWH(0, 0, size.width, _cutoff) : null;
  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_cutoff > 0) visitor(content);
    if (controller.refreshing || _cutoff < size.height) visitor(loader);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      position.dy < _cutoff && content.hitTest(result, position: position);
}
