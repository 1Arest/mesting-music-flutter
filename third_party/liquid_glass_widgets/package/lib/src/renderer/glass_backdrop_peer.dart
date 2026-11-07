import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Contract used by a conservative peer group without importing the engine.
/// Bounds include visible shadows; scaled/overlapping peers stay independent.
abstract interface class GlassBackdropParticipant {
  Rect? sharingBounds(RenderObject group);
  double get sharingReadOutset;
  void invalidateBackdropSharing();
  void clearSharedBackdropKeys();
}

void _invalidatePeers(RenderObject root) {
  if (root is GlassBackdropParticipant) {
    (root as GlassBackdropParticipant).invalidateBackdropSharing();
  }
  root.visitChildren(_invalidatePeers);
}

/// Explicit barrier used only for chrome peers whose layout clock is known.
/// Changing it invalidates retained children before the first transition frame.
class GlassBackdropSharingGate extends SingleChildRenderObjectWidget {
  const GlassBackdropSharingGate(
      {required this.enabled, required super.child, super.key});
  final bool enabled;
  @override
  RenderGlassBackdropSharingGate createRenderObject(BuildContext context) =>
      RenderGlassBackdropSharingGate(enabled);
  @override
  void updateRenderObject(
          BuildContext context, RenderGlassBackdropSharingGate renderObject) =>
      renderObject.enabled = enabled;
}

class RenderGlassBackdropSharingGate extends RenderProxyBox {
  RenderGlassBackdropSharingGate(this._enabled);
  bool _enabled;
  bool get enabled => _enabled;
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    _invalidatePeers(this);
    markNeedsPaint();
  }
}

/// Same 200ms opacity animation as the incumbent accessory. Only this opt-in
/// opacity is transparent to grouping at 1; ordinary opacity remains a barrier.
/// Keeping one render object also preserves the accessory's controllers/state.
class GlassPeerFade extends StatelessWidget {
  const GlassPeerFade({required this.visible, required this.child, super.key});
  final bool visible;
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: visible ? 1 : 0),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: child,
        builder: (_, value, child) =>
            _PeerOpacity(opacity: value, child: child!),
      );
}

class _PeerOpacity extends SingleChildRenderObjectWidget {
  const _PeerOpacity({required this.opacity, required super.child});
  final double opacity;
  @override
  RenderGlassPeerOpacity createRenderObject(BuildContext context) =>
      RenderGlassPeerOpacity(opacity);
  @override
  void updateRenderObject(
          BuildContext context, RenderGlassPeerOpacity renderObject) =>
      renderObject.opacity = opacity;
}

class RenderGlassPeerOpacity extends RenderOpacity {
  RenderGlassPeerOpacity(double value) : super(opacity: value);
  @override
  set opacity(double value) {
    if (super.opacity == value) return;
    // RenderOpacity otherwise recomposites retained children without repaint.
    // Clear their old shared key before entering that new offscreen pass.
    _invalidatePeers(this);
    super.opacity = value;
  }
}
