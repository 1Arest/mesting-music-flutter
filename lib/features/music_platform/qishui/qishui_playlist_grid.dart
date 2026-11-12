import 'package:flutter/material.dart';
import '../../../shared/widgets/artwork_image.dart';
import 'qishui_models.dart';

/// Cell height follows the rendered cover width and two scaled text lines.
/// A fixed 245dp row clips tablet covers and wastes narrow-screen space.
class QishuiPlaylistGrid extends StatelessWidget {
  const QishuiPlaylistGrid({
    required this.lists,
    required this.open,
    super.key,
  });
  final List<QishuiPlaylist> lists;
  final void Function(QishuiPlaylist list) open;
  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    sliver: SliverLayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.crossAxisExtent / 240).ceil().clamp(1, 6);
        final width =
            (constraints.crossAxisExtent - 16 * (columns - 1)) / columns;
        final style = Theme.of(context).textTheme.titleSmall;
        final textHeight =
            MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 14) *
            (style?.height ?? 1.5);
        return SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: width + 12 + textHeight * 2 + 8,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: lists.length,
          itemBuilder: (context, i) {
            final list = lists[i];
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => open(list),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: ArtworkImage(uri: list.cover, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    list.name,
                    style: style,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          },
        );
      },
    ),
  );
}
