import 'beta_control_scope.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'beta_glass_controls.dart';
import 'beta_glass_popover.dart';

/// Keep the existing Stable and Qishui controls. This pass unifies only the
/// NetEase/Kugou Apple surfaces, including shared settings reached from them.
bool _appleControls(BuildContext context) => BetaControlScope.appleOf(context);

/// An existing export preview can keep its layout and capture boundary while
/// its surrounding dialog adopts the same glass as the rest of these pages.
class BetaPanelDialog extends StatelessWidget {
  const BetaPanelDialog({
    required this.child,
    this.insetPadding = const EdgeInsets.symmetric(
      horizontal: 40,
      vertical: 24,
    ),
    super.key,
  });
  final Widget child;
  final EdgeInsets insetPadding;
  @override
  Widget build(BuildContext context) => _appleControls(context)
      ? Dialog(
          insetPadding: insetPadding,
          backgroundColor: Colors.transparent,
          child: BetaGlassMenuSurface(radius: 28, child: child),
        )
      : Dialog(insetPadding: insetPadding, child: child);
}

/// Adapts remaining imported actions without changing their business callback
/// or the Stable/Qishui presentation. Existing dedicated glass actions stay
/// with their original owner; this is the adapter for Material-only call sites.
class BetaActionButton extends StatelessWidget {
  const BetaActionButton({
    required this.onPressed,
    required this.child,
    this.style,
    this.red = false,
    super.key,
  }) : icon = null,
       outlined = false;
  const BetaActionButton.icon({
    required this.onPressed,
    required Widget label,
    required this.icon,
    this.style,
    this.red = false,
    super.key,
  }) : child = label,
       outlined = false;
  const BetaActionButton.outlinedIcon({
    required this.onPressed,
    required Widget label,
    required this.icon,
    this.style,
    this.red = false,
    super.key,
  }) : child = label,
       outlined = true;
  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final ButtonStyle? style;
  final bool outlined, red;

  @override
  Widget build(BuildContext context) {
    if (!_appleControls(context)) {
      if (icon == null) {
        return FilledButton(onPressed: onPressed, style: style, child: child);
      }
      return outlined
          ? OutlinedButton.icon(
              onPressed: onPressed,
              style: style,
              icon: icon!,
              label: child,
            )
          : FilledButton.icon(
              onPressed: onPressed,
              style: style,
              icon: icon!,
              label: child,
            );
    }
    return BetaGlassButton(
      height: MediaQuery.textScalerOf(context).scale(15) > 20 ? 76 : 52,
      blue: !outlined && !red,
      red: red,
      onPressed: onPressed,
      child: icon == null
          ? child
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon!,
                const SizedBox(width: 8),
                Flexible(child: child),
              ],
            ),
    );
  }
}

/// iOS checkbox affordance for ordered multi-selection, keeping the original
/// selection limits and account checks entirely in the caller.
class BetaCheckbox extends StatelessWidget {
  const BetaCheckbox({
    required this.value,
    required this.onChanged,
    this.visualDensity,
    super.key,
  });
  final bool value;
  final ValueChanged<bool?>? onChanged;
  final VisualDensity? visualDensity;
  @override
  Widget build(BuildContext context) => _appleControls(context)
      ? CupertinoCheckbox(value: value, onChanged: onChanged)
      : Checkbox(
          value: value,
          onChanged: onChanged,
          visualDensity: visualDensity,
        );
}

class BetaCheckboxTile extends StatelessWidget {
  const BetaCheckboxTile({
    required this.value,
    required this.onChanged,
    this.secondary,
    this.title,
    this.subtitle,
    super.key,
  });
  final bool value;
  final ValueChanged<bool?>? onChanged;
  final Widget? secondary, title, subtitle;
  @override
  Widget build(BuildContext context) {
    if (!_appleControls(context)) {
      return CheckboxListTile(
        value: value,
        onChanged: onChanged,
        secondary: secondary,
        title: title,
        subtitle: subtitle,
      );
    }
    return MergeSemantics(
      child: ListTile(
        leading: secondary,
        title: title,
        subtitle: subtitle,
        enabled: onChanged != null,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        trailing: CupertinoCheckbox(value: value, onChanged: onChanged),
      ),
    );
  }
}

/// Compact single-choice filters use the same optical and press-cancel owner
/// as the app's other glass actions, rather than Android's Material chip.
class BetaSelectionChip extends StatelessWidget {
  const BetaSelectionChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.avatar,
    this.labelStyle,
    this.padding,
    this.labelPadding,
    this.avatarBoxConstraints,
    this.showCheckmark,
    super.key,
  });
  final Widget label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final Widget? avatar;
  final TextStyle? labelStyle;
  final EdgeInsetsGeometry? padding, labelPadding;
  final BoxConstraints? avatarBoxConstraints;
  final bool? showCheckmark;

  @override
  Widget build(BuildContext context) {
    if (!_appleControls(context)) {
      return ChoiceChip(
        label: label,
        selected: selected,
        onSelected: onSelected,
        avatar: avatar,
        labelStyle: labelStyle,
        padding: padding,
        labelPadding: labelPadding,
        avatarBoxConstraints: avatarBoxConstraints,
        showCheckmark: showCheckmark,
      );
    }
    return Semantics(
      selected: selected,
      child: BetaGlassButton(
        height: 44,
        horizontalPadding: 14,
        accent: selected,
        onPressed: onSelected == null ? null : () => onSelected!(!selected),
        child: DefaultTextStyle.merge(
          style: labelStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (avatar != null) ...[
                avatar!,
                const SizedBox(width: 6),
              ] else if (showCheckmark != false) ...[
                Opacity(
                  opacity: selected ? 1 : 0,
                  child: const Icon(CupertinoIcons.check_mark, size: 15),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(child: label),
            ],
          ),
        ),
      ),
    );
  }
}

/// Platform-independent Apple switch row. Callers still own validation,
/// persistence and disabled state; tapping the label and switch agree.
class BetaSwitchTile extends StatelessWidget {
  const BetaSwitchTile({
    required this.value,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.contentPadding,
    super.key,
  });
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? title, subtitle;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    if (!_appleControls(context)) {
      return SwitchListTile.adaptive(
        value: value,
        onChanged: onChanged,
        title: title,
        subtitle: subtitle,
        contentPadding: contentPadding,
      );
    }
    return MergeSemantics(
      child: ListTile(
        contentPadding: contentPadding,
        title: title,
        subtitle: subtitle,
        enabled: onChanged != null,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        trailing: CupertinoSwitch(value: value, onChanged: onChanged),
      ),
    );
  }
}
