import 'package:flutter/cupertino.dart';
import '../../../shared/widgets/beta_glass_menu_item.dart';
import 'player_glass_button.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/beta_glass_popover.dart';
import '../../themes/beta_appearance.dart';
import '../../themes/music_typography.dart';

class PlayerMenuAction {
  const PlayerMenuAction(
    this.value,
    this.label,
    this.icon, {
    this.selected = false,
  });
  final String value, label;
  final IconData icon;
  final bool selected;
}

/// Presentation-only disclosure; the caller still owns persistence and actions.
class PlayerMenuDisclosure {
  const PlayerMenuDisclosure({
    required this.title,
    required this.current,
    required this.actions,
  });
  final String title, current;
  final List<PlayerMenuAction> actions;
}

/// Geometry, motion and glass share one owner with the capsule and editing
/// toolbar. Business actions run only after the surface has finished closing.
class PlayerMoreMenu extends StatefulWidget {
  const PlayerMoreMenu({
    required this.groups,
    required this.onSelected,
    this.trigger,
    this.tooltip = '更多操作',
    this.menuWidth = 280,
    this.disclosure,
    super.key,
  });
  final List<List<PlayerMenuAction>> groups;
  final ValueChanged<String> onSelected;
  final Widget? trigger;
  final String tooltip;
  final double menuWidth;
  final PlayerMenuDisclosure? disclosure;
  @override
  State<PlayerMoreMenu> createState() => PlayerMoreMenuState();
}

class PlayerMoreMenuState extends State<PlayerMoreMenu> {
  final _anchor = GlobalKey();
  bool _opening = false;

  /// The trigger and fixed interaction sampler use the same guarded action.
  Future<void> openMenu({
    ValueChanged<ModalRoute<dynamic>>? onRouteCreated,
  }) async {
    if (_opening) return;
    final box = _anchor.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    _opening = true;
    try {
      final theme = Theme.of(context);
      final ink = theme.brightness == Brightness.dark
          ? Colors.white
          : const Color(0xFF202024);
      var expanded = false;
      final value = await showBetaGlassPopover<String>(
        context: context,
        anchor: box.localToGlobal(Offset.zero) & box.size,
        width: widget.menuWidth,
        label: '关闭更多菜单',
        fromInnerEdge: true,
        motion: BetaMenuMotion.player,
        onRouteCreated: onRouteCreated,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (
                  var group = 0;
                  group <
                      widget.groups.length +
                          (widget.disclosure == null ? 0 : 1);
                  group++
                ) ...[
                  if (group > 0)
                    Divider(
                      height: 13,
                      thickness: .5,
                      color: theme.dividerColor.withValues(alpha: .3),
                      indent: 16,
                      endIndent: 16,
                    ),
                  if (group == widget.groups.length) ...[
                    Semantics(
                      button: true,
                      expanded: expanded,
                      child: BetaGlassMenuItem(
                        key: const ValueKey('player-style-disclosure'),
                        onTap: () => update(() => expanded = !expanded),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                CupertinoIcons.photo_on_rectangle,
                                size: 20,
                                color: ink,
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Text(
                                  widget.disclosure!.title,
                                  style: TextStyle(
                                    color: ink,
                                    fontSize: MusicTypography.subheadlineSize,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  widget.disclosure!.current,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: ink.withValues(alpha: .65),
                                    fontSize: MusicTypography.captionSize,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                expanded
                                    ? CupertinoIcons.chevron_up
                                    : CupertinoIcons.chevron_down,
                                size: 13,
                                color: ink,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  for (final action
                      in group < widget.groups.length
                          ? widget.groups[group]
                          : expanded
                          ? widget.disclosure!.actions
                          : <PlayerMenuAction>[])
                    Semantics(
                      selected: action.selected,
                      button: true,
                      child: BetaGlassMenuItem(
                        onTap: () =>
                            Navigator.of(dialogContext).pop(action.value),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 46),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 11,
                            ),
                            child: Row(
                              children: [
                                Icon(action.icon, color: ink, size: 20),
                                const SizedBox(width: 13),
                                Expanded(
                                  child: Text(
                                    action.label,
                                    style: TextStyle(
                                      color: ink,
                                      fontSize: MusicTypography.subheadlineSize,
                                      fontWeight: MusicTypography.bodyWeight,
                                    ),
                                  ),
                                ),
                                if (action.selected)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Icon(
                                      CupertinoIcons.check_mark,
                                      size: 18,
                                      color: BetaAppearance.accent(
                                        theme.brightness,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      );
      if (mounted && value != null) widget.onSelected(value);
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.trigger != null
      ? Tooltip(
          message: widget.tooltip,
          child: CupertinoButton(
            key: _anchor,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: const Size(44, 44),
            onPressed: openMenu,
            child: DefaultTextStyle(
              style: Theme.of(context).textTheme.titleMedium!,
              child: widget.trigger!,
            ),
          ),
        )
      : PlayerGlassButton(
          key: _anchor,
          label: widget.tooltip,
          onPressed: openMenu,
          icon: CupertinoIcons.ellipsis,
        );
}
