import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/track.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../../core/platform/distribution_channel.dart';
import '../../themes/beta_appearance.dart';
import 'library_access.dart';
import '../../themes/mesting_palette.dart';
import '../library_providers.dart';
import '../../music_platform/presentation/platform_feedback.dart';

const _favoriteAccent = MestingPalette.favorite;

class FavoriteToggleButton extends ConsumerWidget {
  const FavoriteToggleButton({
    required this.track,
    this.compact = false,
    this.star = false,
    super.key,
  });

  final Track track;
  final bool compact;
  final bool star;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorite = ref.watch(
      favoriteTrackIdsProvider.select((ids) => ids.contains(track.id)),
    );
    const dimension = 48.0;

    return _FavoritePressFeedback(
      child: Semantics(
        button: true,
        selected: favorite,
        label: favorite ? '已收藏《${track.title}》' : '收藏《${track.title}》',
        child: SizedBox(
          key: ValueKey('favorite-button-${track.id}'),
          width: dimension,
          height: dimension,
          child: IconButton(
            tooltip: favorite ? '取消收藏' : '收藏歌曲',
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              // Keep a transparent 48dp target, including inside the player theme.
              backgroundColor: Colors.transparent,
              minimumSize: Size.square(dimension),
              maximumSize: Size.square(dimension),
              foregroundColor: favorite
                  ? (DistributionChannel.isBeta
                        ? BetaAppearance.favorite(Theme.of(context).brightness)
                        : _favoriteAccent)
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              overlayColor: Colors.transparent,
            ),
            onPressed: () async {
              final allowed = await ensureLibraryAccess(
                context,
                ref,
                reason: '登录后才能收藏歌曲，喜欢的音乐会跟随账号在不同设备间同步。',
                redirect: '/music',
              );
              if (!allowed || !context.mounted) return;
              try {
                await ref.read(libraryRepositoryProvider).toggleFavorite(track);
                if (context.mounted) {
                  showMusicNotice(
                    context,
                    icon: star
                        ? (favorite
                              ? Icons.star_border_rounded
                              : Icons.star_rounded)
                        : favorite
                        ? Icons.heart_broken_outlined
                        : Icons.favorite_rounded,
                    title: favorite ? '已取消喜欢' : '已添加到喜欢',
                    message: '',
                  );
                }
              } catch (error) {
                if (context.mounted) showPlatformFailure(context, error);
              }
            },
            icon: star
                ? AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: Icon(
                      favorite ? Icons.star_rounded : Icons.star_border_rounded,
                      key: ValueKey(favorite),
                      size: compact ? 25 : 28,
                    ),
                  )
                : _FavoriteGlyph(favorite: favorite, size: compact ? 21 : 23),
          ),
        ),
      ),
    );
  }
}

/// Successful state changes animate locally; a failed cloud write never plays
/// a misleading filled-heart celebration. Both directions interrupt smoothly.
class _FavoriteGlyph extends StatefulWidget {
  const _FavoriteGlyph({required this.favorite, required this.size});
  final bool favorite;
  final double size;
  @override
  State<_FavoriteGlyph> createState() => _FavoriteGlyphState();
}

class _FavoriteGlyphState extends State<_FavoriteGlyph>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: 1,
  );
  late double _from = widget.favorite ? 1 : 0;
  double get _fill =>
      _from +
      ((widget.favorite ? 1 : 0) - _from) *
          Curves.easeOutCubic.transform(_motion.value);
  @override
  void didUpdateWidget(covariant _FavoriteGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.favorite != widget.favorite) {
      _motion.duration = Duration(milliseconds: widget.favorite ? 420 : 760);
      _from =
          _from +
          ((oldWidget.favorite ? 1.0 : 0.0) - _from) *
              Curves.easeOutCubic.transform(_motion.value);
      if (MediaQuery.disableAnimationsOf(context)) {
        _motion.value = 1;
      } else {
        _motion.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: _motion,
      builder: (_, _) {
        final pulse = TweenSequence<double>([
          TweenSequenceItem(
            tween: Tween(
              begin: 1.0,
              end: widget.favorite ? 1.24 : .8,
            ).chain(CurveTween(curve: Curves.easeOutCubic)),
            weight: 35,
          ),
          TweenSequenceItem(
            tween: Tween(
              begin: widget.favorite ? 1.24 : .8,
              end: 1.0,
            ).chain(CurveTween(curve: Curves.easeOutBack)),
            weight: 65,
          ),
        ]).transform(_motion.value);
        return Transform.scale(
          scale: pulse,
          child: SizedBox.square(
            dimension: widget.size,
            child: Stack(
              children: [
                if (!widget.favorite && _motion.value < .78)
                  Opacity(
                    opacity: (1 - _motion.value / .78).clamp(0.0, 1.0),
                    child: Icon(Icons.heart_broken_outlined, size: widget.size),
                  ),
                if (_fill < 1)
                  Opacity(
                    opacity: !widget.favorite && _motion.value < .78
                        ? 0
                        : 1 - _fill,
                    child: Icon(
                      Icons.favorite_border_rounded,
                      size: widget.size,
                    ),
                  ),
                if (_fill > 0 && (widget.favorite || _motion.value >= .78))
                  Opacity(
                    opacity: _fill,
                    child: Icon(Icons.favorite_rounded, size: widget.size),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Bare glyphs still acknowledge the pointer immediately, while the existing
/// IconButton owns activation, keyboard access and the eventual cloud result.
class _FavoritePressFeedback extends StatefulWidget {
  const _FavoritePressFeedback({required this.child});
  final Widget child;
  @override
  State<_FavoritePressFeedback> createState() => _FavoritePressFeedbackState();
}

class _FavoritePressFeedbackState extends State<_FavoritePressFeedback> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => setState(() => _pressed = true),
    onPointerUp: (_) => setState(() => _pressed = false),
    onPointerCancel: (_) => setState(() => _pressed = false),
    child: AnimatedScale(
      scale: _pressed ? .88 : 1,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      child: widget.child,
    ),
  );
}
