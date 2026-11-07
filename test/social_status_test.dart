import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/auth/domain/auth_models.dart';
import 'package:mesting_music/features/profile/presentation/social_status_sheet.dart';
import 'package:mesting_music/features/social/data/local_preview_social_repository.dart';
import 'package:mesting_music/features/social/domain/social_models.dart';
import 'package:mesting_music/features/social/presentation/social_widgets.dart';
import 'package:mesting_music/features/social/social_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('social status JSON supports profile and action payloads', () {
    const status = SocialStatus(emoji: '🌷', text: '等春天');

    expect(SocialStatus.fromJson(status.toJson()), status);
    expect(
      SocialStatus.fromJson({
        'status_emoji': '🎧',
        'status_text': '找人一起听',
      }).label,
      '🎧 找人一起听',
    );
  });

  test('local preview status can be updated and cleared', () async {
    const user = AuthUser(uid: 'me', nickname: 'Mesting');
    final repository = LocalPreviewSocialRepository(userProvider: () => user);

    const status = SocialStatus(emoji: '✨', text: '今天只听慢歌');
    expect(await repository.setStatus(status), status);
    expect(await repository.getStatus(), status);

    expect(
      await repository.setStatus(const SocialStatus.empty()),
      const SocialStatus.empty(),
    );
  });

  test('local preview status is restored for the same account', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    const user = AuthUser(uid: 'status-owner', nickname: 'Mesting');
    final first = LocalPreviewSocialRepository(
      userProvider: () => user,
      preferences: preferences,
    );
    await first.setStatus(const SocialStatus(emoji: '🌙', text: '听会儿歌'));

    final restored = LocalPreviewSocialRepository(
      userProvider: () => user,
      preferences: preferences,
    );
    expect(
      await restored.getStatus(),
      const SocialStatus(emoji: '🌙', text: '听会儿歌'),
    );
  });

  test(
    'last known status snapshot is available before remote refresh',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      const status = SocialStatus(emoji: '🌷', text: '等春天');

      await rememberSocialStatusSnapshot(
        preferences,
        'status-snapshot',
        status,
      );

      expect(
        cachedSocialStatusSnapshot(preferences, 'status-snapshot'),
        status,
      );
      expect(
        preferences.getString(socialStatusSnapshotKey('status-snapshot')),
        isNotEmpty,
      );
    },
  );

  testWidgets('preset status is selected from the custom bottom sheet', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _StatusHarness()));

    await tester.tap(find.text('打开状态'));
    await tester.pumpAndSettle();
    expect(find.text('选择状态'), findsOneWidget);
    expect(find.text('自定义状态'), findsOneWidget);
    expect(find.text('等春天'), findsOneWidget);

    await tester.tap(find.text('等春天'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('social-status-done')));
    await tester.pumpAndSettle();

    expect(find.text('🌷 等春天'), findsOneWidget);
  });

  testWidgets('custom status supports emoji and twelve-character text', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _StatusHarness()));

    await tester.tap(find.text('打开状态'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义状态'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('custom-social-status-field')),
      '今天只听慢歌',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('custom-social-status-save')));
    await tester.pumpAndSettle();

    expect(find.text('✨ 今天只听慢歌'), findsOneWidget);
    expect(find.text('选择状态'), findsNothing);
  });

  testWidgets('status sheet is presented above shell overlays', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _OverlayHarness()));

    await tester.tap(find.text('打开状态'));
    await tester.pumpAndSettle();

    expect(find.text('选择状态'), findsOneWidget);
    expect(find.text('胶囊播放器遮罩'), findsOneWidget);

    await tester.tap(find.text('等春天'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('social-status-done')));
    await tester.pumpAndSettle();

    expect(find.text('🌷 等春天'), findsOneWidget);
  });

  testWidgets('last preset remains reachable on a short screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(570, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: _StatusHarness()));

    await tester.tap(find.text('打开状态'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('爱学习'),
      180,
      scrollable: find.byType(Scrollable).last,
    );

    expect(find.text('爱学习'), findsOneWidget);
  });

  testWidgets('status sheets round only their top corners', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _StatusHarness()));

    await tester.tap(find.text('打开状态'));
    await tester.pumpAndSettle();

    const expectedRadius = BorderRadius.only(
      topLeft: Radius.circular(30),
      topRight: Radius.circular(30),
    );
    final picker = tester.widget<SocialGlass>(
      find.byKey(const ValueKey('social-status-picker-surface')),
    );
    expect(picker.borderRadius, expectedRadius);

    await tester.tap(find.text('自定义状态'));
    await tester.pumpAndSettle();

    final editor = tester.widget<SocialGlass>(
      find.byKey(const ValueKey('custom-social-status-surface')),
    );
    expect(editor.borderRadius, expectedRadius);
  });
}

class _StatusHarness extends StatefulWidget {
  const _StatusHarness();

  @override
  State<_StatusHarness> createState() => _StatusHarnessState();
}

class _StatusHarnessState extends State<_StatusHarness> {
  SocialStatus _status = const SocialStatus.empty();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_status.isEmpty ? '未设置' : _status.label),
            FilledButton(
              onPressed: () async {
                final selected = await showSocialStatusPicker(
                  context,
                  initialStatus: _status,
                );
                if (selected != null && mounted) {
                  setState(() => _status = selected);
                }
              },
              child: const Text('打开状态'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverlayHarness extends StatefulWidget {
  const _OverlayHarness();

  @override
  State<_OverlayHarness> createState() => _OverlayHarnessState();
}

class _OverlayHarnessState extends State<_OverlayHarness> {
  SocialStatus _status = const SocialStatus.empty();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: (innerContext) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    final selected = await showSocialStatusPicker(
                      innerContext,
                      initialStatus: _status,
                    );
                    if (selected != null && mounted) {
                      setState(() => _status = selected);
                    }
                  },
                  child: Text(_status.isEmpty ? '打开状态' : _status.label),
                ),
              ),
            ),
          ),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 120,
          child: ColoredBox(
            color: Colors.black,
            child: Center(
              child: Text('胶囊播放器遮罩', style: TextStyle(color: Colors.white)),
            ),
          ),
        ),
      ],
    );
  }
}
