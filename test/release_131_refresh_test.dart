import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/features/experience/presentation/editorial_widgets.dart';
import 'package:mesting_music/features/music_platform/presentation/platform_design.dart';
import 'package:mesting_music/shared/widgets/beta_glass_controls.dart';
import 'package:mesting_music/shared/widgets/music_refresh_indicator.dart';

int activeAppleIndicators(WidgetTester tester) => find
    .byType(CupertinoActivityIndicator)
    .evaluate()
    .where((e) => TickerMode.valuesOf(e).enabled)
    .length;

void main() {
  setUpAll(() => LiquidGlassWidgets.initialize());
  for (final framed in [false, true]) {
    testWidgets(
      'refresh has one Apple indicator and retains usable rows framed=$framed',
      (tester) async {
        final done = Completer<void>();
        var calls = 0, busy = false;
        late StateSetter update;
        final body = StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return EditorialScroll(
              onRefresh: () async {
                calls++;
                update(() => busy = true);
                await done.future;
                if (context.mounted) update(() => busy = false);
              },
              children: [
                const Text('cached rows'),
                if (busy) const Center(child: BetaActivityIndicator()),
                const SizedBox(height: 1200),
              ],
            );
          },
        );
        await tester.pumpWidget(
          MaterialApp(
            home: framed
                ? PlatformPageFrame(
                    title: 'Messages',
                    musicChrome: false,
                    child: body,
                  )
                : Scaffold(body: body),
          ),
        );
        await tester.pump();
        await tester.drag(find.byType(ListView), const Offset(0, 750));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(calls, 1);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(activeAppleIndicators(tester), 1);
        expect(find.text('cached rows').hitTestable(), findsOneWidget);
        expect(find.byType(MusicRefreshIndicator), findsOneWidget);
        await tester.drag(find.byType(ListView), const Offset(0, 250));
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          calls,
          1,
          reason: 'A second gesture must not create another refresh.',
        );
        done.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump();
        expect(activeAppleIndicators(tester), 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
