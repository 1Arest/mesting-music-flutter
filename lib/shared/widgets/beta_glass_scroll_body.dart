import 'package:flutter/material.dart';
import 'beta_content_insets.dart';

/// Paint the page surface inside the scrollable's overscroll composition pass.
/// A Scaffold behind that pass is not available to a glass backdrop sampler.
/// Keeping the backing surface here preserves both premium optics and stretch.
class BetaGlassScrollBody extends StatelessWidget {
  const BetaGlassScrollBody({
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(24, 30, 24, 32),
    this.controller,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
    super.key,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final ScrollController? controller;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, viewport) => ListView(
      controller: controller,
      keyboardDismissBehavior: keyboardDismissBehavior,
      padding: EdgeInsets.zero,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: viewport.maxHeight),
          child: ColoredBox(
            key: const ValueKey('glass-scroll-backing-surface'),
            color: Theme.of(context).colorScheme.surface,
            child: Padding(
              padding: padding
                  .resolve(Directionality.of(context))
                  .copyWith(
                    bottom: BetaContentInsets.bottomOf(
                      context,
                      padding.resolve(Directionality.of(context)).bottom,
                    ),
                  ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
