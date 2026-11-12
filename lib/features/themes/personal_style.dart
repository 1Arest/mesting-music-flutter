import '../../shared/models/track.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/persistence/app_preferences.dart';

enum CoverFrame { none, polaroid, stamp }

enum AvatarAccessory { none, notes, stars, moon, bow, record }

enum MiniPlayerFinish { original, frosted, metal, gradient }

enum PosterTemplate { original, ticket, magazine, note, cassette }

enum KeepsakeTemplate { original, postcard, collection }

enum ListeningAtmosphere { off, glow, stars, record }

/// Presentation is independent of lyric typography and palette. Existing
/// preference documents keep their current player until explicitly changed.
enum LyricPresentation { current, focus, clear }

const personalPalettes = <String, Color>{
  '默认': Color(0xFF0A84FF),
  '樱花汽水': Color(0xFFC3507B),
  '海盐蓝调': Color(0xFF297DB5),
  '薰衣草夜曲': Color(0xFF8A61B6),
  '焦糖唱片': Color(0xFF9C682C),
  '薄荷清晨': Color(0xFF267E73),
  '午夜霓虹': Color(0xFF8966DB),
};

/// Explicit bundle selection applies a matching lyric/accessory recommendation.
/// Subsequent edits stay independent; no rebuild re-applies these defaults.
Map<String, Object?> personalPaletteBundle(String name) {
  if (name == '默认') return {'palette': '默认'};
  const accessories = ['bow', 'notes', 'moon', 'record', 'stars', 'moon'];
  const highlights = [
    0xFFFFC2D6,
    0xFFADDFFF,
    0xFFD9C2FF,
    0xFFFFD5A0,
    0xFFADE9DE,
    0xFFC9BEFF,
  ];
  final index = personalPalettes.keys.toList().indexOf(name) - 1;
  if (index < 0 || index >= accessories.length) {
    throw ArgumentError.value(name, 'palette');
  }
  return {
    'palette': name,
    'accessory': accessories[index],
    'lyricColor': highlights[index],
    'lyricSize': 28.0,
    'lineHeight': 1.4,
    'lyricWeight': 2,
    'serif': false,
  };
}

/// One independent preference document; old theme, rail and character choices
/// are untouched. Unknown values fall back individually during upgrades.
class PersonalStyle {
  const PersonalStyle({
    this.palette = '默认',
    this.frame = CoverFrame.none,
    this.accessory = AvatarAccessory.none,
    this.mini = MiniPlayerFinish.original,
    this.poster = PosterTemplate.original,
    this.keepsake = KeepsakeTemplate.original,
    this.atmosphere = ListeningAtmosphere.off,
    this.strength = .35,
    this.lyricSize = 0,
    this.lineHeight = 0,
    this.lyricColor,
    this.serif = false,
    this.lyricWeight = 0,
    this.lyricPresentation = LyricPresentation.current,
    this.discoveryNotes = true,
  });
  final String palette;
  final CoverFrame frame;
  final AvatarAccessory accessory;
  final MiniPlayerFinish mini;
  final PosterTemplate poster;
  final KeepsakeTemplate keepsake;
  final ListeningAtmosphere atmosphere;
  final double strength, lyricSize, lineHeight;
  final int? lyricColor;
  final bool serif, discoveryNotes;
  final int lyricWeight;
  final LyricPresentation lyricPresentation;
  Color get accent => personalPalettes[palette] ?? personalPalettes['默认']!;
  Map<String, Object?> toJson() => {
    'palette': palette,

    'accessory': accessory.name,
    'mini': mini.name,
    'poster': poster.name,
    'keepsake': keepsake.name,
    'atmosphere': atmosphere.name,
    'strength': strength,
    'lyricSize': lyricSize,
    'lineHeight': lineHeight,
    'lyricColor': lyricColor,
    'serif': serif,
    'lyricWeight': lyricWeight,
    'lyricPresentation': lyricPresentation.name,
    'discoveryNotes': discoveryNotes,
  };
  factory PersonalStyle.fromJson(Map<String, dynamic> j) {
    T choice<T extends Enum>(List<T> values, String key) =>
        values.firstWhere((v) => v.name == j[key], orElse: () => values.first);
    double number(String key, double fallback, double min, double max) {
      final value = j[key];
      return value is num && value.isFinite
          ? value.toDouble().clamp(min, max)
          : fallback;
    }

    // Zero keeps the player's existing typography; custom values stay usable.
    double typography(String key, double min, double max) {
      final value = number(key, 0, 0, max);
      return value == 0 ? 0 : value.clamp(min, max);
    }

    final savedColor = j['lyricColor'];
    return PersonalStyle(
      palette: personalPalettes.containsKey(j['palette'])
          ? j['palette'] as String
          : '默认',
      frame: CoverFrame.none,
      accessory: choice(AvatarAccessory.values, 'accessory'),
      mini: choice(MiniPlayerFinish.values, 'mini'),
      poster: choice(PosterTemplate.values, 'poster'),
      keepsake: choice(KeepsakeTemplate.values, 'keepsake'),
      atmosphere: choice(ListeningAtmosphere.values, 'atmosphere'),
      lyricPresentation: choice(LyricPresentation.values, 'lyricPresentation'),
      strength: number('strength', .35, 0, 1),
      lyricSize: typography('lyricSize', 20, 40),
      lineHeight: typography('lineHeight', 1.1, 2.4),
      serif: j['serif'] == true,
      lyricColor:
          savedColor is int && savedColor >= 0 && savedColor <= 0xFFFFFFFF
          ? savedColor
          : null,
      lyricWeight: j['lyricWeight'] == 1
          ? 1
          : j['lyricWeight'] == 2
          ? 2
          : 0,
      discoveryNotes: j['discoveryNotes'] != false,
    );
  }
}

class PersonalStyleController extends Notifier<PersonalStyle> {
  static const preferenceKey = 'music_personal_style_v1';
  @override
  PersonalStyle build() {
    try {
      final json = jsonDecode(
        ref.watch(sharedPreferencesProvider).getString(preferenceKey) ?? '{}',
      );
      return PersonalStyle.fromJson(json is Map<String, dynamic> ? json : {});
    } catch (_) {
      return const PersonalStyle();
    }
  }

  // Serialize writes so a fast slider/selection sequence persists in order.
  Future<void> _pending = Future.value();
  Future<void> change(Map<String, Object?> patch) {
    final next = PersonalStyle.fromJson({...state.toJson(), ...patch});
    state = next;
    final prefs = ref.read(sharedPreferencesProvider);
    final operation = _pending.then((_) async {
      if (!await prefs.setString(preferenceKey, jsonEncode(next.toJson()))) {
        throw StateError('装扮暂未保存，请重试');
      }
    });
    _pending = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> reset() => change(const PersonalStyle().toJson());
}

final personalStyleProvider =
    NotifierProvider<PersonalStyleController, PersonalStyle>(
      PersonalStyleController.new,
    );

/// Only color roles change; all application typography and neutral surfaces
/// keep their existing contrast. Semantic error/success colors are preserved.
ThemeData applyPersonalPalette(ThemeData theme, PersonalStyle style) {
  if (style.palette == '默认') return theme;
  final colors = ColorScheme.fromSeed(
    seedColor: style.accent,
    brightness: theme.brightness,
  );
  return theme.copyWith(
    colorScheme: theme.colorScheme.copyWith(
      primary: colors.primary,
      onPrimary: colors.onPrimary,
      primaryContainer: colors.primaryContainer,
      onPrimaryContainer: colors.onPrimaryContainer,
      secondary: colors.secondary,
      onSecondary: colors.onSecondary,
    ),
    cupertinoOverrideTheme: theme.cupertinoOverrideTheme?.copyWith(
      primaryColor: colors.primary,
    ),
  );
}

/// Explicit illustrative content for settings opened without a running player.
const personalStyleDemoTrack = Track(
  id: 'personal-style-preview',
  title: '歌曲分享预览',
  artist: 'Mesting Music',
  album: '效果预览',
  duration: Duration.zero,
  audioAsset: '',
  coverAsset: '',
  lyricsAsset: '',
);
