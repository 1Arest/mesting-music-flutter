import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/network/music_network_diagnostics.dart';
import 'package:mesting_music/features/settings/presentation/music_network_diagnostics_page.dart';

import 'support/release_152_qa.dart';

/// These tests exercise the existing in-memory export and diagnostic screen.
/// They never open an account, contact a platform or submit a reward request.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initialize151QA);
  final diagnostics = MusicNetworkDiagnostics.shared;
  const labels = {
    MusicNetworkOperation.rewardBalance: '免费听余额',
    MusicNetworkOperation.rewardProgress: '领取进度',
    MusicNetworkOperation.rewardQualification: '领取资格',
    MusicNetworkOperation.rewardClaim: '奖励领取',
    MusicNetworkOperation.rewardSignIn: '每日签到',
  };
  setUp(diagnostics.clear);
  tearDown(diagnostics.clear);

  test('reward stages retain the schema-2 export contract', () {
    // Keep one old operation beside all new stages: old readers still receive
    // the same envelope and legacy operation names rather than enum indices.
    for (final operation in [MusicNetworkOperation.read, ...labels.keys]) {
      diagnostics.record(
        platform: 'netease',
        operation: operation,
        outcome: MusicNetworkOutcome.business,
        status: 500,
        phase: MusicDiagnosticPhase.responseValidate,
      );
    }
    final report = jsonDecode(diagnostics.export()) as Map<String, dynamic>;
    expect(report['schema'], 2);
    expect(report['memoryOnly'], isTrue);
    final events = (report['events'] as List).cast<Map<String, dynamic>>();
    expect(events.map((row) => row['operation']), [
      'read',
      'rewardBalance',
      'rewardProgress',
      'rewardQualification',
      'rewardClaim',
      'rewardSignIn',
    ]);
    for (final row in events) {
      expect(row['outcome'], 'business');
      expect(row['status'], 500);
      expect(row['phase'], 'responseValidate');
      expect(row.keys.toSet(), {
        'at',
        'platform',
        'operation',
        'outcome',
        'elapsedMs',
        'attempt',
        'transport',
        'status',
        'phase',
      });
    }
  });

  test(
    'reward diagnostics stay bounded and reject free-form identity fields',
    () {
      for (var index = 0; index < 100; index++) {
        diagnostics.record(
          platform: 'Cookie=MUSIC_U=private-fixture;userId=private-account',
          operation: labels.keys.elementAt(index % labels.length),
          outcome: MusicNetworkOutcome.business,
          status: index,
          transport: 'https://private-fixture/reqParam?token=private-token',
        );
      }
      final report = jsonDecode(diagnostics.export()) as Map<String, dynamic>;
      final events = (report['events'] as List).cast<Map<String, dynamic>>();
      expect(events, hasLength(80));
      expect(events.first['status'], 20);
      expect(events.last['status'], 99);
      expect(events.every((row) => row['platform'] == 'other'), isTrue);
      expect(events.every((row) => row['transport'] == 'other'), isTrue);
      final exported = diagnostics.export();
      for (final secret in [
        'private-',
        'MUSIC_U',
        'userId',
        'reqParam',
        'token=',
      ]) {
        expect(exported, isNot(contains(secret)));
      }
    },
  );

  for (final entry in labels.entries) {
    testWidgets('diagnostic screen identifies ${entry.key.name}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 844);
      addTearDown(tester.view.reset);
      diagnostics.record(
        platform: 'netease',
        operation: entry.key,
        outcome: MusicNetworkOutcome.business,
        status: 500,
        phase: MusicDiagnosticPhase.responseValidate,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme152(false),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: const MusicNetworkDiagnosticsPage(),
        ),
      );
      await tester.pump();
      expect(find.textContaining('netease · ${entry.value}\n'), findsOneWidget);
      expect(find.textContaining('平台未接受'), findsOneWidget);
      expect(find.textContaining('500'), findsOneWidget);
      expect(find.textContaining('平台资料校验'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('copying diagnostics preserves the failed reward stage', (
    tester,
  ) async {
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    diagnostics.record(
      platform: 'netease',
      operation: MusicNetworkOperation.rewardQualification,
      outcome: MusicNetworkOutcome.business,
      status: 500,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme152(false),
        home: const MusicNetworkDiagnosticsPage(),
      ),
    );
    await tester.tap(find.text('复制诊断记录'));
    await tester.pump();
    expect(copied, isNotNull);
    final report = jsonDecode(copied!) as Map<String, dynamic>;
    expect(report['schema'], 2);
    expect((report['events'] as List).single, {
      ...diagnostics.rows.single,
      'operation': 'rewardQualification',
      'status': 500,
    });
    await tester.pumpWidget(const SizedBox());
  });
}
