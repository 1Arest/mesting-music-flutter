import 'package:flutter/material.dart';

/// Application-owned pages and sheets follow the user's appearance, even when
/// opened beneath the artwork player's deliberately dark local Theme. Keeping
/// this above the router also updates retained tabs and already-open sheets.
class MusicApplicationTheme extends InheritedWidget {
  const MusicApplicationTheme({
    required this.data,
    required super.child,
    super.key,
  });

  final ThemeData data;

  static ThemeData of(BuildContext context) {
    final application = context
        .dependOnInheritedWidgetOfExactType<MusicApplicationTheme>();
    if (application != null) return application.data;
    // Standalone routes/tests still have a complete MaterialApp theme. Never
    // manufacture a second palette from brightness alone: typography and
    // semantic surface/foreground colors must come from the same ThemeData.
    final root = Navigator.maybeOf(context, rootNavigator: true);
    return Theme.of(root?.context ?? context);
  }

  @override
  bool updateShouldNotify(MusicApplicationTheme oldWidget) =>
      data != oldWidget.data;
}
