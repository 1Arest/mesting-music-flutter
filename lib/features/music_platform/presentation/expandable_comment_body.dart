import 'package:flutter/material.dart';

/// The comment list owns vertical gestures. SelectionArea keeps long-press
/// copying without SelectableText's independent, internally scrollable editor.
/// Expansion is local to this keyed comment and never changes repository data.
class ExpandableCommentBody extends StatefulWidget {
  const ExpandableCommentBody({
    required this.text,
    required this.style,
    super.key,
  });
  final String text;
  final TextStyle style;

  @override
  State<ExpandableCommentBody> createState() => _ExpandableCommentBodyState();
}

class _ExpandableCommentBodyState extends State<ExpandableCommentBody> {
  static const _collapsedLines = 6;
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant ExpandableCommentBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _expanded = false;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      // Measure the actual font scaling and available row width. A character
      // threshold would hide short wide text or truncate large accessibility text.
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: _collapsedLines,
      )..layout(maxWidth: bounds.maxWidth);
      final canExpand = painter.didExceedMaxLines;
      painter.dispose();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectionArea(
            child: Text(
              widget.text,
              style: widget.style,
              maxLines: _expanded ? null : _collapsedLines,
              overflow: _expanded ? TextOverflow.clip : TextOverflow.ellipsis,
            ),
          ),
          if (canExpand)
            TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? '收起' : '展开'),
            ),
        ],
      );
    },
  );
}
