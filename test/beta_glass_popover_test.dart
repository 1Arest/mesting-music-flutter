import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/features/experience/presentation/beta_bottom_bar.dart';
import 'package:mesting_music/shared/widgets/beta_glass_popover.dart';
import 'package:mesting_music/shared/widgets/beta_text_editing.dart';

void main() {
  setUpAll(LiquidGlassWidgets.initialize);

  testWidgets(
    'live menu optics stay outside partially transparent compositing layers',
    (tester) async {
      final animation = AnimationController(
        vsync: tester,
        duration: betaMenuOpenDuration,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: BetaGlassMenuTransition(
              animation: animation,
              origin: Alignment.topRight,
              child: const SizedBox(
                width: 260,
                height: 400,
                child: Text('菜单内容'),
              ),
            ),
          ),
        ),
      );
      animation.forward();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 45));
      final menu = find.byKey(const ValueKey('beta13-glass-menu-surface'));
      // An ancestor fade makes the glass sample a transparent, menu-local render
      // pass on Impeller. The text can fade; the live backdrop must stay outside.
      final ancestors = find.ancestor(
        of: menu,
        matching: find.byType(FadeTransition),
      );
      for (final element in ancestors.evaluate()) {
        expect((element.widget as FadeTransition).opacity.value, 1);
      }
      final foreground = tester.widget<FadeTransition>(
        find.descendant(of: menu, matching: find.byType(FadeTransition)),
      );
      expect(foreground.opacity.value, inExclusiveRange(0, 1));
      animation.reverse();
      await tester.pump(const Duration(milliseconds: 30));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      animation.dispose();
    },
  );

  test('menu layout faces its real trigger above and below the field', () {
    const media = MediaQueryData(size: Size(390, 844));
    for (final anchor in [
      const Rect.fromLTWH(20, 80, 80, 48),
      const Rect.fromLTWH(280, 700, 80, 48),
    ]) {
      final layout = BetaMenuLayout(anchor: anchor, media: media, width: 300);
      final position = layout.getPositionForChild(
        media.size,
        const Size(300, 180),
      );
      if (layout.above) {
        expect(anchor.top - position.dy - 180, closeTo(betaMenuAnchorGap, .01));
        expect(layout.motionOrigin.y, 1);
      } else {
        expect(position.dy - anchor.bottom, closeTo(betaMenuAnchorGap, .01));
        expect(layout.motionOrigin.y, -1);
      }
      expect(position.dx, inInclusiveRange(12, 78));
    }
  });

  testWidgets('menu grows from its trigger while keeping one optical surface', (
    tester,
  ) async {
    final motion = AnimationController(
      vsync: tester,
      duration: betaMenuOpenDuration,
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: BetaGlassMenuTransition(
              animation: motion,
              origin: Alignment.bottomCenter,
              child: const SizedBox(width: 240, height: 180),
            ),
          ),
        ),
      );
      final menu = find.byKey(const ValueKey('beta13-glass-menu-surface'));
      final surface = tester.widget<GlassContainer>(menu);
      expect(tester.getRect(menu).height, lessThanOrEqualTo(50));
      motion.forward();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(identical(surface, tester.widget<GlassContainer>(menu)), true);
      await tester.pump(betaMenuOpenDuration);
      expect(tester.getRect(menu).height, closeTo(180, .1));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      motion.dispose();
    }
  });

  for (final reduceMotion in [false, true]) {
    testWidgets('popover finishes closing before its action ($reduceMotion)', (
      tester,
    ) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reduceMotion),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return Center(
                  child: TextButton(
                    onPressed: () async {
                      result = await showBetaGlassPopover<String>(
                        context: context,
                        anchor: const Rect.fromLTWH(60, 700, 270, 48),
                        builder: (dialog) => TextButton(
                          onPressed: () => Navigator.of(dialog).pop('queue'),
                          child: const Text('查看队列'),
                        ),
                      );
                    },
                    child: const Text('打开菜单'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开菜单'));
      await tester.pump();
      if (!reduceMotion) await tester.pump(betaMenuOpenDuration);
      await tester.pump();
      await tester.tap(find.text('查看队列'));
      await tester.pump();
      if (!reduceMotion) {
        expect(result, isNull);
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          find.byKey(const ValueKey('beta13-glass-menu-surface')),
          findsOneWidget,
        );
        expect(result, isNull);
        await tester.pump(betaMenuCloseDuration);
      }
      await tester.pump();
      expect(result, 'queue');
      expect(
        find.byKey(const ValueKey('beta13-glass-menu-surface')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('reversing an opening menu keeps its current painted bounds', (
    tester,
  ) async {
    final motion = AnimationController(
      vsync: tester,
      duration: betaMenuOpenDuration,
      reverseDuration: betaMenuCloseDuration,
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: BetaGlassMenuTransition(
                animation: motion,
                origin: Alignment.bottomCenter,
                child: const SizedBox(width: 240, height: 180),
              ),
            ),
          ),
        ),
      );
      motion.forward();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final menu = find.byKey(const ValueKey('beta13-glass-menu-surface'));
      final before = tester.getRect(menu);
      motion.reverse();
      await tester.pump();
      final after = tester.getRect(menu);
      expect(after.left, closeTo(before.left, .01));
      expect(after.top, closeTo(before.top, .01));
      expect(after.width, closeTo(before.width, .01));
      expect(after.height, closeTo(before.height, .01));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      motion.dispose();
    }
  });

  testWidgets(
    'editing menu leaves its gap outside the complete multiline field',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final controller = TextEditingController(text: '写下你的评论');
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: TextField(
                    key: const ValueKey('comment-input'),
                    controller: controller,
                    maxLines: 4,
                    contextMenuBuilder: buildBetaEditingMenu,
                    selectionControls: betaTextSelectionControls,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byType(TextField));
        await tester.pump();
        final editable = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
        editable.showToolbar();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.bySemanticsLabel('更多编辑操作'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final menu = tester.getRect(
          find.byKey(const ValueKey('beta13-glass-menu-surface')),
        );
        final field = tester.getRect(
          find.byKey(const ValueKey('comment-input')),
        );
        expect(field.top - menu.bottom, greaterThanOrEqualTo(8));
        expect(menu.top, greaterThanOrEqualTo(12));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    },
  );

  testWidgets(
    'menus blur slightly more than the resting capsule in both themes',
    (tester) async {
      for (final brightness in Brightness.values) {
        double? restingBlur;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  restingBlur = betaMusicPillGlass(context).blur;
                  return const Center(
                    child: BetaGlassMenuSurface(
                      child: SizedBox(width: 200, height: 120),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        final glass = tester.widget<GlassContainer>(
          find.byKey(const ValueKey('beta13-glass-menu-surface')),
        );
        expect(glass.settings!.blur, greaterThan(restingBlur!));
        expect(glass.settings!.blur, greaterThan(3));
        expect(glass.settings!.blur - restingBlur!, lessThanOrEqualTo(3));
        expect(glass.quality, GlassQuality.premium);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
