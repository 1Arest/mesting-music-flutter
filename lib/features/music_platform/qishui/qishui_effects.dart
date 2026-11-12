import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/audio/playback_providers.dart';
import '../../../shared/models/track.dart';
import '../domain/platform_session.dart';
import '../music_platform_providers.dart';
import 'qishui_api.dart';
import 'qishui_models.dart';
import 'qishui_repository.dart';

class QishuiEffect {
  const QishuiEffect(this.key, this.name, this.config);
  final String key, name, config;
}

Future<List<QishuiEffect>> loadQishuiEffects() async {
  final value = jsonDecode(
    await rootBundle.loadString('assets/data/qishui-effects.json'),
  );
  return sodaRows(sodaMap(value)['effects'])
      .map(
        (v) => QishuiEffect(
          '${v['key']}',
          '${v['name']}',
          jsonEncode(v['config']),
        ),
      )
      .toList();
}

/// Require an explicit current, unexpired grant for this exact effect key.
/// Generic VIP/activity membership is not substituted for an effect grant.
Map<String, dynamic>? qishuiEffectGrant(
  Map<String, dynamic> commerce,
  String key,
) {
  final detail = sodaMap(
    sodaMap(commerce['benefit_base'])['audio_effect'],
  )['audio_effect_detail'];
  final grant = detail is Map
      ? sodaMap(detail[key])
      : sodaRows(detail).where((v) => v['key'] == key).firstOrNull;
  if (grant == null || grant.isEmpty) return null;
  final now = sodaInt(sodaMap(commerce['status_info'])['now']);
  if (now <= 0 ||
      sodaInt(grant['expire_time']) <= now ||
      grant['stage'] != 'free') {
    return null;
  }
  if (grant['security_config_required'] == true &&
      '${grant['config'] ?? ''}'.isEmpty) {
    return null;
  }
  return grant;
}

final qishuiEffectsProvider = Provider<QishuiEffectCoordinator>((ref) {
  final handler = ref.read(audioHandlerProvider);
  final coordinator = QishuiEffectCoordinator(
    send: handler.setQishuiAudioEffect,
    status: handler.qishuiAudioEffectStatus,
    current: () =>
        ref.mounted &&
        ref.read(platformAccountProvider).value?.platform ==
            MusicPlatform.qishui &&
        handler.trackForId(handler.mediaItem.value?.id ?? '')?.source ==
            TrackSource.qishui,
  );
  ref.listen(
    platformAccountProvider.select((a) => (a.value?.ownerId, a.value?.token)),
    (_, _) => coordinator.reset(),
  );
  ref.listen(currentMediaItemProvider, (_, value) {
    final track = value.value == null
        ? null
        : handler.trackForId(value.value!.id);
    if (track?.source != TrackSource.qishui) coordinator.reset();
  });
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

/// All native configuration writes share a queue and generation. A late grant
/// read from a previous account can never re-enable an effect after reset.
class QishuiEffectCoordinator {
  QishuiEffectCoordinator({
    required this.send,
    required this.status,
    required this.current,
  });
  final Future<Map<String, Object?>> Function(String?) send;
  final Future<Map<String, Object?>> Function() status;
  final bool Function() current;
  Future<void> _pending = Future.value();
  int _epoch = 0;
  bool _disposed = false;
  Timer? _expiry;
  String? selectedKey;
  Future<Map<String, Object?>> _write(String? json, int epoch) {
    final operation = _pending.then((_) async {
      if (json != null && (_disposed || epoch != _epoch || !current())) {
        throw const QishuiException('账号或歌曲已变化，请重新选择音效');
      }
      return send(json);
    });
    _pending = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Future<Map<String, Object?>> select(
    QishuiEffect effect,
    QishuiRepository music,
  ) async {
    final epoch = ++_epoch;
    final commerce = await music.commerce();
    if (epoch != _epoch || !music.current || _disposed) {
      throw const QishuiException('音效选择已取消');
    }
    final grant = qishuiEffectGrant(commerce, effect.key);
    if (grant == null) throw const QishuiException('汽水未确认此音效的当前使用资格');
    final json =
        grant['config'] is String && (grant['config'] as String).isNotEmpty
        ? grant['config'] as String
        : effect.config;
    final result = await _write(json, epoch);
    if (epoch != _epoch || !music.current) {
      throw const QishuiException('音效选择已取消');
    }
    if (result['configured'] != true ||
        '${result['failure'] ?? ''}'.isNotEmpty) {
      throw QishuiException(switch (result['failure']) {
        'unsupported_abi' => '当前设备不支持这套汽水官版音效',
        'unsupported_page_size' => '当前设备的内存页规格不支持这套官版音效，请使用普通播放',
        'player_inactive' => '请先播放一首汽水歌曲，再设置音效',
        _ => '汽水官版音效未能启用，已保留普通播放',
      });
    }
    selectedKey = effect.key;
    _expiry?.cancel();
    _expiry = Timer(
      Duration(
        seconds:
            sodaInt(grant['expire_time']) -
            sodaInt(sodaMap(commerce['status_info'])['now']),
      ),
      reset,
    );
    return result;
  }

  Future<void> off() async {
    _expiry?.cancel();
    selectedKey = null;
    await _write(null, ++_epoch);
  }

  void reset() {
    _expiry?.cancel();
    selectedKey = null;
    unawaited(
      _write(null, ++_epoch).then<void>((_) {}, onError: (Object _) {}),
    );
  }

  void dispose() {
    _disposed = true;
    reset();
  }
}
