import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Same five frequency regions as md3Music v6.1.0. Hardware bands are queried
/// from Android and mapped by their actual center frequency, never assumed.
const musicEqualizerPresets = <String, List<double>>{
  '正常': [0, 0, 0, 0, 0],
  '流行': [-1, 2, 4, 2, -1],
  '摇滚': [4, -1, 0, 3, 4],
  '爵士': [3, 2, -1, 1, 3],
  '古典': [4, 0, -1, 2, 4],
  '重低音': [6, 0, 0, 0, 0],
  '高音增强': [0, 0, 0, 4, 6],
  '人声': [-2, 2, 4, 3, -1],
  '电子': [4, -2, 0, 3, 5],
};
const _defaultCenters = [60000, 230000, 910000, 3600000, 14000000];
const musicEqualizerPreferenceKey = 'music_audio_equalizer_v1';

class EqualizerParameters {
  const EqualizerParameters({
    required this.frequencies,
    required this.levels,
    required this.minimum,
    required this.maximum,
  });
  final List<int> frequencies;
  final List<double> levels;
  final double minimum, maximum;
  factory EqualizerParameters.fromMap(Map<Object?, Object?> raw) {
    final frequencies = (raw['frequencies'] as List)
        .map((v) => (v as num).toInt())
        .toList();
    final levels = (raw['levels'] as List)
        .map((v) => (v as num).toDouble() / 100)
        .toList();
    final minimum = (raw['minimum'] as num).toDouble() / 100;
    final maximum = (raw['maximum'] as num).toDouble() / 100;
    if (frequencies.isEmpty ||
        frequencies.length > 32 ||
        frequencies.length != levels.length ||
        frequencies.any((f) => f <= 0) ||
        minimum >= maximum) {
      throw const FormatException('Invalid equalizer parameters');
    }
    return EqualizerParameters(
      frequencies: frequencies,
      levels: levels,
      minimum: minimum,
      maximum: maximum,
    );
  }
}

abstract interface class MusicEqualizerBridge {
  Future<EqualizerParameters> bind(int sessionId);
  Future<EqualizerParameters> apply(
    int sessionId, {
    required bool enabled,
    required List<double> levels,
  });
  Future<void> release();
}

class AndroidMusicEqualizerBridge implements MusicEqualizerBridge {
  static const channel = MethodChannel('com.mesting.music/equalizer');
  @override
  Future<EqualizerParameters> bind(int sessionId) async =>
      EqualizerParameters.fromMap(
        (await channel
            .invokeMapMethod<Object?, Object?>('bind', {'sessionId': sessionId})
            .timeout(const Duration(seconds: 5)))!,
      );
  @override
  Future<EqualizerParameters> apply(
    int sessionId, {
    required bool enabled,
    required List<double> levels,
  }) async => EqualizerParameters.fromMap(
    (await channel
        .invokeMapMethod<Object?, Object?>('apply', {
          'sessionId': sessionId,
          'enabled': enabled,
          'levels': levels.map((v) => (v * 100).round()).toList(),
        })
        .timeout(const Duration(seconds: 5)))!,
  );
  @override
  Future<void> release() async {
    await channel
        .invokeMethod<void>('release')
        .timeout(const Duration(seconds: 5));
  }
}

class MusicEqualizerState {
  const MusicEqualizerState({
    this.enabled = false,
    this.bound = false,
    this.binding = false,
    this.preset = '正常',
    this.frequencies = _defaultCenters,
    this.levels = const [0, 0, 0, 0, 0],
    this.minimum = -15,
    this.maximum = 15,
    this.effectId,
    this.effectName,
    this.message,
  });
  final bool enabled, bound, binding;
  final String preset;
  final List<int> frequencies;
  final List<double> levels;
  final double minimum, maximum;
  final String? effectId, effectName, message;
  MusicEqualizerState copy({
    bool? enabled,
    bool? bound,
    bool? binding,
    String? preset,
    List<int>? frequencies,
    List<double>? levels,
    double? minimum,
    double? maximum,
    String? effectId,
    String? effectName,
    String? message,
    bool clearEffect = false,
  }) => MusicEqualizerState(
    enabled: enabled ?? this.enabled,
    bound: bound ?? this.bound,
    binding: binding ?? this.binding,
    preset: preset ?? this.preset,
    frequencies: frequencies ?? this.frequencies,
    levels: List.unmodifiable(levels ?? this.levels),
    minimum: minimum ?? this.minimum,
    maximum: maximum ?? this.maximum,
    effectId: clearEffect ? null : effectId ?? this.effectId,
    effectName: clearEffect ? null : effectName ?? this.effectName,
    message: message,
  );
}

/// Persists desired settings; actual attachment is a separate visible state.
/// The controller never owns playback or recreates an audio source. Native
/// errors preserve the previous saved choice and remain visible for retry.
class MusicEqualizerController extends ChangeNotifier {
  MusicEqualizerController({
    required this.bridge,
    required this.preferences,
    required Stream<int?> sessions,
    int? currentSession,
  }) {
    _restore();
    _subscription = sessions.listen(_sessionChanged);
    _sessionChanged(currentSession);
  }
  final MusicEqualizerBridge bridge;
  final SharedPreferences preferences;
  MusicEqualizerState _state = const MusicEqualizerState();
  MusicEqualizerState get state => _state;
  late final StreamSubscription<int?> _subscription;
  Future<void> _tail = Future.value();
  Timer? _previewTimer;
  int? _session;
  int _revision = 0;
  bool _disposed = false;

  void _publish(MusicEqualizerState value) {
    if (!_disposed) {
      _state = value;
      notifyListeners();
    }
  }

  void _restore() {
    try {
      final raw =
          jsonDecode(preferences.getString(musicEqualizerPreferenceKey) ?? '{}')
              as Map;
      final preset = raw['preset'] is String ? raw['preset'] as String : '正常';
      final frequencies = (raw['frequencies'] as List?)
          ?.map((v) => (v as num).toInt())
          .toList();
      final levels = (raw['levels'] as List?)
          ?.map((v) => (v as num).toDouble())
          .toList();
      final valid =
          frequencies != null &&
          levels != null &&
          frequencies.length == levels.length &&
          frequencies.isNotEmpty &&
          frequencies.length <= 32 &&
          frequencies.every((v) => v > 0) &&
          levels.every((v) => v.isFinite && v.abs() <= 30);
      _state = MusicEqualizerState(
        enabled: raw['enabled'] == true,
        preset: preset,
        frequencies: valid ? frequencies : _defaultCenters,
        levels: valid ? levels : const [0, 0, 0, 0, 0],
        effectId: raw['effectId'] as String?,
        effectName: raw['effectName'] as String?,
      );
    } on Object {
      _state = const MusicEqualizerState();
    }
  }

  void _sessionChanged(int? value) {
    if (_session == value) return;
    _session = value != null && value > 0 ? value : null;
    _revision++;
    _previewTimer?.cancel();
    _previewTimer = null;
    _publish(_state.copy(bound: false, binding: false));
    unawaited(bridge.release().catchError((Object _) {}));
    if (_state.enabled && _session != null) unawaited(bind());
  }

  Future<void> _serialize(Future<void> Function() work) {
    final result = _tail.then((_) async {
      if (!_disposed) await work();
    });
    _tail = result.catchError((Object _) {});
    return result;
  }

  List<double> _levelsFor(EqualizerParameters parameters) {
    final preset = musicEqualizerPresets[_state.preset];
    return parameters.frequencies.map((f) {
      double value;
      if (preset != null) {
        final hz = f / 1000;
        final zone = hz < 250
            ? 0
            : hz < 500
            ? 1
            : hz < 2000
            ? 2
            : hz < 6000
            ? 3
            : 4;
        value = preset[zone];
      } else {
        var closest = 0;
        var distance = double.infinity;
        for (var i = 0; i < _state.frequencies.length; i++) {
          final delta = (math.log(f) - math.log(_state.frequencies[i])).abs();
          if (delta < distance) {
            distance = delta;
            closest = i;
          }
        }
        value = _state.levels[closest];
      }
      return value.clamp(parameters.minimum, parameters.maximum).toDouble();
    }).toList();
  }

  Future<void> bind() => _serialize(_bind);
  Future<void> _bind() async {
    if (_state.bound || _disposed) return;
    final session = _session, revision = _revision;
    if (session == null) {
      _publish(_state.copy(message: '播放一首歌曲后，均衡器会自动生效。'));
      return;
    }
    _publish(_state.copy(binding: true));
    try {
      final parameters = await bridge.bind(session);
      if (_disposed || revision != _revision) return;
      final levels = _levelsFor(parameters);
      final actual = await bridge.apply(
        session,
        enabled: _state.enabled,
        levels: levels,
      );
      if (_disposed || revision != _revision) return;
      _publish(
        _state.copy(
          bound: true,
          binding: false,
          frequencies: actual.frequencies,
          levels: actual.levels,
          minimum: actual.minimum,
          maximum: actual.maximum,
        ),
      );
    } on Object {
      if (!_disposed && revision == _revision) {
        _publish(
          _state.copy(
            bound: false,
            binding: false,
            message: '设备均衡器暂不可用。请播放音乐后重试，或关闭均衡器。',
          ),
        );
      }
    }
  }

  Future<bool> _save(MusicEqualizerState value) => preferences.setString(
    musicEqualizerPreferenceKey,
    jsonEncode({
      'enabled': value.enabled,
      'preset': value.preset,
      'frequencies': value.frequencies,
      'levels': value.levels,
      'effectId': value.effectId,
      'effectName': value.effectName,
    }),
  );
  Future<void> _commit(MusicEqualizerState value) async {
    final previous = _state, revision = _revision, session = _session;
    try {
      var applied = value;
      if (session != null && previous.bound) {
        final actual = await bridge.apply(
          session,
          enabled: value.enabled,
          levels: value.levels,
        );
        if (_disposed || revision != _revision) return;
        applied = value.copy(levels: actual.levels);
      }
      if (!await _save(applied)) throw StateError('Preference write failed');
      if (_disposed || revision != _revision) return;
      _publish(
        applied.copy(
          message: applied.enabled && !applied.bound ? '已保存，播放音乐时生效。' : null,
        ),
      );
    } on Object {
      if (session != null && previous.bound && revision == _revision) {
        try {
          await bridge.apply(
            session,
            enabled: previous.enabled,
            levels: previous.levels,
          );
        } on Object {
          /* Device state will be retried explicitly. */
        }
      }
      if (!_disposed && revision == _revision) {
        _publish(previous.copy(message: '设置未能应用或保存，请重试。'));
      }
    }
  }

  Future<void> setEnabled(bool enabled) => _serialize(() async {
    _previewTimer?.cancel();
    _previewTimer = null;
    if (enabled && !_state.bound && _session != null) await _bind();
    if (enabled && _session != null && !_state.bound) return;
    await _commit(_state.copy(enabled: enabled));
  });
  Future<void> selectPreset(
    String name, {
    String? effectId,
    String? effectName,
  }) => _serialize(() async {
    if (!musicEqualizerPresets.containsKey(name)) return;
    _previewTimer?.cancel();
    _previewTimer = null;
    if (!_state.bound && _session != null) await _bind();
    if (_session != null && !_state.bound) return;
    final parameters = EqualizerParameters(
      frequencies: _state.frequencies,
      levels: _state.levels,
      minimum: _state.minimum,
      maximum: _state.maximum,
    );
    final previous = _state;
    _state = _state.copy(preset: name);
    final levels = _levelsFor(parameters);
    _state = previous;
    await _commit(
      _state.copy(
        enabled: true,
        preset: name,
        levels: levels,
        effectId: effectId,
        effectName: effectName,
        clearEffect: effectId == null,
      ),
    );
  });

  /// At most one native update per 40ms while dragging, one persistent commit
  /// on release. This keeps slider feedback local and avoids a disk write/tick.
  void previewBand(int index, double value) {
    if (!_state.enabled ||
        !_state.bound ||
        index < 0 ||
        index >= _state.levels.length) {
      return;
    }
    final levels = [..._state.levels];
    levels[index] = value.clamp(_state.minimum, _state.maximum);
    _publish(_state.copy(levels: levels, preset: '自定义', clearEffect: true));
    _previewTimer ??= Timer(const Duration(milliseconds: 40), () {
      _previewTimer = null;
      unawaited(
        _serialize(() async {
          final session = _session, revision = _revision;
          if (session == null || !_state.bound) return;
          try {
            await bridge.apply(
              session,
              enabled: _state.enabled,
              levels: _state.levels,
            );
          } on Object {
            if (!_disposed && revision == _revision) {
              _publish(_state.copy(message: '设备暂未接受该频段，请松开后重试。'));
            }
          }
        }),
      );
    });
  }

  Future<void> commitBands() => _serialize(() async {
    _previewTimer?.cancel();
    _previewTimer = null;
    await _commit(_state);
  });
  Future<void> clearEffect() => _serialize(() async {
    await _commit(
      _state.copy(
        preset: '正常',
        levels: List.filled(_state.levels.length, 0),
        clearEffect: true,
      ),
    );
  });
  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _previewTimer?.cancel();
    unawaited(_subscription.cancel());
    unawaited(bridge.release().catchError((Object _) {}));
    super.dispose();
  }
}
