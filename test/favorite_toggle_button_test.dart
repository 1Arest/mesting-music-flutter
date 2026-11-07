import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/library/presentation/favorite_toggle_button.dart';

import 'support/test_tracks.dart';

void main() {
  testWidgets('confirmed unlike shows a broken heart then restores the empty glyph', (tester) async {
    final track = testTracks.first;
    final container = ProviderContainer(overrides: [favoriteTrackIdsProvider.overrideWithValue({track.id})]);
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: MaterialApp(home: Scaffold(body: FavoriteToggleButton(track: track)))));
    container.updateOverrides([favoriteTrackIdsProvider.overrideWithValue({})]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byIcon(Icons.heart_broken_outlined), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsNothing);
    await tester.pump(const Duration(milliseconds: 650));
    expect(find.byIcon(Icons.heart_broken_outlined), findsNothing);
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
  Widget app({required bool favorite}) {
    final track = testTracks.first;
    return ProviderScope(
      overrides: [
        favoriteTrackIdsProvider.overrideWithValue({if (favorite) track.id}),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: FavoriteToggleButton(track: track, compact: true),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'unselected favorite is a bare outlined heart with a 48dp target',
    (tester) async {
      final track = testTracks.first;
      await tester.pumpWidget(app(favorite: false));

      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(find.byIcon(Icons.favorite_rounded), findsNothing);
      expect(find.bySemanticsLabel('收藏《${track.title}》'), findsOneWidget);

      final buttonFinder = find.byKey(ValueKey('favorite-button-${track.id}'));
      expect(tester.getSize(buttonFinder), const Size.square(48));
      final iconButton = tester.widget<IconButton>(
        find.descendant(of: buttonFinder, matching: find.byType(IconButton)),
      );
      expect(
        iconButton.style!.backgroundColor!.resolve({}),
        Colors.transparent,
      );
      expect(
        find.descendant(
          of: buttonFinder,
          matching: find.byType(AnimatedContainer),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('selected favorite uses a bare filled heart without a glow', (
    tester,
  ) async {
    final track = testTracks.first;
    await tester.pumpWidget(app(favorite: true));

    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
    expect(find.bySemanticsLabel('已收藏《${track.title}》'), findsOneWidget);

    final buttonFinder = find.byKey(ValueKey('favorite-button-${track.id}'));
    expect(tester.getSize(buttonFinder), const Size.square(48));
    final iconButton = tester.widget<IconButton>(
      find.descendant(of: buttonFinder, matching: find.byType(IconButton)),
    );
    expect(iconButton.style!.backgroundColor!.resolve({}), Colors.transparent);
  });
}
