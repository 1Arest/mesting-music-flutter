import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/core/audio/audio_output_controller.dart';
import 'package:mesting_music/shared/widgets/beta_glass_action.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(LiquidGlassWidgets.initialize);
  testWidgets(
    'output events follow headphone connection, rename and disconnect',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      MockStreamHandlerEventSink? sink;
      var chooses = 0;
      messenger.setMockMethodCallHandler(AudioOutputController.methods, (
        call,
      ) async {
        if (call.method == 'choose') {
          chooses++;
          return true;
        }
        return {'name': '本机扬声器', 'kind': 'speaker', 'available': true};
      });
      messenger.setMockStreamHandler(
        AudioOutputController.events,
        MockStreamHandler.inline(
          onListen: (_, events) {
            sink = events;
          },
        ),
      );
      final container = ProviderContainer();
      final subscription = container.listen(audioOutputProvider, (_, _) {});
      await tester.pump();
      await tester.pump();
      expect(container.read(audioOutputProvider).headphones, false);
      sink!.success({
        'name': 'WH-1000XM5',
        'kind': 'headphones',
        'available': true,
      });
      await tester.pump();
      expect(container.read(audioOutputProvider).name, 'WH-1000XM5');
      expect(container.read(audioOutputProvider).headphones, true);
      sink!.success({'name': '通勤耳机', 'kind': 'headphones', 'available': true});
      await tester.pump();
      expect(container.read(audioOutputProvider).name, '通勤耳机');
      await container.read(audioOutputProvider.notifier).choose();
      expect(chooses, 1);
      sink!.success({'name': '本机扬声器', 'kind': 'speaker', 'available': true});
      await tester.pump();
      expect(container.read(audioOutputProvider).headphones, false);
      subscription.close();
      container.dispose();
      await tester.pump();
      messenger.setMockMethodCallHandler(AudioOutputController.methods, null);
      messenger.setMockStreamHandler(AudioOutputController.events, null);
    },
  );
  testWidgets(
    'inset search lens keeps a 48dp target and does not grow while held',
    (tester) async {
      var submitted = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: BetaGlassAction(
                label: '搜索',
                icon: Icons.arrow_upward_rounded,
                compact: true,
                onPressed: () {
                  submitted++;
                },
              ),
            ),
          ),
        ),
      );
      final lens = find.byType(GlassButton);
      final before = tester.getRect(lens);
      expect(before.size, const Size(36, 36));
      final gesture = await tester.startGesture(before.center);
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.getRect(lens), before);
      await gesture.up();
      await tester.pump();
      expect(submitted, 1);
      // A tap outside the visible 36dp lens still hits its padded touch target.
      await tester.tapAt(before.topLeft - const Offset(3, 3));
      await tester.pump();
      expect(submitted, 2);
    },
  );
}
