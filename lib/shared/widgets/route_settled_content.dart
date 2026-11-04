import 'package:flutter/material.dart';
import 'beta_entrance_readiness.dart';
import 'beta_root_tab_viewport.dart';

/// Start optional shelves/cover work once the entering route has settled.
/// Already-visible content stays mounted on pop/interactive back, so this
/// avoids competing image uploads during entry without replacing live glass
/// with route screenshots or changing navigation/gesture animations.
class RouteSettledContent extends StatefulWidget {
  const RouteSettledContent({
    required this.builder,
    required this.placeholder,
    super.key,
  });
  final WidgetBuilder builder;
  final Widget placeholder;
  @override
  State<RouteSettledContent> createState() => _RouteSettledContentState();
}

class _RouteSettledContentState extends State<RouteSettledContent> {
  Animation<double>? _animation;
  ModalRoute<dynamic>? _route;
  bool _ready = false;
  bool _surfaceReady = true;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _surfaceReady =
        BetaEntranceReadiness.of(context) &&
        BetaTabVisibility.settledOf(context);
    final route = ModalRoute.of(context);
    _route = route;
    final animation = route?.animation;
    if (_animation != animation) {
      _animation?.removeStatusListener(_settled);
      _animation = animation;
      _animation?.addStatusListener(_settled);
    }
    _ready =
        _ready ||
        (_surfaceReady &&
            (animation == null ||
                (!route!.offstage &&
                    animation.status == AnimationStatus.completed)));
  }

  void _settled(AnimationStatus status) {
    if (status == AnimationStatus.completed &&
        _surfaceReady &&
        _route?.offstage != true &&
        !_ready &&
        mounted) {
      setState(() => _ready = true);
    }
  }

  @override
  void dispose() {
    _animation?.removeStatusListener(_settled);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _ready ? widget.builder(context) : widget.placeholder;
}
