import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:mesting_music/core/persistence/app_preferences.dart';
import 'package:mesting_music/features/search/search_providers.dart';
import 'package:mesting_music/features/search/data/music_search_repository.dart';
import 'package:mesting_music/features/search/domain/music_source.dart';
import 'package:mesting_music/shared/models/track.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _localTrack = Track(
  id: 'local_1',
  title: '晴天',
  artist: '周杰伦',
  album: '本地收藏',
  duration: Duration(minutes: 4),
  audioAsset: 'assets/audio/local.mp3',
  coverAsset: 'assets/images/covers/local.jpg',
  lyricsAsset: 'assets/lyrics/local.lrc',
);

const _onlineTrack = Track(
  id: 'audius_1',
  title: 'Sunny Day',
  artist: 'Remote Artist',
  album: 'Audius',
  duration: Duration(minutes: 3),
  audioAsset: 'https://example.com/stream',
  coverAsset: 'https://example.com/cover.jpg',
  lyricsAsset: '',
  source: TrackSource.audius,
  provider: 'Audius',
);

const _chenLiTrack = Track(
  id: 'netease_chen_li',
  title: '虚拟',
  artist: '陈粒',
  album: '小梦大半',
  duration: Duration(minutes: 4),
  audioAsset: 'https://example.com/chen-li.mp3',
  coverAsset: 'https://example.com/chen-li.jpg',
  lyricsAsset: '',
  source: TrackSource.netease,
  provider: '网易云 Enhanced',
);

const _romanChenLiTrack = Track(
  id: 'roman_chen_li',
  title: '水边轻歌',
  artist: 'CHENLI',
  album: '同名英文艺人',
  duration: Duration(minutes: 4),
  audioAsset: 'https://example.com/roman-chen-li.mp3',
  coverAsset: '',
  lyricsAsset: '',
  source: TrackSource.audius,
  provider: 'Audius',
);

const _unrelatedTrack = Track(
  id: 'unrelated',
  title: '太湖船',
  artist: 'Remote Artist',
  album: '其他结果',
  duration: Duration(minutes: 3),
  audioAsset: 'https://example.com/unrelated.mp3',
  coverAsset: '',
  lyricsAsset: '',
  source: TrackSource.audius,
  provider: 'Audius',
);

void main() {
  test('合并本地与在线结果，并在有效期内复用缓存', () async {
    final source = _ImmediateSource([_onlineTrack]);
    final repository = MusicSearchRepository(
      localTracks: [_localTrack],
      sources: [source],
    );

    final first = await repository.search('晴天');
    final second = await repository.search('晴天');
    final refreshed = await repository.search('晴天', allowCache: false);

    expect(first.localTracks, [_localTrack]);
    expect(first.onlineTracks, [_onlineTrack]);
    expect(first.fromCache, isFalse);
    expect(second.fromCache, isTrue);
    expect(refreshed.fromCache, isFalse);
    expect(source.calls, 2);
  });

  test('新搜索会真正取消仍在进行的旧请求', () async {
    final source = _BlockingSource();
    final repository = MusicSearchRepository(
      localTracks: const [],
      sources: [source],
    );

    final first = repository.search('first');
    await source.started.future;
    final second = repository.search('second');

    await expectLater(first, throwsA(isA<http.RequestAbortedException>()));
    repository.cancelActiveSearch();
    await expectLater(second, throwsA(isA<http.RequestAbortedException>()));
  });

  test('单个来源失败时保留其他来源结果并给出提示', () async {
    final repository = MusicSearchRepository(
      localTracks: const [],
      sources: [
        _ImmediateSource([_onlineTrack]),
        const _FailingSource(),
      ],
    );

    final result = await repository.search('music');

    expect(result.onlineTracks, [_onlineTrack]);
    expect(result.warnings.single, contains('失败来源'));
  });

  test('同名歌曲优先主来源，但主来源不可播时使用可播放补充源', () async {
    const unavailablePrimary = Track(
      id: 'kugou_same',
      title: '同一首歌',
      artist: '同一歌手',
      album: '主来源',
      duration: Duration(minutes: 3),
      audioAsset: '',
      coverAsset: '',
      lyricsAsset: '',
      source: TrackSource.kugou,
      provider: '酷狗概念版',
    );
    const playableFallback = Track(
      id: 'netease_same',
      title: '同一首歌',
      artist: '同一歌手',
      album: '补充来源',
      duration: Duration(minutes: 3),
      audioAsset: 'https://example.com/song.mp3',
      coverAsset: '',
      lyricsAsset: '',
      source: TrackSource.netease,
      provider: '网易云 Enhanced',
    );
    final repository = MusicSearchRepository(
      localTracks: const [],
      sources: [
        _ImmediateSource([unavailablePrimary]),
        _ImmediateSource([playableFallback]),
      ],
    );

    final result = await repository.search('同一首歌');

    expect(result.onlineTracks, [playableFallback]);
  });

  test('完整拼音优先返回对应中文歌手且不增加来源调用', () async {
    final source = _ImmediateSource([
      _romanChenLiTrack,
      _unrelatedTrack,
      _chenLiTrack,
    ]);
    final repository = MusicSearchRepository(
      localTracks: const [],
      sources: [source],
    );

    final result = await repository.search('chenli');

    expect(result.onlineTracks.first, _chenLiTrack);
    expect(result.onlineTracks[1], _romanChenLiTrack);
    expect(source.calls, 1);
  });

  test('首拼可以匹配中文歌手并保持单次来源调用', () async {
    final source = _ImmediateSource([
      _unrelatedTrack,
      _romanChenLiTrack,
      _chenLiTrack,
    ]);
    final repository = MusicSearchRepository(
      localTracks: const [],
      sources: [source],
    );

    final result = await repository.search('cl');

    expect(result.onlineTracks.first, _chenLiTrack);
    expect(source.calls, 1);
  });

  test('一字误差可以把近似中文结果排到无关结果之前', () async {
    final source = _ImmediateSource([_unrelatedTrack, _chenLiTrack]);
    final repository = MusicSearchRepository(
      localTracks: const [],
      sources: [source],
    );

    final result = await repository.search('陈立');

    expect(result.onlineTracks.first, _chenLiTrack);
    expect(source.calls, 1);
  });

  test('本地音乐同样支持拼音首拼和拼音轻微输入错误', () async {
    final repository = MusicSearchRepository(
      localTracks: const [_chenLiTrack],
      sources: const [],
    );

    final initials = await repository.search('cl');
    final typo = await repository.search('chenlli');

    expect(initials.localTracks, [_chenLiTrack]);
    expect(typo.localTracks, [_chenLiTrack]);
  });

  test('新查询开始时立即清除上一次的缓存标记', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = MusicSearchRepository(
      localTracks: const [],
      sources: [
        _ImmediateSource([_onlineTrack]),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        musicSearchRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(musicSearchControllerProvider.notifier);
    await controller.submit('music');
    await controller.submit('music');
    expect(container.read(musicSearchControllerProvider).fromCache, isTrue);

    controller.setQuery('next');
    final loading = container.read(musicSearchControllerProvider);
    expect(loading.isLoading, isTrue);
    expect(loading.fromCache, isFalse);
  });
}

class _ImmediateSource implements MusicSource {
  _ImmediateSource(this.tracks);

  final List<Track> tracks;
  int calls = 0;

  @override
  String get id => 'immediate';

  @override
  String get label => '测试来源';

  @override
  bool get isConfigured => true;

  @override
  Future<List<Track>> search(
    String query, {
    int limit = 20,
    Future<void>? abortTrigger,
  }) async {
    calls += 1;
    return tracks;
  }
}

class _BlockingSource implements MusicSource {
  final started = Completer<void>();

  @override
  String get id => 'blocking';

  @override
  String get label => '阻塞来源';

  @override
  bool get isConfigured => true;

  @override
  Future<List<Track>> search(
    String query, {
    int limit = 20,
    Future<void>? abortTrigger,
  }) async {
    if (!started.isCompleted) {
      started.complete();
    }
    await abortTrigger;
    throw http.RequestAbortedException();
  }
}

class _FailingSource implements MusicSource {
  const _FailingSource();

  @override
  String get id => 'failing';

  @override
  String get label => '失败来源';

  @override
  bool get isConfigured => true;

  @override
  Future<List<Track>> search(
    String query, {
    int limit = 20,
    Future<void>? abortTrigger,
  }) {
    throw const MusicSourceException(sourceLabel: '失败来源', message: '暂时无法连接');
  }
}
