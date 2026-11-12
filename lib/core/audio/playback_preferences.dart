import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../persistence/app_preferences.dart';

/// Independent from platform quality, EQ and the phone's media volume.
class PlaybackPreferences {
  const PlaybackPreferences({
    this.prepareNext = true,
    this.balance = false,
    this.crossfade = false,
    this.seconds = 3,
  });
  final bool prepareNext, balance, crossfade;
  final int seconds;
  Map<String, Object> toJson() => {
    'prepareNext': prepareNext,
    'balance': balance,
    'crossfade': crossfade,
    'seconds': seconds,
  };
  factory PlaybackPreferences.fromJson(Map<String, dynamic> json) =>
      PlaybackPreferences(
        prepareNext: json['prepareNext'] != false,
        balance: json['balance'] == true,
        crossfade: json['crossfade'] == true,
        seconds: json['seconds'] is num
            ? (json['seconds'] as num).round().clamp(1, 6)
            : 3,
      );
}

class PlaybackPreferencesController extends Notifier<PlaybackPreferences> {
  static const key = 'music_playback_preferences_v1';
  Future<void> _pending = Future.value();
  @override
  PlaybackPreferences build() {
    try {
      return PlaybackPreferences.fromJson(
        jsonDecode(ref.watch(sharedPreferencesProvider).getString(key) ?? '{}')
            as Map<String, dynamic>,
      );
    } catch (_) {
      return const PlaybackPreferences();
    }
  }

  Future<void> change(Map<String, Object> patch) {
    state = PlaybackPreferences.fromJson({...state.toJson(), ...patch});
    final encoded = jsonEncode(state.toJson());
    final preferences = ref.read(sharedPreferencesProvider);
    final write = _pending.then((_) async {
      if (!await preferences.setString(key, encoded)) {
        throw StateError('播放设置未保存');
      }
    });
    _pending = write.catchError((Object _) {});
    return write;
  }
}

final playbackPreferencesProvider =
    NotifierProvider<PlaybackPreferencesController, PlaybackPreferences>(
      PlaybackPreferencesController.new,
    );
