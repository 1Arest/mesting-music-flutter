import 'package:flutter/widgets.dart';
import 'keyboard_visibility_builder.dart';

/// Measure against the physical window, not a possibly inset-consumed
/// MediaQuery. Both resizing Scaffolds and full-height glass shells can own a
/// local composer without applying the keyboard inset twice.
class KeyboardOverlayLayout extends StatelessWidget {
  const KeyboardOverlayLayout({required this.builder, super.key});
  final Widget Function(BuildContext, double lift, bool keyboard) builder;
  @override
  Widget build(BuildContext context) => KeyboardVisibilityBuilder(
    builder: (context, keyboard) => LayoutBuilder(
      builder: (context, constraints) {
        final view = View.of(context);
        final inset = view.viewInsets.bottom / view.devicePixelRatio;
        final height = view.physicalSize.height / view.devicePixelRatio;
        final render = context.findRenderObject();
        final top = render is RenderBox && render.hasSize
            ? render.localToGlobal(Offset.zero).dy
            : MediaQuery.paddingOf(context).top;
        final lift = (top + constraints.maxHeight - (height - inset)).clamp(
          0.0,
          inset,
        );
        return builder(context, lift, keyboard);
      },
    ),
  );
}
