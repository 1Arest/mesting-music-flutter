import 'package:flutter/material.dart';
import 'beta_glass_popover.dart';

/// Bounded diagnostic previews share the update dialog's glass material.
/// The caller owns redaction, consent, clipboard writes and account validity.
class BetaDiagnosticDialog extends StatelessWidget {
  const BetaDiagnosticDialog({
    required this.title,
    required this.content,
    required this.actions,
    super.key,
  });
  final Widget title, content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: LayoutBuilder(
      builder: (context, bounds) => Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: bounds.maxHeight * .86,
            ),
            child: BetaGlassMenuSurface(
              radius: 28,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DefaultTextStyle.merge(
                      style: Theme.of(context).textTheme.titleLarge,
                      child: title,
                    ),
                    const SizedBox(height: 16),
                    Flexible(child: content),
                    const SizedBox(height: 18),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 10,
                      runSpacing: 10,
                      children: actions,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
