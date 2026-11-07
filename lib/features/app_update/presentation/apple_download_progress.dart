import 'package:flutter/material.dart';
import '../../themes/beta_appearance.dart';

/// The first frame starts at persisted progress, so reopening a download never
/// animates from zero. Only the capsule fill interpolates; labels always report
/// actual received bytes, and 100% does not claim that verification has passed.
class AppleDownloadProgress extends StatelessWidget {
  const AppleDownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
    this.semanticLabel = '更新下载进度',
    super.key,
  });
  final int receivedBytes, totalBytes;
  final String semanticLabel;
  @override
  Widget build(BuildContext context) {
    final fraction = totalBytes > 0
        ? (receivedBytes / totalBytes).clamp(0.0, 1.0)
        : 0.0;
    final percent = totalBytes > 0 ? '${(fraction * 100).round()}%' : '总大小未知';
    final bytes = totalBytes > 0
        ? '${formatDownloadBytes(receivedBytes)} / ${formatDownloadBytes(totalBytes)}'
        : '已下载 ${formatDownloadBytes(receivedBytes)}';
    final scheme = Theme.of(context).colorScheme;
    final blue = BetaAppearance.accent(Theme.of(context).brightness);
    return Semantics(
      label: semanticLabel,
      value: '$percent，$bytes',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: fraction, end: fraction),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                height: 4,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Positioned.fill(
                      child: ColoredBox(
                        color: scheme.onSurface.withValues(alpha: .12),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: value,
                      child: ColoredBox(
                        color: blue,
                        child: const SizedBox(height: 4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          DefaultTextStyle.merge(
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            child: Row(
              children: [
                Expanded(child: Text(bytes)),
                const SizedBox(width: 16),
                Text(
                  percent,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Byte labels always describe measured bytes, including an unknown-length CDN.
String formatDownloadBytes(int bytes) => bytes >= 1048576
    ? '${(bytes / 1048576).toStringAsFixed(1)} MB'
    : '${(bytes.clamp(0, 1 << 60) / 1024).toStringAsFixed(1)} KB';
