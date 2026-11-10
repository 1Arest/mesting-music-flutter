import 'package:flutter/material.dart';
import 'beta_popup_menu_button.dart';

/// Compact anchored filter. The menu retains the existing glass, navigation
/// and selection behavior instead of expanding options into additional rows.
class MusicFilterDropdown extends StatelessWidget {
  const MusicFilterDropdown({
    required this.value,
    required this.options,
    required this.onChanged,
    this.label = '地区',
    super.key,
  });
  final String value, label;
  final List<String> options;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: IgnorePointer(
      ignoring: onChanged == null,
      child: Opacity(
        opacity: onChanged == null ? .5 : 1,
        child: BetaPopupMenuButton<String>(
          width: 128 + MediaQuery.textScalerOf(context).scale(24),
          tooltip: '$label：$value',
          onSelected: (next) {
            if (next != value) onChanged?.call(next);
          },
          itemBuilder: (_) => [
            for (final option in options)
              PopupMenuItem(
                value: option,
                child: Row(
                  children: [
                    Expanded(child: Text(option)),
                    if (option == value)
                      const Icon(Icons.check_rounded, size: 18),
                  ],
                ),
              ),
          ],
          icon: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.keyboard_arrow_down_rounded),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
