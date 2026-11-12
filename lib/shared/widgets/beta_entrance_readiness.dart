import 'package:flutter/widgets.dart';

/// Optional cold content can start after its containing surface has entered.
/// This does not pause audio/network state or replace already mounted content.
class BetaEntranceReadiness extends InheritedWidget {
  const BetaEntranceReadiness({
    required this.ready,
    required super.child,
    super.key,
  });
  final bool ready;
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<BetaEntranceReadiness>()
          ?.ready ??
      true;
  @override
  bool updateShouldNotify(BetaEntranceReadiness oldWidget) =>
      ready != oldWidget.ready;
}
