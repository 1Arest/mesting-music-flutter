import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'beta_glass_controls.dart';
import 'beta_glass_popover.dart';

/// Form validation stays with the owning form; presentation uses the shared
/// glass menu and never starts a second Material dropdown route.
class BetaChoiceField<T> extends FormField<T> {
  BetaChoiceField({
    super.key,
    super.initialValue,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
    InputDecoration decoration = const InputDecoration(),
    bool isExpanded = true,
    super.validator,
  }) : super(
         enabled: onChanged != null,
         builder: (field) {
           final selected = items
               .where((item) => item.value == field.value)
               .firstOrNull;
           return Column(
             crossAxisAlignment: CrossAxisAlignment.stretch,
             children: [
               if (decoration.labelText != null)
                 Padding(
                   padding: const EdgeInsets.only(left: 12, bottom: 7),
                   child: Text(
                     decoration.labelText!,
                     style: Theme.of(field.context).textTheme.bodySmall,
                   ),
                 ),
               Builder(
                 builder: (anchorContext) => BetaGlassButton(
                   onPressed: onChanged == null
                       ? null
                       : () async {
                           final box =
                               anchorContext.findRenderObject()! as RenderBox;
                           final result = await showBetaGlassPopover<T>(
                             context: anchorContext,
                             anchor: box.localToGlobal(Offset.zero) & box.size,
                             width: box.size.width.clamp(230, 420),
                             builder: (menu) => ConstrainedBox(
                               constraints: BoxConstraints(
                                 maxHeight: MediaQuery.sizeOf(menu).height * .6,
                               ),
                               child: SingleChildScrollView(
                                 child: Column(
                                   mainAxisSize: MainAxisSize.min,
                                   children: [
                                     for (final item in items)
                                       ListTile(
                                         enabled: item.enabled,
                                         title: item.child,
                                         trailing: item.value == field.value
                                             ? const Icon(
                                                 CupertinoIcons.check_mark,
                                                 size: 18,
                                               )
                                             : null,
                                         onTap: item.enabled
                                             ? () => Navigator.pop(
                                                 menu,
                                                 item.value,
                                               )
                                             : null,
                                       ),
                                   ],
                                 ),
                               ),
                             ),
                           );
                           if (!field.mounted ||
                               !field.widget.enabled ||
                               result == null) {
                             return;
                           }
                           field.didChange(result);
                           onChanged(result);
                         },
                   child: Row(
                     children: [
                       Expanded(
                         child:
                             selected?.child ??
                             Text(decoration.hintText ?? '请选择'),
                       ),
                       const SizedBox(width: 10),
                       const Icon(CupertinoIcons.chevron_down, size: 15),
                     ],
                   ),
                 ),
               ),
               if (field.errorText != null)
                 Padding(
                   padding: const EdgeInsets.only(top: 6, left: 12),
                   child: Text(
                     field.errorText!,
                     style: TextStyle(
                       color: Theme.of(field.context).colorScheme.error,
                     ),
                   ),
                 ),
             ],
           );
         },
       );
  @override
  FormFieldState<T> createState() => _BetaChoiceState<T>();
}

class _BetaChoiceState<T> extends FormFieldState<T> {
  @override
  void didUpdateWidget(covariant BetaChoiceField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A refreshed settings model can change while its form stays mounted.
    if (oldWidget.initialValue != widget.initialValue) {
      setValue(widget.initialValue);
    }
  }
}
