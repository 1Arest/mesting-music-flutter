import 'package:flutter/material.dart';

/// A terminal state, not a loading guess. Owners render this only when their
/// authoritative source has no more data; scroll padding separately clears chrome.
class MusicListEnd extends StatelessWidget {
  const MusicListEnd({this.label = '已加载全部内容', super.key});
  final String label;
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}
