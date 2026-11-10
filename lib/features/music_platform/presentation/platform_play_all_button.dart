import 'package:flutter/material.dart';
import '../../../shared/widgets/collection_play_all_button.dart';

/// Legacy feed callers retain their loading contract and stable button key.
class PlatformPlayAllButton extends StatelessWidget {
  const PlatformPlayAllButton({
    required this.onPressed,
    this.loading = false,
    this.total,
    super.key,
  });
  final VoidCallback? onPressed;
  final bool loading;
  final int? total;
  @override
  Widget build(BuildContext context) => CollectionPlayAllButton(
    key: const ValueKey('platform-play-all'),
    onPressed: onPressed,
    loading: loading,
    total: total,
  );
}
