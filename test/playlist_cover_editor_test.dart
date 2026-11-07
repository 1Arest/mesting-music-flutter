import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/playlists/presentation/playlist_editor_dialog.dart';

void main() {
  Future<void> open(
    WidgetTester tester, {
    String? cover,
    Future<void> Function(PlaylistDraft)? save,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showPlaylistEditorDialog(
                context,
                initialCoverAsset: cover,
                onSave: save,
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets('new playlist exposes cover templates and gallery in a sheet', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('新建歌单'), findsOneWidget);
    expect(find.text('从相册选择封面'), findsOneWidget);
    expect(find.byTooltip('保存歌单'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets('persisted local cover remains readable after reopening', (
    tester,
  ) async {
    final path = File(
      'assets/images/theme_gallery/shinchan-avatar-v2.png',
    ).absolute.path;
    await open(tester, cover: path);
    final images = tester.widgetList<Image>(find.byType(Image));
    expect(
      images.any((widget) {
        final provider = widget.image;
        return provider is FileImage ||
            (provider is ResizeImage && provider.imageProvider is FileImage);
      }),
      isTrue,
    );
  });
  testWidgets(
    'failed save retains the draft and explicit retry commits it once',
    (tester) async {
      final submitted = <PlaylistDraft>[];
      await open(
        tester,
        save: (draft) async {
          submitted.add(draft);
          if (submitted.length == 1) throw StateError('网络中断，请重试');
        },
      );
      await tester.enterText(
        find.byKey(const ValueKey('playlist-editor-name-field')),
        '夜行电台',
      );
      await tester.enterText(
        find.byKey(const ValueKey('playlist-editor-description-field')),
        '慢慢听',
      );
      await tester.tap(find.byTooltip('保存歌单'));
      await tester.pumpAndSettle();
      expect(find.text('网络中断，请重试'), findsOneWidget);
      expect(find.text('夜行电台'), findsOneWidget);
      expect(find.text('慢慢听'), findsOneWidget);
      expect(submitted, hasLength(1));
      await tester.tap(find.byTooltip('保存歌单'));
      await tester.pumpAndSettle();
      expect(submitted, hasLength(2));
      expect(submitted.last.name, submitted.first.name);
      expect(find.byKey(const ValueKey('playlist-editor-sheet')), findsNothing);
    },
  );
  testWidgets(
    'short keyboard viewport keeps save accessible and rejects blank name',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await open(tester);
      await tester.tap(find.byTooltip('保存歌单'));
      await tester.pumpAndSettle();
      expect(find.text('请先填写歌单名称'), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetViewInsets);
      await tester.showKeyboard(
        find.byKey(const ValueKey('playlist-editor-name-field')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('保存歌单'));
      expect(tester.takeException(), null);
    },
  );
}
