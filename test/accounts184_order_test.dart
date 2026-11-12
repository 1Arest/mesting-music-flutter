import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/music_platform/data/kugou_account_store.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/presentation/kugou_accounts_page.dart';
import 'support/release_152_qa.dart';

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async =>
      const PlatformSession(userId: 'b', token: 'fixture');
  void select(PlatformSession value) => state = AsyncData(value);
}

void main() {
  setUpAll(initialize151QA);
  testWidgets(
    'current login is first, peers stable, saved snapshot untouched',
    (tester) async {
      const saved = [
        KugouSavedAccount(userId: 'a', nickname: '甲', avatarUrl: ''),
        KugouSavedAccount(userId: 'b', nickname: '乙', avatarUrl: ''),
        KugouSavedAccount(userId: 'c', nickname: '丙', avatarUrl: ''),
      ];
      final scope = ProviderContainer(
        overrides: [
          platformAccountProvider.overrideWith(_Account.new),
          savedKugouAccountsProvider.overrideWith((_) async => saved),
        ],
      );
      await scope.read(platformAccountProvider.future);
      await scope.read(savedKugouAccountsProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: scope,
          child: MaterialApp(
            theme: theme152(false),
            home: const KugouAccountsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      List<String> order() => tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((w) => w.key)
          .whereType<ValueKey<String>>()
          .map((k) => k.value)
          .where((k) => k.startsWith('kugou-account-'))
          .toList();
      expect(order(), [
        'kugou-account-b',
        'kugou-account-a',
        'kugou-account-c',
      ]);
      (scope.read(platformAccountProvider.notifier) as _Account).select(
        const PlatformSession(userId: 'c', token: 'fixture-c'),
      );
      await tester.pumpAndSettle();
      expect(order(), [
        'kugou-account-c',
        'kugou-account-a',
        'kugou-account-b',
      ]);
      expect(
        (await scope.read(
          savedKugouAccountsProvider.future,
        )).map((a) => a.userId),
        ['a', 'b', 'c'],
      );
      expect(find.text('当前登录'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      scope.dispose();
    },
  );
}
