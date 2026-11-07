import 'package:flutter/material.dart';
import 'beta_glass_controls.dart';
import 'beta_secondary_music_layout.dart';

/// Secondary music pages inherit the existing neutral surface, readable type
/// and independent glass navigation. Feature state stays with each caller.
class MusicFeaturePage extends StatelessWidget {
  const MusicFeaturePage({
    required this.title,
    required this.child,
    this.actions,
    super.key,
  });
  final String title;
  final Widget child;
  final List<Widget>? actions;
  @override
  Widget build(BuildContext context) => BetaSecondaryMusicLayout.wrap(
    context,
    Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        leadingWidth: 68,
        leading: const Center(child: BetaGlassBackButton()),
        title: Text(
          title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        actions: actions,
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: child,
          ),
        ),
      ),
    ),
  );
}

class MusicFeatureMessage extends StatelessWidget {
  const MusicFeatureMessage({required this.message, this.onRetry, super.key});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              height: 1.6,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 20),
            BetaGlassButton(
              onPressed: onRetry,
              accent: true,
              child: const Text('重试'),
            ),
          ],
        ],
      ),
    ),
  );
}
