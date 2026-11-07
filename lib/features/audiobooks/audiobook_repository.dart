import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/track.dart';
import '../music_platform/data/music_platform_api.dart';
import '../music_platform/data/platform_playback_resolver.dart';
import '../music_platform/domain/platform_session.dart';
import '../music_platform/music_platform_providers.dart';
import 'audiobook_models.dart';

final audiobookRepositoryProvider = Provider<AudiobookRepository>((ref) {
  // A nickname/avatar refresh is not a new authentication epoch.
  ref.watch(
    platformAccountProvider.select(
      (account) => (
        account.value?.userId,
        account.value?.token,
        account.value?.vipToken,
      ),
    ),
  );
  return AudiobookRepository(
    ref.watch(musicPlatformApiProvider),
    ref.read(platformAccountProvider).value,
  );
});

class AudiobookRepository {
  AudiobookRepository(this.api, this.identity);
  final MusicPlatformApi api;
  final PlatformSession? identity;
  void _check() {
    if (api.session?.userId != identity?.userId ||
        api.session?.token != identity?.token) {
      throw const MusicPlatformException('酷狗账号已变化，请重新打开听书');
    }
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String> query = const {},
    Future<void>? abortTrigger,
  }) async {
    _check();
    final result = await api.get(
      path,
      query: query,
      expectedSession: identity,
      abortTrigger: abortTrigger,
    );
    _check();
    return result;
  }

  Future<List<BookCategory>> categories({Future<void>? abortTrigger}) async {
    final rows = bookRows(
      await _get('/longaudio/tag/list', abortTrigger: abortTrigger),
    );
    final categories = <BookCategory>[];
    for (final parent in rows) {
      final id = bookText(parent, ['tag_id']);
      final name = bookText(parent, ['tag_name', 'name']);
      if (id.isNotEmpty && name.isNotEmpty) {
        categories.add(BookCategory(id, name));
      }
      for (final child in bookRows({'data': parent['son']})) {
        final childId = bookText(child, ['tag_id']);
        final childName = bookText(child, ['tag_name', 'name']);
        if (childId.isNotEmpty && childName.isNotEmpty) {
          categories.add(BookCategory(childId, childName));
        }
      }
    }
    final ids = <String>{};
    return categories.where((c) => ids.add(c.id)).toList();
  }

  Future<BookPage<BookAlbum>> albums({
    String category = '906',
    int page = 1,
    Future<void>? abortTrigger,
  }) async {
    final result = await _get(
      '/longaudio/album/list',
      query: {
        'tag_id': category,
        'page': '$page',
        'page_size': '20',
        'free': '1',
      },
      abortTrigger: abortTrigger,
    );
    final rows = bookRows(result);
    final data = MusicPlatformApi.objectMap(result['data']);
    return BookPage(
      rows
          .map(BookAlbum.fromJson)
          .where((a) => a.id.isNotEmpty && a.name.isNotEmpty)
          .toList(),
      hasMore: data['is_end']?.toString() != '1' && rows.length >= 20,
      page: page,
    );
  }

  Future<BookPage<BookAlbum>> search(
    String query, {
    int page = 1,
    Future<void>? abortTrigger,
  }) async {
    final result = await _get(
      '/search/audiobook',
      query: {'keyword': query.trim(), 'page': '$page', 'pagesize': '30'},
      abortTrigger: abortTrigger,
    );
    final rows = bookRows(result);
    final ids = <String>{};
    final albums = rows
        .map(BookAlbum.fromJson)
        .where((a) => a.id.isNotEmpty && a.name.isNotEmpty && ids.add(a.id))
        .toList();
    return BookPage(albums, hasMore: rows.length >= 30, page: page);
  }

  Future<BookAlbum> detail(
    BookAlbum initial, {
    Future<void>? abortTrigger,
  }) async {
    final rows = bookRows(
      await _get(
        '/longaudio/album/detail',
        query: {'album_id': initial.id},
        abortTrigger: abortTrigger,
      ),
    );
    final album = rows
        .map(BookAlbum.fromJson)
        .where((a) => a.id == initial.id)
        .firstOrNull;
    if (album == null) return initial;
    return BookAlbum(
      id: initial.id,
      name: album.name.isEmpty ? initial.name : album.name,
      author: album.author.isEmpty ? initial.author : album.author,
      cover: album.cover.isEmpty ? initial.cover : album.cover,
      intro: album.intro.isEmpty ? initial.intro : album.intro,
      chapterCount: album.chapterCount > 0
          ? album.chapterCount
          : initial.chapterCount,
    );
  }

  Future<BookPage<BookChapter>> chapters(
    BookAlbum album, {
    int page = 1,
    Future<void>? abortTrigger,
  }) async {
    final rows = bookRows(
      await _get(
        '/longaudio/album/audios',
        query: {'album_id': album.id, 'page': '$page', 'pagesize': '50'},
        abortTrigger: abortTrigger,
      ),
    );
    return BookPage(
      rows
          .map((r) => BookChapter.fromJson(r, album))
          .where((c) => c.valid)
          .toList(),
      hasMore: rows.length >= 50,
      page: page,
    );
  }

  /// Refreshed for every play, including restored queues. Purchase/VIP failures
  /// remain failures; a preview URL is never presented as a complete chapter.
  Future<Track> resolve(Track track) async {
    final chapter = bookIdentity(track);
    if (chapter == null || chapter.hash.isEmpty && chapter.mixId.isEmpty) {
      throw const MusicPlatformException('这条听书记录缺少章节标识，请从专辑重新选择');
    }
    final abort = Completer<void>();
    final timer = Timer(const Duration(seconds: 35), () {
      if (!abort.isCompleted) abort.complete();
    });
    try {
      await api.ensureRegisteredDevice();
      _check();
      for (final path in [
        if (identity?.vipToken.isNotEmpty == true) '/song/url/new',
        '/song/url',
      ]) {
        final result = await _get(
          path,
          query: {
            'hash': chapter.hash,
            'album_id': chapter.albumId,
            'album_audio_id': chapter.mixId,
            'quality': '128',
          },
          abortTrigger: abort.future,
        );
        final data = PlatformPlaybackResolver.audioData(result);
        final fail = data['fail_process'];
        final denied = fail is List
            ? fail.isNotEmpty
            : fail != null && '$fail' != '0' && '$fail'.isNotEmpty;
        final media = PlatformPlaybackResolver.mediaUrl(data);
        final preview =
            data['is_preview'] == true ||
            data['is_preview']?.toString() == '1' ||
            data['free_part']?.toString() == '1';
        if (!denied &&
            !preview &&
            media.isNotEmpty &&
            data['priv_status']?.toString() != '0') {
          if (RegExp(
            r'\.(kgs|kgm|kgma|kgg|vpr)$',
          ).hasMatch(Uri.parse(media).path.toLowerCase())) {
            throw const MusicPlatformException('平台返回了当前设备不支持的加密章节格式');
          }
          return track.copyWith(
            audioAsset: media,
            isPreview: false,
            availabilityMessage: '',
            playbackQuality: '128',
          );
        }
      }
      throw const MusicPlatformException('此章节暂不可完整播放，可能需要购买或相应会员权限');
    } finally {
      timer.cancel();
    }
  }
}
