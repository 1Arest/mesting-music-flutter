import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/platform/distribution_channel.dart';

/// Shared decoration for Beta login forms and the two login method pickers.
/// The illustration never overlays the form: each owns a separate layout slot.
/// Keyboard and short landscape windows give the entire height back to inputs.
class BetaLoginArtworkFrame extends StatelessWidget {
  const BetaLoginArtworkFrame({
    required this.child,
    this.enabled = true,
    super.key,
  });

  static const asset = 'assets/branding/login/companions-bottom.png';
  static const artworkKey = ValueKey('beta-login-bottom-artwork');
  static const gap = 24.0;

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled || !DistributionChannel.isBeta) return child;
    return LayoutBuilder(
      builder: (context, bounds) {
        final showArtwork =
            MediaQuery.viewInsetsOf(context).bottom == 0 &&
            bounds.maxHeight >= 480;
        // Retain the approved 85% height, stretching only horizontally to the
        // screen edges. Limit the height on wide windows to protect the form.
        final height = math.min(
          bounds.maxWidth * (2 / 3) * .85,
          bounds.maxHeight * .28,
        );
        return ColoredBox(
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: child),
              // The form stays under the same Expanded when art hides, so
              // keyboard focus and scroll state survive the height change.
              if (showArtwork) ...[
                const SizedBox(height: gap),
                ExcludeSemantics(
                  child: IgnorePointer(
                    child: Image.asset(
                      asset,
                      key: artworkKey,
                      width: bounds.maxWidth,
                      height: height,
                      fit: BoxFit.fill,
                      // Decode near the displayed size, not the 1536px master.
                      cacheWidth:
                          (bounds.maxWidth *
                                  MediaQuery.devicePixelRatioOf(context))
                              .ceil(),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
