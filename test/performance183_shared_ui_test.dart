import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/shared/widgets/artwork_reveal_boundary.dart';

/// A real viewport registration without HTTP/decoder timing. The callback
/// counts geometry discovery, rather than treating host pump time as FPS.
class _ArtworkProbe183 extends StatefulWidget {
  const _ArtworkProbe183({required this.reads, required this.ready, super.key});
  final List<int> reads;
  final ValueNotifier<bool> ready;
  @override
  State<_ArtworkProbe183> createState() => _ArtworkProbe183State();
}

class _ArtworkProbe183State extends State<_ArtworkProbe183> {
  ArtworkRevealEntry? entry;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    entry ??= ArtworkRevealBoundary.of(context)!.register(() {
      widget.reads[0]++;
      final box = context.findRenderObject();
      return mounted && box is RenderBox ? box : null;
    })..identity = '${widget.key}';
    entry!.update(ready: widget.ready.value, enabled: true);
  }

  @override
  void initState() {
    super.initState();
    widget.ready.addListener(_changed);
  }

  void _changed() => entry?.update(ready: widget.ready.value, enabled: true);

  @override
  void dispose() {
    widget.ready.removeListener(_changed);
    entry?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: 60, child: ColoredBox(color: Colors.red));
}

void main() {
  testWidgets('artwork paint reads each registered row once, after movement', (
    tester,
  ) async {
    final reads = [0];
    final ready = ValueNotifier(true);
    final scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 300,
          child: ArtworkRevealBoundary(
            child: ListView(
              controller: scroll,
              children: [
                _ArtworkProbe183(
                  key: const ValueKey('first'),
                  reads: reads,
                  ready: ready,
                ),
                const SizedBox(height: 200),
                _ArtworkProbe183(
                  key: const ValueKey('last'),
                  reads: reads,
                  ready: ready,
                ),
                const SizedBox(height: 1000),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    reads[0] = 0;
    scroll.jumpTo(40);
    await tester.pump();
    expect(
      reads[0],
      2,
      reason:
          'Each paint must reuse its row geometry for the frontier, '
          'visibility and commit passes, without caching across frames.',
    );
    ready.value = false;
    await tester.pump();
    ready.value = true;
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
    ready.dispose();
  });
}
