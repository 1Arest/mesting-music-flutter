import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'personal_style.dart';

/// Opt-in for the signed-in user's avatar only. Public artists, comments and
/// other account avatars must not inherit the local user's accessory.
class PersonalAvatarDecoration extends ConsumerWidget {
  const PersonalAvatarDecoration({
    required this.child,
    this.accessory,
    super.key,
  });
  final Widget child;
  final AvatarAccessory? accessory;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value =
        accessory ??
        ref.watch(personalStyleProvider.select((s) => s.accessory));
    if (value == AvatarAccessory.none) return child;
    final icon = switch (value) {
      AvatarAccessory.notes => Icons.music_note_rounded,
      AvatarAccessory.stars => Icons.auto_awesome,
      AvatarAccessory.moon => Icons.nightlight_round,
      AvatarAccessory.bow => Icons.all_inclusive,
      AvatarAccessory.record => Icons.album_outlined,
      _ => Icons.circle_outlined,
    };
    return Stack(
      clipBehavior: Clip.none,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          ),
          child: child,
        ),
        Positioned(
          right: -3,
          bottom: -3,
          child: ExcludeSemantics(
            child: value == AvatarAccessory.bow
                ? SizedBox.square(
                    dimension: 22,
                    child: CustomPaint(
                      painter: _BowPainter(
                        Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  )
                : Icon(
                    icon,
                    size: 22,
                    color: Theme.of(context).colorScheme.primary,
                  ),
          ),
        ),
      ],
    );
  }
}

class PersonalMiniPlayer extends ConsumerWidget {
  const PersonalMiniPlayer({required this.child, this.finish, super.key});
  final MiniPlayerFinish? finish;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final MiniPlayerFinish finish =
        this.finish ?? ref.watch(personalStyleProvider.select((s) => s.mini));
    if (finish == MiniPlayerFinish.original) return child;
    return DecoratedBox(
      key: ValueKey('mini-finish-${finish.name}'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        color: finish == MiniPlayerFinish.frosted
            ? Colors.white.withValues(alpha: .07)
            : null,
        border: finish == MiniPlayerFinish.metal
            ? Border.all(color: const Color(0xFFB2B6BD), width: 1)
            : null,
      ),
      child: CustomPaint(
        foregroundPainter: finish == MiniPlayerFinish.gradient
            ? _MiniOutline()
            : null,
        child: child,
      ),
    );
  }
}

class _BowPainter extends CustomPainter {
  _BowPainter(this.color);
  final Color color;
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = color;
    c.drawPath(
      Path()
        ..moveTo(10, 11)
        ..lineTo(1, 4)
        ..quadraticBezierTo(-2, 11, 1, 18)
        ..close(),
      p,
    );
    c.drawPath(
      Path()
        ..moveTo(12, 11)
        ..lineTo(21, 4)
        ..quadraticBezierTo(24, 11, 21, 18)
        ..close(),
      p,
    );
    c.drawCircle(const Offset(11, 11), 3, p);
  }

  @override
  bool shouldRepaint(covariant _BowPainter old) => color != old.color;
}

class _MiniOutline extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final rect = (Offset.zero & s).deflate(1);
    c.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(32)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = const LinearGradient(
          colors: [Color(0xFF5CA5EB), Color(0xFFAC80D8), Color(0xFFE475A4)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _MiniOutline old) => false;
}
