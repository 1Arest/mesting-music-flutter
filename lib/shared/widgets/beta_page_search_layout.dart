import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../../features/experience/presentation/beta_bottom_bar.dart';
import 'beta_bottom_search.dart';
import '../../core/platform/distribution_channel.dart';
import 'beta_secondary_music_layout.dart';
import 'beta_glass_action.dart';
import 'beta_text_editing.dart';

/// All task-local search reuses the official bottom-bar field. Within the music
/// shell it registers with the existing bar; independently pushed/fullscreen
/// pages render the same package component locally. Repositories and filtering
/// stay with the page, so searching a local list never becomes an online query.
class BetaPageSearchLayout extends StatelessWidget {
  const BetaPageSearchLayout({
    required this.controller,
    required this.child,
    super.key,
  });
  final BetaPageSearchController controller;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (BetaBottomSearchScope.maybeOf(context) != null) {
      return BetaBottomSearchBinding(controller: controller, child: child);
    }
    if (DistributionChannel.isBeta) {
      return BetaSecondaryMusicLayout(search: controller, child: child);
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final scale = (MediaQuery.textScalerOf(context).scale(24) - 24).clamp(
          0.0,
          28.0,
        );
        final keyboard = MediaQuery.viewInsetsOf(context).bottom;
        final safe = MediaQuery.viewPaddingOf(context).bottom;
        return LayoutBuilder(
          builder: (context, constraints) {
            // A surrounding Scaffold may already have removed the keyboard's
            // height. Lift only the part not yet consumed by that ancestor.
            final consumed =
                (MediaQuery.sizeOf(context).height - constraints.maxHeight)
                    .clamp(0.0, keyboard);
            final lift = (keyboard - consumed).clamp(0.0, keyboard);
            return ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 100 + scale + safe),
                      child: child,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: lift,
                    child: Material(
                      type: MaterialType.transparency,
                      child: GlassTabBar.searchable(
                        tabs: const [
                          GlassTab(
                            label: '搜索',
                            icon: Icon(CupertinoIcons.search),
                          ),
                        ],
                        selectedIndex: 0,
                        onTabSelected: (_) => controller.focus.requestFocus(),
                        isSearchActive: true,
                        searchBarHeight: 50 + scale,
                        barHeight: 64 + scale,
                        horizontalPadding: 20,
                        verticalPadding: 16,
                        spacing: 8,
                        quality: GlassQuality.premium,
                        interactionBehavior: GlassInteractionBehavior.full,
                        whitenAtBottom: false,
                        settings: betaMusicPillGlass(context),
                        searchConfig: GlassSearchBarConfig(
                          controller: controller.text,
                          focusNode: controller.focus,
                          hintText: controller.hintText,
                          contextMenuBuilder: buildBetaEditingMenu,
                          selectionControls: betaTextSelectionControls,
                          cursorColor: betaEditingBlue(context),
                          textInputAction: TextInputAction.search,
                          autoFocusOnExpand: false,
                          showsCancelButton: true,
                          onSearchToggle: (active) {
                            controller.setActive(active);
                            if (!active) controller.clearResults();
                          },
                          onChanged: controller.changed,
                          onSubmitted: controller.submit,
                          trailingBuilder: (context) => BetaGlassAction(
                            key: const ValueKey('search-submit-action'),
                            label: '搜索',
                            compact: true,
                            icon: Icons.arrow_upward_rounded,
                            blue: true,
                            onPressed: () =>
                                controller.submit(controller.text.text),
                          ),
                          cancelButtonSemanticLabel: '关闭搜索',
                          clearButtonSemanticLabel: '清空搜索',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
