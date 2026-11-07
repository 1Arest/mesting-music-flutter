import 'package:flutter/material.dart';

import 'mesting_palette.dart';

enum MusicThemeIp { classic, shinchan, helloKitty, kuromi }

enum ThemeMotion {
  none,
  drift,
  rain,
  parade,
  dream,
  petals,
  carousel,
  stickers,
  vinyl,
}

@immutable
class MusicThemePreset {
  const MusicThemePreset({
    required this.id,
    required this.ip,
    required this.name,
    required this.caption,
    required this.description,
    required this.backgroundAsset,
    required this.colors,
    required this.accent,
    this.motion = ThemeMotion.none,
    this.mobileBackgroundAsset,
    this.alignment = Alignment.center,
    this.dark = false,
    this.followsSystem = false,
  });

  final String id;
  final MusicThemeIp ip;
  final String name;
  final String caption;
  final String description;
  final String? backgroundAsset;
  final String? mobileBackgroundAsset;
  final List<Color> colors;
  final Color accent;
  final ThemeMotion motion;
  final Alignment alignment;
  final bool dark;
  final bool followsSystem;

  bool get isMotion => motion != ThemeMotion.none;
  String get ipLabel => switch (ip) {
    MusicThemeIp.classic => '经典',
    MusicThemeIp.shinchan => '蜡笔小新',
    MusicThemeIp.helloKitty => 'Hello Kitty',
    MusicThemeIp.kuromi => '库洛米',
  };

  String? get progressCharacterAsset => switch (ip) {
    MusicThemeIp.classic => null,
    MusicThemeIp.shinchan => null,
    MusicThemeIp.helloKitty =>
      'assets/images/theme_gallery/hello-kitty-progress-head.png',
    MusicThemeIp.kuromi =>
      'assets/images/theme_gallery/kuromi-progress-head.png',
  };
}

const _shinchanCovers = 'assets/images/theme_playlists/shinchan';
const _gallery = 'assets/images/theme_gallery';

const musicThemePresets = <MusicThemePreset>[
  MusicThemePreset(
    id: 'classic',
    ip: MusicThemeIp.classic,
    name: '浅色模式',
    caption: '浅色 · 无背景装饰',
    description: '使用纯白页面背景，让内容与控件保持清晰克制',
    backgroundAsset: null,
    colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
    accent: MestingPalette.primary,
  ),
  MusicThemePreset(
    id: 'classic-dark',
    ip: MusicThemeIp.classic,
    name: '深色模式',
    caption: '深色 · 无背景装饰',
    description: '使用纯黑页面背景，让文字与控件保持稳定对比',
    backgroundAsset: null,
    colors: [Color(0xFF000000), Color(0xFF000000)],
    accent: MestingPalette.primaryBright,
    dark: true,
  ),
  MusicThemePreset(
    id: 'classic-system',
    ip: MusicThemeIp.classic,
    name: '跟随系统',
    caption: '自动 · 与系统同步',
    description: '根据手机当前的浅色或深色外观自动切换',
    backgroundAsset: null,
    colors: [Color(0xFFFFFFFF), Color(0xFF000000)],
    accent: MestingPalette.primary,
    followsSystem: true,
  ),
  MusicThemePreset(
    id: 'kasukabe-sky',
    ip: MusicThemeIp.shinchan,
    name: '春日部晴空',
    caption: '晴天与彩虹',
    description: '明亮轻快的春日部晴空',
    backgroundAsset: '$_shinchanCovers/cover-09.jpg',
    colors: [Color(0xFFBDEBFF), Color(0xFFFFF7D8)],
    accent: MestingPalette.amber,
    alignment: Alignment(0.35, 0),
  ),
  MusicThemePreset(
    id: 'family-picnic',
    ip: MusicThemeIp.shinchan,
    name: '野原家野餐',
    caption: '草地与微风',
    description: '柔和清新的野原家野餐日',
    backgroundAsset: '$_shinchanCovers/cover-03.jpg',
    colors: [Color(0xFFDFF4C7), Color(0xFFFFF1C7)],
    accent: Color(0xFF48A868),
  ),
  MusicThemePreset(
    id: 'sunset-road',
    ip: MusicThemeIp.shinchan,
    name: '放学晚霞',
    caption: '橘粉夕阳',
    description: '暖橘色的放学回家路',
    backgroundAsset: '$_shinchanCovers/cover-15.jpg',
    colors: [Color(0xFFFFC98F), Color(0xFF9FC8EE)],
    accent: MestingPalette.azure,
  ),
  MusicThemePreset(
    id: 'starry-radio',
    ip: MusicThemeIp.shinchan,
    name: '春日部夜电台',
    caption: '深蓝星光',
    description: '适合夜间听歌的春日部电台',
    backgroundAsset: '$_shinchanCovers/cover-10.jpg',
    colors: [Color(0xFF18274B), Color(0xFF474A86)],
    accent: Color(0xFFFFC857),
    dark: true,
  ),
  MusicThemePreset(
    id: 'crayon-room',
    ip: MusicThemeIp.shinchan,
    name: '蜡笔涂鸦屋',
    caption: '奶油漫画感',
    description: '像蜡笔画一样温暖的室内背景',
    backgroundAsset: '$_shinchanCovers/cover-07.jpg',
    colors: [Color(0xFFFFE7B5), Color(0xFFAFCDF3)],
    accent: MestingPalette.amber,
  ),
  MusicThemePreset(
    id: 'rainy-day',
    ip: MusicThemeIp.shinchan,
    name: '小新雨天',
    caption: '雨滴与水蓝',
    description: '和撑伞小新一起听雨',
    backgroundAsset: '$_shinchanCovers/cover-01.jpg',
    colors: [Color(0xFFB8DDEB), Color(0xFFD9E9F0)],
    accent: Color(0xFF368FB7),
  ),
  MusicThemePreset(
    id: 'midnight-cinema',
    ip: MusicThemeIp.shinchan,
    name: '春日部深夜影院',
    caption: '专属暗色主题',
    description: '电影光影里的深夜音乐空间',
    backgroundAsset: '$_shinchanCovers/cover-02.jpg',
    colors: [Color(0xFF11182A), Color(0xFF273D68)],
    accent: MestingPalette.primaryBright,
    dark: true,
  ),
  MusicThemePreset(
    id: 'motion-walk',
    ip: MusicThemeIp.shinchan,
    name: '放学晴空',
    caption: '小新、小白与纸飞机',
    description: '和小新、小白沿着晴空街道随音乐回家',
    backgroundAsset: '$_gallery/motion-walk-shinchan-scene.webp',
    colors: [Color(0xFF9EDCFF), Color(0xFFFFF0B7)],
    accent: MestingPalette.amber,
    motion: ThemeMotion.drift,
  ),
  MusicThemePreset(
    id: 'motion-rain',
    ip: MusicThemeIp.shinchan,
    name: '雷雨夜行',
    caption: '小新、小白与雨夜水花',
    description: '和披着雨衣的小新踏过随音乐落下的雨幕',
    backgroundAsset: '$_gallery/motion-rain-shinchan-scene.webp',
    colors: [Color(0xFF111A35), Color(0xFF334E73)],
    accent: Color(0xFF70B7FF),
    motion: ThemeMotion.rain,
    dark: true,
  ),
  MusicThemePreset(
    id: 'motion-parade',
    ip: MusicThemeIp.shinchan,
    name: '春日部庆典巡游',
    caption: '小新、小白与庆典舞步',
    description: '跟着小新的祭典舞步感受灯笼与彩纸律动',
    backgroundAsset: '$_gallery/motion-parade-shinchan-scene.webp',
    colors: [Color(0xFFFFD38F), Color(0xFF8CC4E8)],
    accent: MestingPalette.teal,
    motion: ThemeMotion.parade,
  ),
  MusicThemePreset(
    id: 'hello-kitty-garden',
    ip: MusicThemeIp.helloKitty,
    name: 'Kitty 草莓花园',
    caption: '草莓、蝴蝶结与午后茶会',
    description: '奶油白和草莓红组成的甜点花园',
    backgroundAsset: '$_gallery/hello-kitty-main.png',
    colors: [Color(0xFFFFF8ED), Color(0xFFDCEEFF)],
    accent: Color(0xFF3E78B8),
    alignment: Alignment(0.72, 0.75),
  ),
  MusicThemePreset(
    id: 'hello-kitty-midnight',
    ip: MusicThemeIp.helloKitty,
    name: 'Kitty 蓝丝绒夜宴',
    caption: '蓝丝绒夜幕与香槟金',
    description: '午夜甜点桌的柔光氛围',
    backgroundAsset: '$_gallery/hello-kitty-friends.png',
    colors: [Color(0xFF111A2E), Color(0xFF29466F)],
    accent: Color(0xFFD8AD63),
    dark: true,
  ),
  MusicThemePreset(
    id: 'hello-kitty-dream',
    ip: MusicThemeIp.helloKitty,
    name: 'Kitty 云端梦游',
    caption: '云朵、爱心与漂浮丝带',
    description: 'Kitty 乘着云朵穿过粉蓝色梦境',
    backgroundAsset: '$_gallery/hello-kitty-angel.png',
    colors: [Color(0xFFD9ECFF), Color(0xFFE6E3FF)],
    accent: Color(0xFF687DD2),
    motion: ThemeMotion.dream,
    alignment: Alignment(-0.55, 0.72),
  ),
  MusicThemePreset(
    id: 'hello-kitty-patisserie',
    ip: MusicThemeIp.helloKitty,
    name: 'Kitty 草莓甜品屋',
    caption: '奶油蛋糕、茶杯与粉色磁带',
    description: '温暖的午后甜品台',
    backgroundAsset: '$_gallery/kitty-strawberry-patisserie.webp',
    colors: [Color(0xFFFFF0D9), Color(0xFFDDEEFF)],
    accent: Color(0xFF3E78B8),
  ),
  MusicThemePreset(
    id: 'hello-kitty-ribbon-cinema',
    ip: MusicThemeIp.helloKitty,
    name: 'Kitty 缎带影院',
    caption: '舞台幕布、胶片与蝴蝶结',
    description: '柔和复古的蝴蝶结放映室',
    backgroundAsset: '$_gallery/kitty-ribbon-cinema.webp',
    colors: [Color(0xFF121A2B), Color(0xFF31547D)],
    accent: Color(0xFFE3B66D),
    dark: true,
  ),
  MusicThemePreset(
    id: 'hello-kitty-sakura-breeze',
    ip: MusicThemeIp.helloKitty,
    name: 'Kitty 樱花纸笺',
    caption: '花瓣、信笺与轻风',
    description: '樱花纸笺在音乐页缓缓掠过',
    backgroundAsset: '$_gallery/kitty-sakura-letter.webp',
    colors: [Color(0xFFEDF4FF), Color(0xFFDCE8FF)],
    accent: Color(0xFF6078C8),
    motion: ThemeMotion.petals,
  ),
  MusicThemePreset(
    id: 'hello-kitty-candy-carousel',
    ip: MusicThemeIp.helloKitty,
    name: 'Kitty 月光旋转木马',
    caption: '粉金木马、纸灯与星星乐谱',
    description: '月光游园会随着旋律缓慢转动',
    backgroundAsset: '$_gallery/kitty-carousel-sunrise.webp',
    mobileBackgroundAsset: '$_gallery/kitty-carousel-mobile.webp',
    colors: [Color(0xFF1D2138), Color(0xFF41466F)],
    accent: Color(0xFFF1C66D),
    motion: ThemeMotion.carousel,
    dark: true,
  ),
  MusicThemePreset(
    id: 'kuromi-neon',
    ip: MusicThemeIp.kuromi,
    name: '库洛米霓虹卧室',
    caption: '黑莓紫与朋克格纹',
    description: '俏皮反叛的霓虹音乐房间',
    backgroundAsset: '$_gallery/kuromi-main.png',
    colors: [Color(0xFF17152D), Color(0xFF493A78)],
    accent: Color(0xFF8B70E8),
    dark: true,
    alignment: Alignment(-0.6, 0.72),
  ),
  MusicThemePreset(
    id: 'kuromi-midnight',
    ip: MusicThemeIp.kuromi,
    name: '库洛米暗夜舞台',
    caption: '黑曜石舞台与霓虹粉',
    description: '金属铆钉点亮深夜舞台',
    backgroundAsset: '$_gallery/kuromi-midnight-stage.webp',
    colors: [Color(0xFF10111B), Color(0xFF382E63)],
    accent: Color(0xFF8B70E8),
    dark: true,
  ),
  MusicThemePreset(
    id: 'kuromi-night-flight',
    ip: MusicThemeIp.kuromi,
    name: '库洛米午夜飞行',
    caption: '弯月、星芒与飞行轨迹',
    description: '库洛米掠过紫色夜空',
    backgroundAsset: '$_gallery/kuromi-melody.png',
    colors: [Color(0xFF17122B), Color(0xFF5E3B91)],
    accent: Color(0xFF9A7AF0),
    motion: ThemeMotion.drift,
    dark: true,
    alignment: Alignment(0.65, 0.7),
  ),
  MusicThemePreset(
    id: 'kuromi-arcade-noir',
    ip: MusicThemeIp.kuromi,
    name: '库洛米月光街机厅',
    caption: '街机、镜面球与紫色黑胶',
    description: '月光霓虹组成的深色音乐角落',
    backgroundAsset: '$_gallery/kuromi-arcade-noir.webp',
    colors: [Color(0xFF0D0D17), Color(0xFF342B57)],
    accent: Color(0xFF8068DE),
    dark: true,
  ),
  MusicThemePreset(
    id: 'kuromi-violet-library',
    ip: MusicThemeIp.kuromi,
    name: '库洛米紫夜书房',
    caption: '紫墨、旧书与星图',
    description: '把反叛感收进安静的夜读书房',
    backgroundAsset: '$_gallery/kuromi-violet-library.webp',
    colors: [Color(0xFF171124), Color(0xFF553A6A)],
    accent: Color(0xFFCF85FF),
    dark: true,
  ),
  MusicThemePreset(
    id: 'kuromi-sticker-storm',
    ip: MusicThemeIp.kuromi,
    name: '库洛米贴纸风暴',
    caption: '贴纸、星星与涂鸦',
    description: '手帐贴纸随着节拍在页面里飞舞',
    backgroundAsset: '$_gallery/kuromi-sticker-storm.webp',
    colors: [Color(0xFF18152D), Color(0xFF574585)],
    accent: Color(0xFF9A7AF0),
    motion: ThemeMotion.stickers,
    dark: true,
  ),
  MusicThemePreset(
    id: 'kuromi-vinyl-rush',
    ip: MusicThemeIp.kuromi,
    name: '库洛米黑胶夜行',
    caption: '紫曜黑胶、星夜与涂鸦节拍',
    description: '紫黑唱片舞台随播放节拍缓慢旋转',
    backgroundAsset: '$_gallery/kuromi-vinyl-night.webp',
    colors: [Color(0xFF10101B), Color(0xFF3C315F)],
    accent: Color(0xFF8068DE),
    motion: ThemeMotion.vinyl,
    dark: true,
  ),
];

MusicThemePreset musicThemePresetById(String? id) =>
    musicThemePresets.firstWhere(
      (preset) => preset.id == id,
      orElse: () => musicThemePresets[2],
    );

String themedPlaylistCover({
  required MusicThemePreset preset,
  required int index,
  required String fallback,
}) {
  if (preset.ip == MusicThemeIp.classic || index < 0 || index >= 16) {
    return fallback;
  }
  final number = index + 1;
  final suffix = number.toString().padLeft(2, '0');
  return switch (preset.ip) {
    MusicThemeIp.classic => fallback,
    MusicThemeIp.shinchan =>
      'assets/images/theme_playlists/shinchan/cover-$suffix.jpg',
    MusicThemeIp.helloKitty =>
      'assets/images/theme_playlists/hello_kitty/cover-$suffix.png',
    MusicThemeIp.kuromi =>
      'assets/images/theme_playlists/kuromi/cover-$suffix.png',
  };
}
