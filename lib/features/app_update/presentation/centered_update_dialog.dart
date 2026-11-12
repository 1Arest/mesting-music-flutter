import 'package:flutter/material.dart';
import '../../../shared/widgets/beta_glass_popover.dart';

/// Update presentation owns only its route. Download/install state remains in
/// the existing controller, so closing and reopening never restarts a task.
Future<void> showCenteredUpdateDialog(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
}) => showGeneralDialog<void>(
  context: context,
  useRootNavigator: true,
  barrierDismissible: dismissible,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  barrierColor: Colors.black.withValues(alpha: .36),
  transitionDuration: MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 240),
  pageBuilder: (context, _, _) => SafeArea(
    child: LayoutBuilder(
      builder: (context, limits) => Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: ConstrainedBox(
            key: const ValueKey('app-update-centered-dialog'),
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: limits.maxHeight * .86,
            ),
            child: BetaGlassMenuSurface(radius: 28, child: builder(context)),
          ),
        ),
      ),
    ),
  ),
  transitionBuilder: (context, animation, _, child) => FadeTransition(
    opacity: animation,
    child: ScaleTransition(
      scale: Tween(
        begin: .96,
        end: 1.0,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  ),
);
