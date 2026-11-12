import 'package:flutter/widgets.dart';
import '../../core/platform/distribution_channel.dart';

/// The application publishes its already-selected UI here. Reusable controls
/// must not read credentials, start account restoration, or require Riverpod.
/// Standalone galleries default to their channel's existing visual language.
class BetaControlScope extends InheritedWidget {
  const BetaControlScope({
    required this.apple,
    required super.child,
    super.key,
  });
  final bool apple;
  static bool appleOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BetaControlScope>()?.apple ??
      DistributionChannel.isBeta;
  @override
  bool updateShouldNotify(BetaControlScope oldWidget) =>
      apple != oldWidget.apple;
}
