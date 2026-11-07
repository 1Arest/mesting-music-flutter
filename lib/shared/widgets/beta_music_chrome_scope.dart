import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'beta_root_tab_viewport.dart';
import 'beta_page_route_observer.dart';

/// Route addresses cannot describe pages pushed on a retained tab Navigator.
/// Fullscreen content registers its actual visibility here instead. The render
/// gate reads this signal at paint/hit-test time, so mounting a covering page
/// cannot leave one frame of the persistent music controls above that page.
class BetaMusicChromeController extends ChangeNotifier {
  final _covers = <Object, bool>{};
  Object? _player;
  bool _playerReset = false;
  bool get covered => _covers.isNotEmpty;

  void cover(Object owner, {required bool player}) {
    if (_covers[owner] == player) return;
    _covers[owner] = player;
    if (player) {
      _player = owner;
      _playerReset = false;
    }
    notifyListeners();
  }

  void uncover(Object owner) {
    if (_covers.remove(owner) == null) return;
    if (identical(_player, owner)) {
      _player = null;
      _playerReset = false;
    }
    notifyListeners();
  }

  double opacity(double reveal, {bool revealHandledByRoute = false}) {
    if (_covers.isEmpty) return 1;
    if (_covers.values.any((player) => !player)) return 0;
    // A previous player's dismissal may have left the shared signal at one.
    // Only the newly mounted player's reset may enable its own drag reveal.
    if (reveal == 0) _playerReset = true;
    return _playerReset
        ? (revealHandledByRoute ? 1 : reveal.clamp(0.0, 1.0))
        : 0;
  }
}

class BetaMusicChromeScope extends InheritedWidget {
  const BetaMusicChromeScope({
    required this.controller,
    required super.child,
    super.key,
  });
  final BetaMusicChromeController controller;
  static BetaMusicChromeController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<BetaMusicChromeScope>()
      ?.controller;
  @override
  bool updateShouldNotify(BetaMusicChromeScope oldWidget) =>
      controller != oldWidget.controller;
}

/// Used by the player and by pages that own their own composer/bottom area.
/// Retained, covered routes never suppress the active tab's controls.
class BetaMusicChromeCover extends StatefulWidget {
  const BetaMusicChromeCover({
    required this.child,
    this.player = false,
    this.enabled = true,
    super.key,
  });
  final Widget child;
  final bool player, enabled;
  @override
  State<BetaMusicChromeCover> createState() => _BetaMusicChromeCoverState();
}

class _BetaMusicChromeCoverState extends State<BetaMusicChromeCover> {
  BetaMusicChromeController? _controller;
  BetaPageRouteObserver? _routes;
  bool _active = true;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = BetaMusicChromeScope.maybeOf(context);
    if (next != _controller) {
      _controller?.uncover(this);
      _controller = next;
    }
    final routes = BetaPageRouteObserver.maybeOf(context);
    if (_routes != routes) {
      _routes?.removeListener(_synchronize);
      _routes = routes;
      _routes?.addListener(_synchronize);
    }
    _synchronize();
  }

  void _synchronize() {
    if (!_active) return;
    final route = ModalRoute.of(context);
    if (widget.enabled &&
        BetaTabVisibility.of(context) &&
        (_routes?.isTopPage(route) ?? (route?.isCurrent ?? true))) {
      _controller?.cover(this, player: widget.player);
    } else {
      _controller?.uncover(this);
    }
  }

  @override
  void didUpdateWidget(covariant BetaMusicChromeCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    _synchronize();
  }

  @override
  void deactivate() {
    _active = false;
    _routes?.removeListener(_synchronize);
    _routes = null;
    _controller?.uncover(this);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
  }

  @override
  void dispose() {
    _routes?.removeListener(_synchronize);
    _controller?.uncover(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class BetaMusicChromeGate extends SingleChildRenderObjectWidget {
  const BetaMusicChromeGate({
    required this.controller,
    required this.playerReveal,
    this.revealHandledByRoute = false,
    required super.child,
    super.key,
  });
  final BetaMusicChromeController controller;
  final ValueListenable<double> playerReveal;
  final bool revealHandledByRoute;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderBetaMusicChromeGate(controller, playerReveal, revealHandledByRoute);
  @override
  void updateRenderObject(
    BuildContext context,
    RenderBetaMusicChromeGate renderObject,
  ) => renderObject.update(controller, playerReveal, revealHandledByRoute);
}

class RenderBetaMusicChromeGate extends RenderProxyBox {
  RenderBetaMusicChromeGate(
    this._controller,
    this._reveal,
    this._revealHandledByRoute,
  );
  BetaMusicChromeController _controller;
  ValueListenable<double> _reveal;
  bool _revealHandledByRoute;
  void _changed() {
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  void update(
    BetaMusicChromeController controller,
    ValueListenable<double> reveal,
    bool revealHandledByRoute,
  ) {
    if (controller == _controller &&
        reveal == _reveal &&
        revealHandledByRoute == _revealHandledByRoute) {
      return;
    }
    if (attached) {
      _controller.removeListener(_changed);
      _reveal.removeListener(_changed);
    }
    _controller = controller;
    _reveal = reveal;
    _revealHandledByRoute = revealHandledByRoute;
    if (attached) {
      _controller.addListener(_changed);
      _reveal.addListener(_changed);
    }
    _changed();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(_changed);
    _reveal.addListener(_changed);
  }

  @override
  void detach() {
    _controller.removeListener(_changed);
    _reveal.removeListener(_changed);
    super.detach();
  }

  @override
  bool get alwaysNeedsCompositing {
    final opacity = _controller.opacity(
      _reveal.value,
      revealHandledByRoute: _revealHandledByRoute,
    );
    return child != null && opacity > 0 && opacity < 1;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final opacity = _controller.opacity(
      _reveal.value,
      revealHandledByRoute: _revealHandledByRoute,
    );
    if (child == null || opacity == 0) return;
    if (opacity == 1) {
      super.paint(context, offset);
    } else {
      context.pushOpacity(offset, (opacity * 255).round(), super.paint);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      !_controller.covered && super.hitTestChildren(result, position: position);

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (!_controller.covered) super.visitChildrenForSemantics(visitor);
  }
}
