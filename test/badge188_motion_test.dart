import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/music_platform/domain/membership_badge.dart';
import 'package:mesting_music/features/music_platform/presentation/animated_membership_badge.dart';

void main() {
  testWidgets(
    'membership motion stops when hidden or reduced and resumes without moving its label',
    (tester) async {
      Widget app({bool visible = true, bool reduced = false}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: TickerMode(
            enabled: visible,
            child: const Scaffold(
              body: Center(
                child: AnimatedMembershipBadge(
                  tier: MembershipBadgeTier.supreme,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app());
      final label = find.text('至尊SVIP');
      final rect = tester.getRect(label);
      expect(tester.hasRunningAnimations, true);
      await tester.pump(const Duration(milliseconds: 1100));
      expect(tester.getRect(label), rect);
      await tester.pumpWidget(app(visible: false));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, false);
      await tester.pumpWidget(app());
      expect(tester.hasRunningAnimations, true);
      await tester.pumpWidget(app(reduced: true));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, false);
      expect(find.bySemanticsLabel(RegExp('至尊SVIP，本地会员展示')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
