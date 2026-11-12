import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mesting_music/features/experience/presentation/beta_bottom_bar.dart';
import 'package:mesting_music/shared/widgets/beta_entrance_readiness.dart';
import 'package:mesting_music/shared/widgets/beta_glass_popover.dart';
import 'package:mesting_music/shared/widgets/beta_music_chrome_scope.dart';
import 'package:mesting_music/shared/widgets/beta_root_tab_viewport.dart';
import 'package:mesting_music/shared/widgets/beta_text_editing.dart';
import 'package:mesting_music/shared/widgets/route_settled_content.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await LiquidGlassWidgets.initialize();
    if (!const bool.fromEnvironment('CAPTURE_V140')) return;
    for (final family in [
      'Roboto',
      'CupertinoSystemText',
      'CupertinoSystemDisplay',
      'sans-serif',
    ]) {
      await (FontLoader(family)..addFont(
            File(
              'C:/Windows/Fonts/msyh.ttc',
            ).readAsBytes().then(ByteData.sublistView),
          ))
          .load();
    }
    await (FontLoader('MaterialIcons')..addFont(
          File(
            'D:/CodexCache/flutter-3.41.9/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
          rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
        ))
        .load();
  });

  testWidgets('search padding reopens a hidden IME without losing focus', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final focus = FocusNode();
    final text = TextEditingController(text: 'Canon');
    await tester.pumpWidget(
      MaterialApp(
        home: GlassScaffold(
          edgeFade: false,
          resizeToAvoidBottomInset: false,
          body: const SizedBox.expand(),
          bottomBar: BetaMusicBottomBar(
            selectedIndex: 0,
            onTabSelected: (_) {},
            isSearchActive: true,
            searchConfig: GlassSearchBarConfig(
              onSearchToggle: (_) {},
              controller: text,
              focusNode: focus,
              expandWhenActive: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CupertinoTextField));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    tester.testTextInput.hide();
    final before = tester.testTextInput.log
        .where((call) => call.method == 'TextInput.show')
        .length;
    final field = tester.getRect(find.byType(CupertinoTextField));
    await tester.tapAt(Offset(field.left - 8, field.center.dy));
    await tester.pump();
    expect(
      tester.testTextInput.log
          .where((call) => call.method == 'TextInput.show')
          .length,
      greaterThan(before),
    );
    expect(text.text, 'Canon');
    await tester.pumpWidget(const SizedBox());
    focus.dispose();
    text.dispose();
  });

  testWidgets('compact to search retains exactly one live editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var expanded = false;
    late StateSetter update;
    final text = TextEditingController(text: 'Canon');
    final focus = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return GlassScaffold(
              edgeFade: false,
              body: const SizedBox.expand(),
              bottomBar: BetaMusicBottomBar(
                selectedIndex: 0,
                onTabSelected: (_) {},
                isSearchActive: true,
                inline: !expanded,
                accessory: const Text('Current song'),
                searchConfig: GlassSearchBarConfig(
                  controller: text,
                  focusNode: focus,
                  expandWhenActive: expanded,
                  onSearchToggle: (_) {},
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final editor = tester.state(find.byType(EditableText));
    update(() => expanded = true);
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(EditableText), findsOneWidget);
    }
    expect(tester.state(find.byType(EditableText)), same(editor));
    await tester.tap(find.byType(CupertinoTextField));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    expect(text.text, 'Canon');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    focus.dispose();
    text.dispose();
  });

  for (final player in [false, true]) {
    testWidgets(
      'imperative fullscreen suppresses paint and taps player=$player',
      (tester) async {
        final chrome = BetaMusicChromeController();
        final reveal = ValueNotifier(1.0); // Stale prior player dismissal.
        final navigator = GlobalKey<NavigatorState>();
        var paints = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: BetaMusicChromeScope(
              controller: chrome,
              child: Stack(
                children: [
                  Navigator(
                    key: navigator,
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (_) => const ColoredBox(color: Colors.white),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: BetaMusicChromeGate(
                      controller: chrome,
                      playerReveal: reveal,
                      child: _PaintCounter(
                        onPaint: () => paints++,
                        child: GestureDetector(
                          key: const ValueKey('persistent-chrome'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () {},
                          child: const SizedBox(height: 64),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final before = paints;
        unawaited(
          navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => BetaMusicChromeCover(
                player: player,
                child: const ColoredBox(color: Colors.blue),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(chrome.covered, isTrue);
        expect(paints, before);
        expect(
          find.byKey(const ValueKey('persistent-chrome')).hitTestable(),
          findsNothing,
        );
        reveal.value = 0;
        await tester.pump();
        reveal.value = .5;
        await tester.pump();
        expect(paints, player ? greaterThan(before) : before);
        expect(
          find.byKey(const ValueKey('persistent-chrome')).hitTestable(),
          findsNothing,
        );
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(chrome.covered, isFalse);
        expect(
          find.byKey(const ValueKey('persistent-chrome')).hitTestable(),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
        chrome.dispose();
        reveal.dispose();
      },
    );
  }

  test('editing menu clamps to the available short keyboard viewport', () {
    const layout = BetaMenuLayout(
      anchor: Rect.fromLTWH(12, 64, 280, 48),
      media: MediaQueryData(
        size: Size(320, 360),
        padding: EdgeInsets.only(top: 24),
        viewInsets: EdgeInsets.only(bottom: 280),
      ),
      width: 270,
    );
    final constraints = layout.getConstraintsForChild(
      const BoxConstraints.tightFor(width: 320, height: 360),
    );
    expect(constraints.maxHeight, lessThanOrEqualTo(32));
    final size = constraints.constrain(const Size(270, 300));
    final rect = layout.getPositionForChild(const Size(320, 360), size) & size;
    expect(rect.left, greaterThanOrEqualTo(12));
    expect(rect.right, lessThanOrEqualTo(308));
    expect(rect.top, greaterThanOrEqualTo(36));
    expect(rect.bottom, lessThanOrEqualTo(68));
  });

  for (final dark in [false, true]) {
    testWidgets('expanded paste menu follows IME geometry dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final focus = FocusNode();
      final text = TextEditingController(text: 'Canon');
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => RepaintBoundary(
            key: const ValueKey('editing-capture'),
            child: child,
          ),
          theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
          home: GlassScaffold(
            edgeFade: false,
            resizeToAvoidBottomInset: false,
            body: const SizedBox.expand(),
            bottomBar: BetaMusicBottomBar(
              selectedIndex: 0,
              onTabSelected: (_) {},
              isSearchActive: true,
              searchConfig: GlassSearchBarConfig(
                onSearchToggle: (_) {},
                controller: text,
                focusNode: focus,
                expandWhenActive: true,
                contextMenuBuilder: buildBetaEditingMenu,
                selectionControls: betaTextSelectionControls,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CupertinoTextField));
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      final editor = tester.state<EditableTextState>(find.byType(EditableText));
      editor.showToolbar();
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('更多编辑操作'));
      await tester.pumpAndSettle();
      for (final inset in [280.0, 180.0, 0.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: inset);
        await tester.pumpAndSettle();
        final menu = tester.getRect(
          find.byKey(const ValueKey('beta13-glass-menu-surface')),
        );
        final field = tester.getRect(find.byType(CupertinoTextField));
        expect(menu.left, greaterThanOrEqualTo(11.9));
        expect(menu.right, lessThanOrEqualTo(378.1));
        expect(menu.bottom, lessThanOrEqualTo(844 - inset - 11.9));
        expect(menu.bottom, lessThanOrEqualTo(field.top - 7.9));
        if (const bool.fromEnvironment('CAPTURE_V140') && inset == 280) {
          await tester.runAsync(() async {
            final image = await tester
                .renderObject<RenderRepaintBoundary>(
                  find.byKey(const ValueKey('editing-capture')),
                )
                .toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              '.codex-artifacts/2026-11-02-v140-fixes/ui/search-menu-${dark ? 'dark' : 'light'}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
      editor.hideToolbar();
      await tester.pumpWidget(const SizedBox());
      focus.dispose();
      text.dispose();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('cold target work starts after tab motion and stays retained', (
    tester,
  ) async {
    var index = 0, mounted = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return BetaRootTabViewport(
              index: index,
              children: [
                const Text('Discovery'),
                const Text('Functions'),
                const Text('Library'),
                RouteSettledContent(
                  builder: (_) => _MountedCounter(onMount: () => mounted++),
                  placeholder: const Text('Profile loading'),
                ),
              ],
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    update(() => index = 3);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      mounted,
      0,
      reason: 'Cold profile subscriptions do not start in moving frames.',
    );
    await tester.pumpAndSettle();
    expect(mounted, 1);
    update(() => index = 0);
    await tester.pumpAndSettle();
    update(() => index = 3);
    await tester.pumpAndSettle();
    expect(mounted, 1, reason: 'A visited profile keeps its existing element.');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cold optional search work waits for its containing slide', (
    tester,
  ) async {
    var ready = false, mounted = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return BetaEntranceReadiness(
              ready: ready,
              child: RouteSettledContent(
                builder: (_) => _MountedCounter(onMount: () => mounted++),
                placeholder: const Text('Search keywords'),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 290));
    expect(mounted, 0);
    update(() => ready = true);
    await tester.pump();
    expect(mounted, 1);
    update(() => ready = false);
    await tester.pump();
    expect(mounted, 1);
    await tester.pumpWidget(const SizedBox());
  });
}

class _PaintCounter extends SingleChildRenderObjectWidget {
  const _PaintCounter({required this.onPaint, required super.child});
  final VoidCallback onPaint;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPaintCounter(onPaint);
}

class _RenderPaintCounter extends RenderProxyBox {
  _RenderPaintCounter(this.onPaint);
  final VoidCallback onPaint;
  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint();
    super.paint(context, offset);
  }
}

class _MountedCounter extends StatefulWidget {
  const _MountedCounter({required this.onMount});
  final VoidCallback onMount;
  @override
  State<_MountedCounter> createState() => _MountedCounterState();
}

class _MountedCounterState extends State<_MountedCounter> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const Text('Ready');
}
