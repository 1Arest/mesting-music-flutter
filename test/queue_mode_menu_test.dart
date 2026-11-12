import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:mesting_music/core/platform/distribution_channel.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/audio/playback_mode.dart';
import 'package:mesting_music/features/queue/presentation/playback_mode_button.dart';

const capture = bool.fromEnvironment('CAPTURE_QUEUE_MODE');
const output = String.fromEnvironment('QUEUE_MODE_CAPTURE_PATH');

void main() {
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (!capture) return;
    await (FontLoader('Roboto')..addFont(
          File(
            'C:/Windows/Fonts/msyh.ttc',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
        ))
        .load();
  });
  for (final dark in [false, true]) {
    testWidgets(
      'single four-mode menu fits narrow large-text queue dark=$dark',
      (tester) async {
        final originalShadows = debugDisableShadows;
        if (capture) debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = originalShadows);
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var mode = PlaybackMode.sequential;
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('queue-mode-proof'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark ? ThemeData.dark() : ThemeData.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(1.8)),
                child: child!,
              ),
              home: Scaffold(
                body: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: StatefulBuilder(
                      builder: (context, update) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            '待播列表',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  '12 首待播放',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              PlaybackModeButton(
                                mode: mode,
                                immersive: dark,
                                onSelected: (value) =>
                                    update(() => mode = value),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('queue-playback-mode')));
        await tester.pumpAndSettle();
        for (final choice in PlaybackMode.values) {
          expect(
            find.byKey(ValueKey('queue-mode-${choice.name}')),
            findsOneWidget,
          );
        }
        expect(
          find.byIcon(
            DistributionChannel.isBeta
                ? CupertinoIcons.check_mark
                : Icons.check_rounded,
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        if (capture && dark && output.isNotEmpty) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('queue-mode-proof')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            try {
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(output).writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
        await tester.tap(find.byKey(const ValueKey('queue-mode-random')));
        await tester.pumpAndSettle();
        expect(mode, PlaybackMode.random);
        expect(find.text('随机播放'), findsOneWidget);
        expect(find.byType(PopupMenuItem<PlaybackMode>), findsNothing);
        debugDisableShadows = originalShadows;
        expect(tester.takeException(), isNull);
      },
    );
  }
}
