import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/persistence/app_preferences.dart';
import '../data/music_platform_api.dart';
import '../domain/platform_session.dart';
import '../music_platform_providers.dart';
import 'fallback/lx_source_catalog.dart';

enum NeteaseSourceStrategy { ordered, highestQuality }

/// These are anonymous adapters, not additional signed-in platform accounts.
/// Keep the public ID stable: persisted source preferences must survive upgrades.
enum NeteasePublicSource {
  kugou('酷狗', true),
  kuwo('酷我', true),
  gdstudio('GD Studio', false),
  bilibili('B站音频', true),
  bilivideo('B站视频音轨', true),
  bodian('波点', false),
  youtube('YouTube', false),
  lxChangqing('长青 · changqing', true, LxMusicSource.changqing),
  lxFish('Fish · fish', true, LxMusicSource.fish),
  lxHelloworld('HelloWorld · helloworld', true, LxMusicSource.helloworld),
  lxHuanyin('幻音 · huanyin', true, LxMusicSource.huanyin),
  lxHuibq('Huibq · huibq', true, LxMusicSource.huibq),
  lxHyw('HYW · hyw', true, LxMusicSource.hyw),
  lxJiexiang('杰翔 · jiexiang', true, LxMusicSource.jiexiang),
  lxLx('LX · lx', true, LxMusicSource.lx),
  lxQdy('全豆要 · qdy', true, LxMusicSource.qdy),
  lxXinghai('星海 · xinghai', true, LxMusicSource.xinghai),
  lxYuningxi('玉宁熙 · yuningxi', true, LxMusicSource.yuningxi);

  const NeteasePublicSource(this.label, this.available, [this.lx]);
  final String label;
  final bool available;
  final LxMusicSource? lx;
  String get note => lx != null
      ? '按歌曲检测完整音频；仅传歌曲信息，不发送账号凭据'
      : switch (this) {
          NeteasePublicSource.gdstudio => '平台暂不支持：服务当前不接受网易云来源',
          NeteasePublicSource.bilibili ||
          NeteasePublicSource.bilivideo => '匿名访问，匹配不足或地区限制时跳过',
          NeteasePublicSource.bodian => '平台暂不支持：匿名完整播放链路尚未验证',
          NeteasePublicSource.youtube => '平台暂不支持：地区及动态解析条件尚未验证',
          _ => '匿名获取，不发送网易云账号凭据',
        };
}

class NeteasePlaybackOptions {
  const NeteasePlaybackOptions({
    this.strategy = NeteaseSourceStrategy.ordered,
    this.lossless = true,
    this.minimumBitrate = 0,
    this.cache = true,
    this.diagnostics = false,
    this.enabledSources = const {
      NeteasePublicSource.kugou,
      NeteasePublicSource.kuwo,
      NeteasePublicSource.bilibili,
      NeteasePublicSource.bilivideo,
      NeteasePublicSource.lxChangqing,
      NeteasePublicSource.lxFish,
      NeteasePublicSource.lxHelloworld,
      NeteasePublicSource.lxHuanyin,
      NeteasePublicSource.lxHuibq,
      NeteasePublicSource.lxHyw,
      NeteasePublicSource.lxJiexiang,
      NeteasePublicSource.lxLx,
      NeteasePublicSource.lxQdy,
      NeteasePublicSource.lxXinghai,
      NeteasePublicSource.lxYuningxi,
    },
  });
  final NeteaseSourceStrategy strategy;
  final bool lossless, cache, diagnostics;
  final int minimumBitrate;
  final Set<NeteasePublicSource> enabledSources;
  NeteasePlaybackOptions copyWith({
    NeteaseSourceStrategy? strategy,
    bool? lossless,
    int? minimumBitrate,
    bool? cache,
    bool? diagnostics,
    Set<NeteasePublicSource>? enabledSources,
  }) => NeteasePlaybackOptions(
    strategy: strategy ?? this.strategy,
    lossless: lossless ?? this.lossless,
    minimumBitrate: minimumBitrate ?? this.minimumBitrate,
    cache: cache ?? this.cache,
    diagnostics: diagnostics ?? this.diagnostics,
    enabledSources: Set.unmodifiable(enabledSources ?? this.enabledSources),
  );
  Map<String, Object?> toJson() => {
    'strategy': strategy.name,
    'lossless': lossless,
    'minimumBitrate': minimumBitrate,
    'cache': cache,
    'diagnostics': diagnostics,
    // Migrate defaults once; preserve later explicit disabling on restart.
    'lxSourcesVersion': 1,
    'sources': enabledSources.map((s) => s.name).toList(),
  };
  factory NeteasePlaybackOptions.fromJson(Map<String, dynamic> value) {
    const defaults = NeteasePlaybackOptions();
    final sources = value['sources'];
    final bitrate = value['minimumBitrate'];
    return NeteasePlaybackOptions(
      strategy:
          NeteaseSourceStrategy.values
              .where((s) => s.name == value['strategy'])
              .firstOrNull ??
          defaults.strategy,
      lossless: value['lossless'] is bool
          ? value['lossless']
          : defaults.lossless,
      cache: value['cache'] is bool ? value['cache'] : defaults.cache,
      diagnostics: value['diagnostics'] == true,
      minimumBitrate: {0, 128000, 192000, 320000}.contains(bitrate)
          ? bitrate
          : 0,
      enabledSources: sources is List
          ? Set.unmodifiable(
              NeteasePublicSource.values.where(
                (s) =>
                    s.available &&
                    (sources.contains(s.name) ||
                        (value['lxSourcesVersion'] != 1 && s.lx != null)),
              ),
            )
          : defaults.enabledSources,
    );
  }
}

final neteasePlaybackOptionsProvider =
    NotifierProvider<NeteasePlaybackOptionsController, NeteasePlaybackOptions>(
      NeteasePlaybackOptionsController.new,
    );

class NeteasePlaybackOptionsController
    extends Notifier<NeteasePlaybackOptions> {
  static const key = 'netease_playback_options_v1';
  @override
  NeteasePlaybackOptions build() {
    try {
      return NeteasePlaybackOptions.fromJson(
        jsonDecode(ref.watch(sharedPreferencesProvider).getString(key) ?? '{}'),
      );
    } catch (_) {
      return const NeteasePlaybackOptions();
    }
  }

  Future<void> save(NeteasePlaybackOptions options) async {
    if (!await ref
        .read(sharedPreferencesProvider)
        .setString(key, jsonEncode(options.toJson()))) {
      throw const MusicPlatformException('播放设置未保存，请重试');
    }
    if (ref.mounted) state = options;
  }
}

class NeteaseLocalMembershipSettings {
  const NeteaseLocalMembershipSettings({
    this.accounts = const {},
    this.allowedUids = const {},
  });
  final Map<String, bool> accounts;
  final Set<String> allowedUids;
  bool enabledFor(String uid) =>
      uid.isNotEmpty &&
      (accounts[uid] ?? true) &&
      (allowedUids.isEmpty || allowedUids.contains(uid));
}

/// Local presentation policy. Never mutate secure sessions, authenticated API
/// responses or playback permissions received from NetEase's servers.
final neteaseLocalMembershipSettingsProvider =
    NotifierProvider<
      NeteaseLocalMembershipController,
      NeteaseLocalMembershipSettings
    >(NeteaseLocalMembershipController.new);
final neteaseLocalSvipProvider = Provider<bool>((ref) {
  final account = ref.watch(platformAccountProvider).value;
  return account?.platform == MusicPlatform.netease &&
      ref
          .watch(neteaseLocalMembershipSettingsProvider)
          .enabledFor(account!.userId);
});

class NeteaseLocalMembershipController
    extends Notifier<NeteaseLocalMembershipSettings> {
  static const key = 'netease_local_membership_v1';
  Future<void> _writes = Future.value();
  @override
  NeteaseLocalMembershipSettings build() {
    try {
      final value =
          jsonDecode(
                ref.watch(sharedPreferencesProvider).getString(key) ?? '{}',
              )
              as Map;
      return NeteaseLocalMembershipSettings(
        accounts: {
          for (final entry in (value['accounts'] as Map? ?? {}).entries)
            if (entry.value is bool) '${entry.key}': entry.value as bool,
        },
        allowedUids: (value['uids'] as List? ?? [])
            .whereType<String>()
            .where((s) => RegExp(r'^\d+$').hasMatch(s))
            .toSet(),
      );
    } catch (_) {
      return const NeteaseLocalMembershipSettings();
    }
  }

  Future<void> setEnabled(String uid, bool enabled) => _update(
    (previous) => NeteaseLocalMembershipSettings(
      accounts: {...previous.accounts, uid: enabled},
      allowedUids: previous.allowedUids,
    ),
  );
  Future<void> setAllowedUids(String input) {
    final uids = input
        .split(RegExp(r'[,，;；\s]+'))
        .where((s) => s.isNotEmpty)
        .toSet();
    if (uids.length > 100 ||
        uids.any((s) => !RegExp(r'^\d{1,20}$').hasMatch(s))) {
      throw const MusicPlatformException('请填写有效 UID，使用逗号分隔，最多 100 个');
    }
    return _update(
      (previous) => NeteaseLocalMembershipSettings(
        accounts: previous.accounts,
        allowedUids: uids,
      ),
    );
  }

  /// Serialize mutations and read the latest state inside the queue. Switching
  /// accounts while another page saves must not discard that account's choice.
  Future<void> _update(
    NeteaseLocalMembershipSettings Function(NeteaseLocalMembershipSettings)
    change,
  ) {
    final operation = _writes.catchError((Object _) {}).then((_) async {
      if (!ref.mounted) return;
      final value = change(state);
      if (!await ref
          .read(sharedPreferencesProvider)
          .setString(
            key,
            jsonEncode({
              'accounts': value.accounts,
              'uids': value.allowedUids.toList(),
            }),
          )) {
        throw const MusicPlatformException('本地会员设置未保存，请重试');
      }
      if (ref.mounted) state = value;
    });
    _writes = operation;
    return operation;
  }
}
