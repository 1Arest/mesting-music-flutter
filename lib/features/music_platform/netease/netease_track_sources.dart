import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../music_platform_providers.dart';
import 'fallback/lx_source_catalog.dart';

/// Explicit adapters include the retained Concept login and anonymous sources.
/// A manual choice is scoped to this account/session and recording.
enum NeteaseTrackSource {
  automatic('自动', null),
  official('网易云官方', null),
  accountKugou('酷狗概念版账号', '酷狗概念版账号'),
  kugou('酷狗公开音源', '酷狗公开音源'),
  kuwo('酷我公开音源', '酷我公开音源'),
  bilibili('B站音频', 'B站音频'),
  bilivideo('B站视频音轨', 'B站视频音轨'),
  bugpk('BugPk', 'BugPk · 网易云同曲'),
  lxChangqing('长青 · changqing', 'LX · changqing', LxMusicSource.changqing),
  lxFish('Fish · fish', 'LX · fish', LxMusicSource.fish),
  lxHelloworld(
    'HelloWorld · helloworld',
    'LX · helloworld',
    LxMusicSource.helloworld,
  ),
  lxHuanyin('幻音 · huanyin', 'LX · huanyin', LxMusicSource.huanyin),
  lxHuibq('Huibq · huibq', 'LX · huibq', LxMusicSource.huibq),
  lxHyw('HYW · hyw', 'LX · hyw', LxMusicSource.hyw),
  lxJiexiang('杰翔 · jiexiang', 'LX · jiexiang', LxMusicSource.jiexiang),
  lxLx('LX · lx', 'LX · lx', LxMusicSource.lx),
  lxQdy('全豆要 · qdy', 'LX · qdy', LxMusicSource.qdy),
  lxXinghai('星海 · xinghai', 'LX · xinghai', LxMusicSource.xinghai),
  lxYuningxi('玉宁熙 · yuningxi', 'LX · yuningxi', LxMusicSource.yuningxi);

  const NeteaseTrackSource(this.label, this.adapter, [this.lx]);
  final String label;
  final String? adapter;
  final LxMusicSource? lx;
}

final neteaseTrackSourcesProvider =
    NotifierProvider<NeteaseTrackSources, Map<String, NeteaseTrackSource>>(
      NeteaseTrackSources.new,
    );

class NeteaseTrackSources extends Notifier<Map<String, NeteaseTrackSource>> {
  @override
  Map<String, NeteaseTrackSource> build() {
    ref.watch(
      platformAccountProvider.select((a) => (a.value?.ownerId, a.value?.token)),
    );
    return const {};
  }

  void select(String trackId, NeteaseTrackSource source) {
    state = {...state, trackId: source};
  }
}
