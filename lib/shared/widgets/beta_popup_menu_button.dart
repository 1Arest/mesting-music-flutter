import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/platform/distribution_channel.dart';
import 'beta_glass_controls.dart';
import 'beta_glass_popover.dart';

/// Imports may retain their menu data and callback contract; Beta supplies one
/// shared glass route, with disabled semantics and no default Material overlay.
class BetaPopupMenuButton<T> extends StatelessWidget {
  const BetaPopupMenuButton({
    required this.itemBuilder,
    required this.onSelected,
    this.tooltip = '更多操作',
    this.icon = const Icon(CupertinoIcons.ellipsis),
    super.key,
  });
  final PopupMenuItemBuilder<T> itemBuilder;
  final ValueChanged<T> onSelected;
  final String tooltip;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    if (!DistributionChannel.isBeta) {
      return PopupMenuButton<T>(
        tooltip: tooltip,
        icon: icon,
        itemBuilder: itemBuilder,
        onSelected: onSelected,
      );
    }
    return Builder(
      builder: (anchorContext) => BetaGlassButton(
        label: tooltip,
        width: 48,
        height: 48,
        onPressed: () async {
          final box = anchorContext.findRenderObject()! as RenderBox;
          final selected = await showBetaGlassPopover<T>(
            context: anchorContext,
            anchor: box.localToGlobal(Offset.zero) & box.size,
            builder: (menu) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in itemBuilder(anchorContext))
                  if (entry is PopupMenuItem<T>)
                    ListTile(
                      enabled: entry.enabled,
                      title: entry.child,
                      onTap: entry.enabled
                          ? () => Navigator.pop(menu, entry.value)
                          : null,
                    )
                  else if (entry is PopupMenuDivider)
                    const Divider(height: 10),
              ],
            ),
          );
          if (anchorContext.mounted && selected != null) onSelected(selected);
        },
        child: icon,
      ),
    );
  }
}
