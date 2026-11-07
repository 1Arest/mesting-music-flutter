import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/discover/data/curated_playlists.dart';
import 'package:mesting_music/features/themes/music_theme_preset.dart';

String _fileFingerprint(String path) {
  final bytes = File(path).readAsBytesSync();
  var hash = 0xcbf29ce484222325;
  for (final byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return '${bytes.length}:$hash';
}

Future<(int width, int height)> _imageDimensions(String path) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  try {
    final frame = await codec.getNextFrame();
    return (frame.image.width, frame.image.height);
  } finally {
    codec.dispose();
  }
}

void main() {
  test('27 套主题的 ID、分组和动静态数量完整', () {
    expect(musicThemePresets, hasLength(27));
    expect(musicThemePresets.map((preset) => preset.id).toSet(), hasLength(27));
    expect(musicThemePresets.where((preset) => preset.isMotion), hasLength(9));
    expect(
      musicThemePresets.where((preset) => !preset.isMotion),
      hasLength(18),
    );
    final classic = musicThemePresets.where(
      (preset) => preset.ip == MusicThemeIp.classic,
    );
    expect(classic, hasLength(3));
    expect(classic.where((preset) => preset.dark), hasLength(1));
    expect(classic.where((preset) => preset.followsSystem), hasLength(1));
    final classicLight = classic.singleWhere(
      (preset) => !preset.dark && !preset.followsSystem,
    );
    final classicDark = classic.singleWhere((preset) => preset.dark);
    final classicSystem = classic.singleWhere((preset) => preset.followsSystem);
    expect(classicLight.colors.toSet(), {const Color(0xFFFFFFFF)});
    expect(classicDark.colors.toSet(), {const Color(0xFF000000)});
    expect(classicLight.name, '浅色模式');
    expect(classicDark.name, '深色模式');
    expect(classicSystem.name, '跟随系统');
    expect(classicSystem.colors, const [Color(0xFFFFFFFF), Color(0xFF000000)]);
    expect(
      musicThemePresets.where((preset) => preset.ip == MusicThemeIp.shinchan),
      hasLength(10),
    );
    expect(
      musicThemePresets.where((preset) => preset.ip == MusicThemeIp.helloKitty),
      hasLength(7),
    );
    expect(
      musicThemePresets.where((preset) => preset.ip == MusicThemeIp.kuromi),
      hasLength(7),
    );
  });

  test('主题图片、进度角色和三组歌单封面都存在', () {
    for (final preset in musicThemePresets) {
      final background = preset.backgroundAsset;
      if (background != null) expect(File(background).existsSync(), isTrue);
      final mobile = preset.mobileBackgroundAsset;
      if (mobile != null) expect(File(mobile).existsSync(), isTrue);
      final character = preset.progressCharacterAsset;
      if (character != null) expect(File(character).existsSync(), isTrue);
    }
    for (final preset in musicThemePresets.where(
      (preset) => preset.ip != MusicThemeIp.classic,
    )) {
      final resolvedCovers = <String>[];
      for (var index = 0; index < curatedPlaylists.length; index++) {
        final path = themedPlaylistCover(
          preset: preset,
          index: index,
          fallback: curatedPlaylists[index].coverAsset,
        );
        resolvedCovers.add(path);
        expect(File(path).existsSync(), isTrue, reason: path);
      }
      expect(
        resolvedCovers.toSet(),
        hasLength(curatedPlaylists.length),
        reason: '${preset.id} 的全部歌单封面不应循环复用',
      );
      expect(
        resolvedCovers.map(_fileFingerprint).toSet(),
        hasLength(curatedPlaylists.length),
        reason: '${preset.id} 的全部歌单封面图片内容不应重复',
      );
    }
  });

  test('主题分类使用三组比例正确的 IP 头像素材', () {
    const avatars = <String>[
      'assets/images/theme_gallery/shinchan-avatar-v2.png',
      'assets/images/theme_gallery/hello-kitty-progress-head.png',
      'assets/images/theme_gallery/kuromi-progress-head.png',
    ];
    for (final avatar in avatars) {
      final file = File(avatar);
      expect(file.existsSync(), isTrue, reason: avatar);
      expect(file.lengthSync(), greaterThan(0), reason: avatar);
    }
  });

  test('三套小新动态皮肤使用独立角色场景素材和角色化文案', () async {
    const expectedAssets = <String, String>{
      'motion-walk':
          'assets/images/theme_gallery/motion-walk-shinchan-scene.webp',
      'motion-rain':
          'assets/images/theme_gallery/motion-rain-shinchan-scene.webp',
      'motion-parade':
          'assets/images/theme_gallery/motion-parade-shinchan-scene.webp',
    };
    final fingerprints = <String>{};

    for (final entry in expectedAssets.entries) {
      final preset = musicThemePresets.singleWhere(
        (candidate) => candidate.id == entry.key,
      );
      expect(preset.ip, MusicThemeIp.shinchan);
      expect(preset.isMotion, isTrue);
      expect(preset.backgroundAsset, entry.value);
      expect(preset.caption, contains('小新'));
      expect(preset.caption, contains('小白'));
      expect(preset.description, contains('小新'));
      expect(await _imageDimensions(entry.value), (1672, 941));
      fingerprints.add(_fileFingerprint(entry.value));
    }

    expect(fingerprints, hasLength(expectedAssets.length));
  });
}
