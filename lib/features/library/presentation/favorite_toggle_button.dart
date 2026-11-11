import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/track.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../../core/platform/distribution_channel.dart';
import '../../themes/beta_appearance.dart';
import 'library_access.dart';
import '../../themes/mesting_palette.dart';
import '../library_providers.dart';
import '../data/song_favorite_count.dart';
import '../../music_platform/presentation/platform_feedback.dart';

const _favoriteAccent = MestingPalette.favorite;

/// Shared by the player, list glyphs and their status HUDs.
Color favoriteFeedbackColor(BuildContext context) => DistributionChannel.isBeta
    ? BetaAppearance.favorite(Theme.of(context).brightness)
    : _favoriteAccent;

class FavoriteToggleButton extends ConsumerWidget {
  const FavoriteToggleButton({
    required this.track,
    this.compact = false,
    this.star = false,
    this.player = false,
    super.key,
  });

  final Track track;
  final bool compact;
  final bool star;

  /// Extra horizontal room keeps the count beside the player heart.
  final bool player;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorite = ref.watch(
      favoriteTrackIdsProvider.select((ids) => ids.contains(track.id)),
    );
    const dimension = 48.0;
    final buttonWidth = player ? 72.0 : dimension;
    final song = songCountIdentity(track);
    final count = song != null
        ? ref.watch(songFavoriteCountProvider(song)).value
        : null;

    return _FavoritePressFeedback(
      child: Semantics(
        button: true,
        selected: favorite,
        label: [
          favorite ? '已收藏《${track.title}》' : '收藏《${track.title}》',
          if (count != null) '平台收藏总数 $count',
        ].join('，'),
        child: SizedBox(
          key: ValueKey('favorite-button-${track.id}'),
          width: buttonWidth,
          height: dimension,
          child: Stack(
            children: [
              Positioned.fill(
                child: IconButton(
                  tooltip: favorite ? '取消收藏' : '收藏歌曲',
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    // Keep a transparent 48dp target, including inside the player theme.
                    backgroundColor: Colors.transparent,
                    minimumSize: Size(buttonWidth, dimension),
                    maximumSize: Size(buttonWidth, dimension),
                    foregroundColor: favorite
                        ? (DistributionChannel.isBeta
                              ? BetaAppearance.favorite(
                                  Theme.of(context).brightness,
                                )
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
                      final next = await ref
                          .read(favoriteMutationsProvider)
                          .toggle(track, wasFavorite: favorite);
                      if (context.mounted && next != null) {
                        if (count != null && song != null) {
                          ref
                              .read(songFavoriteCountCacheProvider)
                              .invalidate(song);
                          ref.invalidate(songFavoriteCountProvider(song));
                        }
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
                          iconColor: favoriteFeedbackColor(context),
                        );
                      }
                    } catch (error) {
                      if (context.mounted) showPlatformFailure(context, error);
                    }
                  },
                  icon: Padding(
                    padding: EdgeInsets.only(
                      right: player
                          ? 36
                          : count != null
                          ? 12
                          : 0,
                    ),
                    child: star
                        ? Icon(
                            favorite
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            key: ValueKey(favorite),
                            size: compact ? 25 : 28,
                          )
                        : _FavoriteGlyph(
                            favorite: favorite,
                            size: player
                                ? 28
                                : compact
                                ? 21
                                : 23,
                            thin: player,
                          ),
                  ),
                ),
              ),
              if (count != null)
                Positioned(
                  left: player ? 32 : 26,
                  right: 0,
                  top: player ? 8 : 6,
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: SizedBox(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            formatSongFavoriteCount(count),
                            key: ValueKey('song-favorite-count-${track.id}'),
                            style: TextStyle(
                              fontSize: player ? 9.5 : 8,
                              height: 1,
                              fontWeight: FontWeight.w500,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              color: favorite
                                  ? favoriteFeedbackColor(context)
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The glyph commits immediately; only its small scale acknowledgment animates.
/// A cloud rollback therefore restores the outline on its first painted frame.
class _FavoriteGlyph extends StatefulWidget {
  const _FavoriteGlyph({
    required this.favorite,
    required this.size,
    this.thin = false,
  });
  final bool favorite;
  final double size;
  final bool thin;
  @override
  State<_FavoriteGlyph> createState() => _FavoriteGlyphState();
}

class _FavoriteGlyphState extends State<_FavoriteGlyph>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: 1,
  );
  @override
  void didUpdateWidget(covariant _FavoriteGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.favorite != widget.favorite) {
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
      builder: (_, child) => Transform.scale(
        scale: 1 + .12 * (1 - Curves.easeOutCubic.transform(_motion.value)),
        child: child,
      ),
      child: Icon(
        widget.thin
            ? (widget.favorite
                  ? CupertinoIcons.heart_fill
                  : CupertinoIcons.heart)
            : widget.favorite
            ? Icons.favorite_rounded
            : Icons.favorite_border_rounded,
        size: widget.size,
      ),
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
