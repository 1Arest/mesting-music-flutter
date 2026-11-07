import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/platform/distribution_channel.dart';
import '../../features/themes/beta_appearance.dart';
import '../../core/haptics/app_haptics.dart';
import 'beta_success_feedback.dart';

OverlayEntry? _activeMusicNotice;
// Kept for callers compiled against older releases; HUDs now use the top inset.
const double musicNoticeBottomClearance = 144;

/// One Apple-style status HUD replaces stale feedback during rapid actions.
/// Capture the invoking theme because the root overlay may have a different one.
void showMusicNotice(
  BuildContext context, {
  required IconData? icon,
  required String title,
  required String message,
}) {
  if (icon == Icons.check_rounded || icon == Icons.check) {
    appHaptic(context, AppHapticEvent.success);
  } else if (icon == Icons.error_outline_rounded ||
      icon == Icons.warning_amber_rounded) {
    appHaptic(context, AppHapticEvent.warning);
  }
  _activeMusicNotice?.remove();
  final overlay = Overlay.of(context, rootOverlay: true);
  final theme = Theme.of(context);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Theme(
      data: theme,
      child: _MusicNoticeOverlay(
        icon: icon,
        title: title,
        message: message,
        onDismissed: () {
          if (_activeMusicNotice != entry) return;
          entry.remove();
          _activeMusicNotice = null;
        },
      ),
    ),
  );
  _activeMusicNotice = entry;
  overlay.insert(entry);
}

class _MusicNoticeOverlay extends StatefulWidget {
  const _MusicNoticeOverlay({
    required this.icon,
    required this.title,
    required this.message,
    required this.onDismissed,
  });
  final IconData? icon;
  final String title, message;
  final VoidCallback onDismissed;
  @override
  State<_MusicNoticeOverlay> createState() => _MusicNoticeOverlayState();
}

class _MusicNoticeOverlayState extends State<_MusicNoticeOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _animation =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 240),
          reverseDuration: const Duration(milliseconds: 180),
        )..addStatusListener((status) {
          if (status == AnimationStatus.dismissed) widget.onDismissed();
        });
    _animation.forward();
    final success =
        DistributionChannel.isBeta &&
        (widget.icon == Icons.check_rounded || widget.icon == Icons.check);
    _timer = Timer(
      Duration(milliseconds: success ? 2600 : 1900),
      _animation.reverse,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark ? Colors.white : const Color(0xFF212124);
    final error =
        widget.icon == Icons.error_outline_rounded ||
        widget.icon == Icons.warning_amber_rounded;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final animation = CurvedAnimation(
      parent: _animation,
      curve: Curves.easeOutCubic,
    );
    final label = error && widget.message.trim().isNotEmpty
        ? '${widget.title}。${widget.message}'
        : widget.title;
    return Positioned(
      top: MediaQuery.viewPaddingOf(context).top + 12,
      left: 22,
      right: 22,
      child: IgnorePointer(
        child: Center(
          child: Semantics(
            liveRegion: true,
            label: label,
            child: FadeTransition(
              opacity: reduced ? kAlwaysCompleteAnimation : animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: reduced ? Offset.zero : const Offset(0, -.18),
                  end: Offset.zero,
                ).animate(animation),
                child: ScaleTransition(
                  scale: Tween<double>(
                    begin: reduced ? 1 : .96,
                    end: 1,
                  ).animate(animation),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(25),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: Material(
                        color: dark
                            ? const Color(0xB82C2C2E)
                            : const Color(0xCCF9F9FB),
                        child: Container(
                          key: const ValueKey('apple-status-notice'),
                          constraints: const BoxConstraints(
                            maxWidth: 380,
                            minHeight: 50,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 13,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(25),
                            border: Border.all(
                              color: dark ? Colors.white24 : Colors.white70,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.icon != null) ...[
                                if (DistributionChannel.isBeta &&
                                    (widget.icon == Icons.check_rounded ||
                                        widget.icon == Icons.check))
                                  BetaSuccessMark(
                                    animated: false,
                                    color: BetaAppearance.success(
                                      Theme.of(context).brightness,
                                    ),
                                  )
                                else
                                  Icon(
                                    widget.icon,
                                    color: error
                                        ? foreground
                                        : BetaAppearance.accent(
                                            Theme.of(context).brightness,
                                          ),
                                    size: 22,
                                  ),
                                const SizedBox(width: 10),
                              ],
                              Flexible(
                                child: Text(
                                  label,
                                  maxLines: error ? 3 : 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: foreground,
                                    fontSize: 14,
                                    height: 1.25,
                                    decoration: TextDecoration.none,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
