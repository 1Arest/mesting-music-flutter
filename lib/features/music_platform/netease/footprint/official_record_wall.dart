import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../shared/widgets/artwork_image.dart';
import 'official_report_extras.dart';

/// The official Listen Home collage repeats short lists before interleaving
/// covers by column. In the two/four-cover case its visible four columns use
/// the first four buckets of a five-way interleave.
List<List<String>> officialRecordWallColumns(List<String> covers) {
  final valid = covers.where((url) => url.isNotEmpty).take(20).toList();
  if (valid.isEmpty) return const [];
  final count = valid.length;
  final sparse = count == 2 || count == 4;
  final length = sparse
      ? 30
      : count == 20
      ? 20
      : 24;
  final repeated = List.generate(length, (index) => valid[index % count]);
  if (count == 5) {
    repeated.setRange(20, 24, repeated.take(4).toList().reversed);
  } else if (count == 10) {
    repeated.setRange(20, 24, repeated.sublist(2, 6));
  }
  final stride = sparse ? 5 : 4;
  return List.generate(
    4,
    (column) => [
      for (var i = column; i < repeated.length; i += stride) repeated[i],
    ],
  );
}

/// The report animates the cover layer behind a fixed mask. Exports reuse the
/// same cover order and layout at a deterministic frame and their own aspect.
class OfficialRecordWall extends StatefulWidget {
  const OfficialRecordWall({
    required this.data,
    required this.period,
    this.wallpaper = false,
    this.animate = true,
    super.key,
  });
  final OfficialReportExtras data;
  final String period;
  final bool wallpaper, animate;

  @override
  State<OfficialRecordWall> createState() => _OfficialRecordWallState();
}

class _OfficialRecordWallState extends State<OfficialRecordWall>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  );
  ScrollPosition? _scroll;
  bool _foreground = true;
  bool _canAnimate = false;
  bool _visibilityPending = false;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _scroll) {
      _scroll?.removeListener(_checkAfterLayout);
      _scroll = position;
      _scroll?.addListener(_checkAfterLayout);
    }
    _canAnimate =
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context) &&
        (ModalRoute.isCurrentOf(context) ?? true);
    _checkAfterLayout();
  }

  @override
  void didUpdateWidget(covariant OfficialRecordWall oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkAfterLayout();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _motion.stop();
    _checkAfterLayout();
  }

  @override
  void didChangeMetrics() => _checkAfterLayout();

  void _checkAfterLayout() {
    if (_visibilityPending) return;
    _visibilityPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityPending = false;
      if (!mounted) return;
      final animate =
          widget.animate &&
          _canAnimate &&
          _foreground &&
          widget.data.covers.isNotEmpty &&
          _isVisible();
      if (animate && !_motion.isAnimating) _motion.repeat();
      if (!animate && _motion.isAnimating) _motion.stop();
    });
  }

  bool _isVisible() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return true;
    final viewportRect = MatrixUtils.transformRect(
      viewport.getTransformTo(null),
      viewport.paintBounds,
    );
    return (box.localToGlobal(Offset.zero) & box.size).overlaps(viewportRect);
  }

  @override
  void dispose() {
    _scroll?.removeListener(_checkAfterLayout);
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final columns = officialRecordWallColumns(widget.data.covers);
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return Semantics(
      container: true,
      child: AspectRatio(
        key: const ValueKey('official-record-wall'),
        aspectRatio: widget.wallpaper ? 9 / 16 : 4 / 5,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.animate ? 16 : 0),
          child: LayoutBuilder(
            builder: (context, bounds) {
              final rows = columns.isEmpty ? 1 : columns.first.length;
              final rowHeight = bounds.maxHeight / 5;
              return Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Color(0xFF15171D)),
                  if (columns.isNotEmpty)
                    ExcludeSemantics(
                      child: AnimatedBuilder(
                        animation: _motion,
                        child: RepaintBoundary(
                          child: Row(
                            children: [
                              for (final column in columns)
                                Expanded(
                                  child: Column(
                                    children: [
                                      for (final url in [...column, ...column])
                                        SizedBox(
                                          height: rowHeight,
                                          width: double.infinity,
                                          child: ArtworkImage(
                                            uri: url,
                                            fit: BoxFit.cover,
                                            decodeWidth: 240,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        builder: (context, child) => OverflowBox(
                          alignment: Alignment.topCenter,
                          minHeight: rows * rowHeight * 2,
                          maxHeight: rows * rowHeight * 2,
                          child: Transform.translate(
                            offset: Offset(
                              0,
                              -_motion.value * rows * rowHeight,
                            ),
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xE8161720),
                            Color(0x36161720),
                            Color(0x16161720),
                            Color(0xEB161720),
                          ],
                          stops: [0, .32, .58, 1],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(scale > 1.45 ? 12 : 18),
                    child: DefaultTextStyle.merge(
                      style: const TextStyle(color: Color(0xFFF9F9FC)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            '云村听歌足迹',
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            widget.period,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                          const Spacer(),
                          if (widget.data.songCount case final count?)
                            Text(
                              '听过 $count 首歌',
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          if (!widget.animate)
                            const Text(
                              'Mesting Music',
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white70,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
