import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/platform/sensitive_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.mesting.music/system_media');

  testWidgets('sensitive screen balances native privacy requests', (
    tester,
  ) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await tester.pumpWidget(
      const MaterialApp(home: SensitiveScreen(child: Text('账号安全'))),
    );
    await tester.pump();
    expect(calls, ['enterSecureScreen']);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(calls, ['enterSecureScreen', 'exitSecureScreen']);
  });
}
