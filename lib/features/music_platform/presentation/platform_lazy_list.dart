import 'package:flutter/widgets.dart';

/// A single scrollable viewport with a finite header/footer and lazy data rows.
///
/// Keep pagination and filtering in the owning page. Passing already-created
/// data widgets in [header] or [footer] defeats this contract: only controls,
/// status messages and other bounded page chrome belong there. Returning the
/// ListView itself preserves its controller, PageStorage key and focus behavior.
ListView buildPlatformLazyList({
  required int itemCount,
  required IndexedWidgetBuilder itemBuilder,
  ChildIndexGetter? findItemIndex,
  List<Widget> header = const [],
  List<Widget> footer = const [],
  Key? key,
  ScrollController? controller,
  EdgeInsetsGeometry? padding,
  ScrollPhysics? physics,
}) {
  assert(itemCount >= 0);
  return ListView.builder(
    key: key,
    controller: controller,
    padding: padding,
    physics: physics,
    itemCount: header.length + itemCount + footer.length,
    // Keyed rows keep their element/reveal state when filtering or a refreshed
    // page changes their index. Owners can retain this lookup with their data.
    findChildIndexCallback: findItemIndex == null
        ? null
        : (key) {
            final row = findItemIndex(key);
            if (row != null) return header.length + row;
            for (var i = 0; i < header.length; i++) {
              if (header[i].key == key) return i;
            }
            for (var i = 0; i < footer.length; i++) {
              if (footer[i].key == key) return header.length + itemCount + i;
            }
            return null;
          },
    itemBuilder: (context, index) {
      if (index < header.length) return header[index];
      final row = index - header.length;
      if (row < itemCount) return itemBuilder(context, row);
      return footer[row - itemCount];
    },
  );
}
