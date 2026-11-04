import 'package:flutter/widgets.dart';

/// A refresh has one visual owner. Descendant data loaders keep their layout
/// and business state, while this scope suppresses their duplicate animation.
/// Explicit action-button progress may opt out because it owns another task.
class MusicLoadingScope extends InheritedWidget {
  const MusicLoadingScope({
    required this.covered,
    required super.child,
    super.key,
  });
  final bool covered;
  static bool coveredOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<MusicLoadingScope>()
          ?.covered ??
      false;
  @override
  bool updateShouldNotify(MusicLoadingScope oldWidget) =>
      covered != oldWidget.covered;
}

/// A whole data-loading placeholder can yield its padding as well as its
/// spinner to an active refresh. The refresh's single indicator already owns
/// the waiting space, so retaining both gaps would push cached rows away.
class MusicLoadingPlaceholder extends StatelessWidget {
  const MusicLoadingPlaceholder({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      MusicLoadingScope.coveredOf(context) ? const SizedBox.shrink() : child;
}
