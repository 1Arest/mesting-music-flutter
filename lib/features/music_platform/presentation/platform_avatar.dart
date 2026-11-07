import 'package:flutter/material.dart';
import '../../../shared/widgets/artwork_image.dart';

class PlatformAvatar extends StatelessWidget {
  const PlatformAvatar({required this.url, this.size = 44, super.key});
  final String url;
  final double size;
  @override
  Widget build(BuildContext context) => ClipOval(
    child: SizedBox.square(
      dimension: size,
      child: url.isEmpty
          ? ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.person_outline),
            )
          : ArtworkImage(uri: url, width: size, height: size),
    ),
  );
}
