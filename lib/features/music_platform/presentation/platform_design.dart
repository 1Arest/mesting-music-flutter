import 'package:flutter/material.dart';
import '../../../shared/widgets/song_list_tools.dart';
import '../../../shared/widgets/artwork_reveal_boundary.dart';
import '../../../shared/widgets/beta_edge_back.dart';
import '../../../shared/widgets/beta_secondary_music_layout.dart';
import '../../../shared/widgets/beta_music_chrome_scope.dart';
import '../../../shared/widgets/overflow_marquee.dart';
import '../../../shared/widgets/mesting_loading_indicator.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../themes/music_theme_tokens.dart';
import '../../themes/music_typography.dart';

/// Shared visual adapter for all imported platform surfaces. Business widgets
/// keep their own repositories; the adapter only reuses Mesting theme tokens.
class PlatformStyle extends StatelessWidget {
  const PlatformStyle({
    required this.child,
    this.artworkReadiness = true,
    super.key,
  });
  final Widget child;
  final bool artworkReadiness;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.musicThemeTokens;
    const shape = StadiumBorder();
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerLow,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 17,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: tokens.borderStrong),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: tokens.borderStrong),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(
              color: theme.colorScheme.primary,
              width: 1.5,
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
            shape: shape,
            textStyle: theme.textTheme.labelLarge?.copyWith(
              fontSize: MusicTypography.subheadlineSize,
              fontWeight: MusicTypography.bodyWeight,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 48),
            shape: shape,
            side: BorderSide(color: tokens.borderStrong),
            backgroundColor: theme.colorScheme.surfaceContainerLow,
            foregroundColor: tokens.textPrimary,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            minimumSize: const Size(44, 44),
            shape: shape,
            textStyle: theme.textTheme.labelLarge?.copyWith(
              fontWeight: MusicTypography.bodyWeight,
            ),
          ),
        ),
        chipTheme: theme.chipTheme.copyWith(
          backgroundColor: theme.colorScheme.surfaceContainerLow,
          selectedColor: theme.brightness == Brightness.dark
              ? theme.colorScheme.primary.withValues(alpha: .16)
              : theme.colorScheme.onSurface.withValues(alpha: .1),
          side: BorderSide.none,
          shape: const StadiumBorder(),
          labelStyle: theme.textTheme.labelLarge?.copyWith(
            color: tokens.textPrimary,
            fontWeight: MusicTypography.bodyWeight,
          ),
        ),
        popupMenuTheme: theme.popupMenuTheme.copyWith(
          color: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
        dialogTheme: theme.dialogTheme.copyWith(
          backgroundColor: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
      ),
      child: artworkReadiness ? ArtworkRevealBoundary(child: child) : child,
    );
  }
}

class PlatformPanel extends StatelessWidget {
  const PlatformPanel({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    super.key,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Padding(padding: padding, child: child),
  );
}

class PlatformPageFrame extends StatelessWidget {
  const PlatformPageFrame({
    required this.title,
    required this.child,
    this.subtitle = '',
    this.actions = const [],
    this.pageKey,
    this.centerTitle = false,
    this.titleWeight = MusicTypography.titleWeight,
    this.titleFontSize = MusicTypography.bodySize,
    this.musicChrome = true,
    this.headerInScroll = false,
    super.key,
  });
  final String title;
  final String subtitle;
  final Widget child;
  final List<Widget> actions;
  final Key? pageKey;
  final bool centerTitle;

  /// Composer pages already own a bottom glass input surface. Music navigation
  /// must never be stacked over their send/reply controls.
  final bool musicChrome;

  /// Collection mastheads own their navigation and scroll with the artwork.
  /// All other secondary pages retain the established fixed glass header.
  final bool headerInScroll;
  final FontWeight titleWeight;
  final double titleFontSize;
  @override
  Widget build(BuildContext context) => BetaMusicChromeCover(
    enabled: !musicChrome,
    child: BetaSecondaryMusicLayout.wrap(
      context,
      PlatformStyle(
        artworkReadiness: false,
        child: BetaEdgeBack(
          child: Scaffold(
            key: pageKey,
            backgroundColor: Theme.of(context).colorScheme.surface,
            body: SafeArea(
              top: !headerInScroll,
              child: Column(
                children: [
                  if (!headerInScroll)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: centerTitle
                          ? SizedBox(
                              height: 52,
                              child: CustomMultiChildLayout(
                                delegate: _CenteredPlatformHeader(),
                                children: [
                                  LayoutId(
                                    id: 'back',
                                    child: BetaGlassBackButton(
                                      onPressed: () =>
                                          Navigator.of(context).maybePop(),
                                    ),
                                  ),
                                  LayoutId(
                                    id: 'title',
                                    child: Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: titleFontSize,
                                        fontWeight: titleWeight,
                                      ),
                                    ),
                                  ),
                                  LayoutId(
                                    id: 'actions',
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: actions,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Row(
                              children: [
                                BetaGlassBackButton(
                                  onPressed: () =>
                                      Navigator.of(context).maybePop(),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      OverflowMarquee(
                                        title,
                                        style: TextStyle(
                                          fontSize:
                                              MusicTypography.sectionTitleSize,
                                          fontWeight: titleWeight,
                                          height: 1.2,
                                          color: context
                                              .musicThemeTokens
                                              .textPrimary,
                                          letterSpacing: -.5,
                                        ),
                                      ),
                                      if (subtitle.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 5,
                                          ),
                                          child: Text(
                                            subtitle,
                                            style: TextStyle(
                                              fontSize:
                                                  MusicTypography.captionSize,
                                              color: context
                                                  .musicThemeTokens
                                                  .textSecondary,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                ...actions,
                              ],
                            ),
                    ),
                  // Keep an opaque backdrop in the same scroll compositing pass.
                  Expanded(
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.surface,
                      child: SongListTools(
                        listId: 'platform-frame:$title:${pageKey ?? ''}',
                        child: ArtworkRevealBoundary(child: child),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      enabled: musicChrome,
    ),
  );
}

/// Equal title gutters use the larger measured action group. The text remains
/// centred on the page even with asymmetric buttons or accessibility scaling;
/// ellipsis handles a long peer name without covering either control group.
class _CenteredPlatformHeader extends MultiChildLayoutDelegate {
  @override
  void performLayout(Size size) {
    final back = layoutChild('back', BoxConstraints.loose(size));
    final actions = layoutChild(
      'actions',
      BoxConstraints(
        maxWidth: (size.width - back.width - 8).clamp(0, size.width),
        maxHeight: size.height,
      ),
    );
    final side = (back.width > actions.width ? back.width : actions.width) + 4;
    final title = layoutChild(
      'title',
      BoxConstraints(
        maxWidth: (size.width - side * 2).clamp(0, size.width),
        maxHeight: size.height,
      ),
    );
    positionChild('back', Offset(0, (size.height - back.height) / 2));
    positionChild(
      'actions',
      Offset(size.width - actions.width, (size.height - actions.height) / 2),
    );
    positionChild(
      'title',
      Offset((size.width - title.width) / 2, (size.height - title.height) / 2),
    );
  }

  @override
  bool shouldRelayout(covariant _CenteredPlatformHeader oldDelegate) => false;
}

class PlatformSectionTitle extends StatelessWidget {
  const PlatformSectionTitle(this.title, {this.subtitle, super.key});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: MusicTypography.sectionTitleSize,
            fontWeight: MusicTypography.titleWeight,
            color: context.musicThemeTokens.textPrimary,
            letterSpacing: -.4,
          ),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              subtitle!,
              style: TextStyle(
                color: context.musicThemeTokens.textSecondary,
                fontSize: MusicTypography.captionSize,
              ),
            ),
          ),
      ],
    ),
  );
}

class PlatformFeedbackState extends StatelessWidget {
  const PlatformFeedbackState({
    this.loading = false,
    this.message = '',
    this.retry,
    super.key,
  });
  final bool loading;
  final String message;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) => PlatformPanel(
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const MestingLoadingIndicator(semanticLabel: '正在加载音乐内容')
          else ...[
            Icon(
              Icons.music_note_rounded,
              color: context.musicThemeTokens.textMuted,
              size: 30,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (retry != null)
              TextButton.icon(
                onPressed: retry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重新加载'),
              ),
          ],
        ],
      ),
    ),
  );
}
