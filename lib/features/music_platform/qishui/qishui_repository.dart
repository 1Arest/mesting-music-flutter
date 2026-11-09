import 'dart:async';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../../../shared/models/track.dart';
import '../domain/platform_audio_quality.dart';
import '../netease/fallback/netease_audio_probe.dart';
import 'qishui_api.dart';
import 'qishui_models.dart';
import 'qishui_write_journal.dart';
import 'qishui_official_audio_cache.dart';
import 'qishui_playback_media.dart';
import 'qishui_player_info_loader.dart';
import 'qishui_entitlements.dart';
import 'qishui_media_attempts.dart';
import 'qishui_search_catalog.dart';
import 'qishui_image_upload.dart';
import 'qishui_history_repository.dart';
import 'qishui_diagnostics.dart';
import '../../../core/network/music_network_diagnostics.dart';

/// Typed feature adapter. Account ownership is captured at construction; a
/// delayed old repository can never send through a newly configured identity.
class QishuiRepository {
  QishuiRepository(
    this.api, {
    QishuiWriteJournal? writeJournal,
    QishuiOfficialAudioCache? audioCache,
  }) : credential = api.credential,
       _ownerId = api.session?.userId,
       _audioCache = audioCache ?? QishuiOfficialAudioCache(api.client),
       _journal = writeJournal ?? QishuiWriteJournal(),
       _ownerAbort = api.identityAbort;
  final QishuiApi api;
  final QishuiWriteJournal _journal;
  final QishuiOfficialAudioCache _audioCache;
  Future<void> _writeTail = Future.value();

  /// Serialize mutations separately from catalog reads. The journal is written
  /// before remote dispatch, and is cleared only on a definite rejection or
  /// confirmed official readback. No automatic retry of an unknown write.
  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _writeTail.then((_) {
      if (!current) throw const QishuiException('账号已变化，请重新操作');
      return operation();
    });
    _writeTail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> _confirmedWrite(
    String operation,
    Future<void> Function() submit,
    Future<bool> Function() confirmed,
  ) async {
    final key = _journal.key(api.session!.userId, operation);
    if (await confirmed()) {
      await _journal.finish(key);
      return;
    }
    if (await _journal.pending(key)) {
      throw const QishuiException(
        '上次汽水操作结果仍未确认，请先在官方App核对；本次没有重复提交',
        unknownWrite: true,
        kind: QishuiFailureKind.uncertainWrite,
      );
    }
    await _journal.begin(key);
    try {
      await submit();
    } on QishuiException catch (error) {
      if (!error.unknownWrite) await _journal.finish(key);
      rethrow;
    }
    try {
      if (await confirmed()) {
        await _journal.finish(key);
        return;
      }
    } on Object {
      /* Preserve pending state after an unreadable readback. */
    }
    throw const QishuiException(
      '汽水已接收提交，但当前状态尚未核对成功，请刷新核对；不会自动重发',
      unknownWrite: true,
      kind: QishuiFailureKind.uncertainWrite,
    );
  }

  Future<QishuiPlaylist> _ownedPlaylist(String id) async {
    final list = (await playlists()).where((p) => p.id == id).firstOrNull;
    if (list == null ||
        (list.kind != 1 && list.ownerId != api.session?.userId)) {
      throw const QishuiException('只有自己的汽水歌单可以修改，请刷新账号与歌单');
    }
    return list;
  }

  List<Map<String, String>> _mediaRows(List<Track> tracks) {
    if (tracks.isEmpty ||
        tracks.length > 10000 ||
        tracks.any(
          (t) => t.source != TrackSource.qishui || t.platformSongId.isEmpty,
        )) {
      throw const QishuiException('请选择有效的汽水歌曲');
    }
    return [
      for (final id in tracks.map((t) => t.platformSongId).toSet())
        {'id': id, 'type': 'track'},
    ];
  }

  Future<void> addPlaylistTracks(String id, List<Track> tracks) => _serialize(
    () async {
      await _ownedPlaylist(id);
      final rows = _mediaRows(tracks);
      await _confirmedWrite(
        'append:$id:${rows.map((r) => r['id']).join(',')}',
        () async {
          await call(
            '/luna/me/playlist/media/append',
            body: {'playlist_id': id, 'media': rows},
            write: true,
          );
        },
        () async {
          final ids = (await playlist(id)).map((t) => t.platformSongId).toSet();
          return rows.every((r) => ids.contains(r['id']));
        },
      );
    },
  );

  Future<void> removePlaylistTracks(String id, List<Track> tracks) =>
      _serialize(() async {
        await _ownedPlaylist(id);
        final rows = _mediaRows(tracks);
        await _confirmedWrite(
          'delete:$id:${rows.map((r) => r['id']).join(',')}',
          () async {
            await call(
              '/luna/me/playlist/media/delete',
              body: {'playlist_id': id, 'media': rows},
              write: true,
            );
          },
          () async {
            final ids = (await playlist(
              id,
            )).map((t) => t.platformSongId).toSet();
            return rows.every((r) => !ids.contains(r['id']));
          },
        );
      });

  Future<void> reorderPlaylist(String id, List<Track> ordered) =>
      _serialize(() async {
        await _ownedPlaylist(id);
        final rows = _mediaRows(ordered);
        final old = await playlist(id);
        final ids = rows.map((r) => r['id']!).toList();
        if (ids.length != ordered.length ||
            old.length != ids.length ||
            !old.map((t) => t.platformSongId).toSet().containsAll(ids)) {
          throw const QishuiException('汽水歌单内容已变化，请刷新后再排序');
        }
        await _confirmedWrite(
          'sort:$id:${ids.join(',')}',
          () async {
            await call(
              '/luna/me/playlist/media/sort',
              body: {'playlist_id': id, 'media': rows},
              write: true,
            );
          },
          () async =>
              (await playlist(id)).map((t) => t.platformSongId).join(',') ==
              ids.join(','),
        );
      });

  Future<void> setPlaylistPrivate(String id, bool value) =>
      _serialize(() async {
        await _ownedPlaylist(id);
        await _confirmedWrite(
          'privacy:$id:$value',
          () async {
            await call(
              '/luna/me/playlist/update',
              body: {'playlist_id': id, 'is_private': value},
              write: true,
            );
          },
          () async => (await _ownedPlaylist(id)).isPrivate == value,
        );
      });

  /// An image grant is temporary; only the server-returned URI enters the
  /// playlist update. A pending update is never re-uploaded/replayed after an
  /// unknown response. Readback must identify the same image, not merely any
  /// changed cover, before either this page or Mine reports success.
  Future<QishuiPlaylist> changePlaylistCover(
    String id,
    Uint8List bytes, {
    Future<void>? abortTrigger,
    Future<String> Function(Uint8List, Future<void>, bool Function())? upload,
  }) => _serialize(() async {
    final owned = await _ownedPlaylist(id);
    if (owned.kind == 1) throw const QishuiException('我喜欢的封面由汽水管理');
    if (bytes.isEmpty || bytes.length > QishuiImageUploader.maximumBytes) {
      throw const QishuiException('请选择10 MB以内的有效图片');
    }
    final key = _journal.key(
      api.session!.userId,
      'cover:$id:${sha256.convert(bytes)}',
    );
    if (await _journal.pending(key)) {
      throw const QishuiException(
        '上次封面更新尚未确认，请先到官版核对；本次没有重复上传或更新',
        unknownWrite: true,
        kind: QishuiFailureKind.uncertainWrite,
      );
    }
    final abort = _abort(abortTrigger);
    var cancelled = false;
    unawaited(abort.then((_) => cancelled = true));
    bool active() => current && !cancelled;
    final image =
        await (upload?.call(bytes, abort, active) ??
            QishuiImageUploader(
              api,
            ).upload(bytes, abort: abort, current: active));
    if (!active()) {
      throw const QishuiException(
        '账号已变化或封面更新已取消',
        kind: QishuiFailureKind.cancelled,
      );
    }
    if (!validQishuiImageKey(image)) throw const QishuiException('汽水返回的图片凭据无效');
    await _journal.begin(key);
    try {
      await call(
        '/luna/me/playlist/update',
        body: {'playlist_id': id, 'cover_uri': image},
        write: true,
        abortTrigger: abort,
      );
    } on QishuiException catch (error) {
      if (!error.unknownWrite) await _journal.finish(key);
      rethrow;
    }
    try {
      final confirmed = await _ownedPlaylist(id);
      if (active() &&
          (confirmed.coverUri == image ||
              Uri.tryParse(confirmed.cover)?.path.endsWith('/$image') ==
                  true)) {
        await _journal.finish(key);
        QishuiDiagnostics.shared.record(
          feature: QishuiDiagnosticFeature.playlistCover,
          stage: QishuiDiagnosticStage.readback,
          outcome: QishuiDiagnosticOutcome.success,
          receiptAccepted: true,
        );
        return confirmed;
      }
    } on Object {
      /* Keep unknown update pending; no blind write retry. */
    }
    QishuiDiagnostics.shared.record(
      feature: QishuiDiagnosticFeature.playlistCover,
      stage: QishuiDiagnosticStage.readback,
      outcome: QishuiDiagnosticOutcome.unconfirmed,
      reason: QishuiDiagnosticReason.cloudReadbackMismatch,
      receiptAccepted: false,
    );
    throw const QishuiException(
      '封面已提交，云端状态尚未核对成功，请刷新或到官版核对；不会自动重发',
      unknownWrite: true,
      kind: QishuiFailureKind.uncertainWrite,
    );
  });

  Future<QishuiPlaylist> createPlaylist(String name) => _serialize(() async {
    name = name.trim();
    if (name.isEmpty || name.runes.length > 30) {
      throw const QishuiException('汽水歌单名称需要1至30个字符');
    }
    final key = _journal.key(api.session!.userId, 'create:$name');
    final existing = (await playlists())
        .where((p) => p.name == name && p.ownerId == api.session?.userId)
        .toList();
    if (await _journal.pending(key)) {
      if (existing.length == 1) {
        await _journal.finish(key);
        return existing.single;
      }
      throw const QishuiException(
        '上次创建结果尚未确认，请在官方App核对，不要重复创建',
        unknownWrite: true,
      );
    }
    if (existing.isNotEmpty) throw const QishuiException('已有同名汽水歌单，请使用其他名称');
    await _journal.begin(key);
    Map<String, dynamic> response;
    try {
      response = await call(
        '/luna/me/playlist',
        body: {'name': name, 'is_private': false},
        write: true,
      );
    } on QishuiException catch (e) {
      if (!e.unknownWrite) await _journal.finish(key);
      rethrow;
    }
    final data = sodaMap(response['data']);
    final id =
        '${response['playlist_id'] ?? sodaMap(response['playlist'])['id'] ?? data['playlist_id'] ?? sodaMap(data['playlist'])['id'] ?? ''}';
    try {
      final lists = await playlists();
      final created = lists
          .where(
            (p) =>
                p.ownerId == api.session?.userId &&
                (id.isNotEmpty ? p.id == id : p.name == name),
          )
          .toList();
      if (created.length == 1) {
        await _journal.finish(key);
        return created.single;
      }
    } on Object {
      /* Never turn an uncertain create into another create. */
    }
    throw const QishuiException(
      '汽水歌单创建结果尚未确认，请刷新核对，不要重复创建',
      unknownWrite: true,
    );
  });
  final Future<void> _ownerAbort;
  Future<void> _abort(Future<void>? caller) =>
      caller == null ? _ownerAbort : Future.any([_ownerAbort, caller]);
  final String? credential;
  final String? _ownerId;
  bool get current =>
      credential != null &&
      api.credential == credential &&
      _ownerId != null &&
      api.session?.userId == _ownerId;
  Future<Map<String, dynamic>> call(
    String path, {
    Map<String, Object?> body = const {},
    Map<String, String> query = const {},
    bool get = false,
    bool write = false,
    Future<void>? abortTrigger,
  }) {
    if (!current) throw const QishuiException('账号已变化，请重新打开');
    return api.request(
      path,
      body: body,
      query: query,
      get: get,
      write: write,
      expectedCredential: credential,
      abortTrigger: abortTrigger,
    );
  }

  Future<List<QishuiPlaylist>> discover({Future<void>? abortTrigger}) async =>
      QishuiPlaylist.parse(
        await call(
          '/luna/discover/mix',
          body: {'count': 24},
          abortTrigger: abortTrigger,
        ),
      );
  Future<List<Track>> search(
    String query, {
    String cursor = '',
    Future<void>? abortTrigger,
  }) async =>
      (await QishuiSearchCatalog(
            request:
                (
                  path, {
                  body = const {},
                  query = const {},
                  get = false,
                  abortTrigger,
                }) => call(
                  path,
                  body: body,
                  query: query,
                  get: get,
                  abortTrigger: abortTrigger,
                ),
          ).searchTracks(
            query,
            cursor: cursor.isEmpty ? '0' : cursor,
            searchId: QishuiSearchCatalog.newSearchId(),
            abortTrigger: abortTrigger,
          ))
          .items;

  /// One presentation page. Merely opening a collection must not enumerate
  /// every offscreen track. Full-list mutations and explicit bulk actions keep
  /// using [playlist], whose completeness/loop guards remain independent.
  Future<QishuiCatalogPage<Track>> playlistPage(
    String id, {
    String cursor = '',
    int count = 100,
    Future<void>? abortTrigger,
  }) async {
    if (id.isEmpty ||
        id.length > 256 ||
        cursor.length > 4096 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch('$id$cursor') ||
        count < 1 ||
        count > 100) {
      throw const QishuiException('汽水歌单或读取位置无效');
    }
    final response = await call(
      '/luna/playlist/detail',
      body: {'playlist_id': id, 'cursor': cursor, 'count': count},
      abortTrigger: abortTrigger,
    );
    final nested = sodaMap(response['data']);
    final data = nested.isNotEmpty ? nested : response;
    final returnedId = '${sodaMap(data['playlist'])['id'] ?? ''}';
    if (returnedId.isNotEmpty && returnedId != id) {
      throw const QishuiException('汽水返回的歌单不匹配');
    }
    final marker = data['has_more'] ?? response['has_more'];
    if (marker != null &&
        marker != true &&
        marker != false &&
        marker != 0 &&
        marker != 1 &&
        marker != '0' &&
        marker != '1') {
      throw const QishuiException('汽水歌单续载状态无效');
    }
    final more = marker == true || marker == 1 || marker == '1';
    final nextValue = data['next_cursor'] ?? response['next_cursor'];
    final next = nextValue is String || nextValue is num ? '$nextValue' : '';
    final validNext =
        next.isNotEmpty &&
        next.length <= 4096 &&
        next != cursor &&
        !RegExp(r'[\x00-\x1f\x7f]').hasMatch(next);
    return QishuiCatalogPage(
      items: sodaTracks(data),
      cursor: cursor,
      nextCursor: more && validNext ? next : null,
      hasMore: more,
      continuationProblem: more && !validNext ? '歌单续载位置异常，请重新读取' : null,
    );
  }

  Future<List<Track>> playlist(
    String id, {
    String cursor = '',
    Future<void>? abortTrigger,
  }) async {
    final result = <String, Track>{};
    final cursors = <String>{};
    for (var page = 0; page < 1000; page++) {
      final batch = await playlistPage(
        id,
        cursor: cursor,
        abortTrigger: abortTrigger,
      );
      for (final track in batch.items) {
        result[track.id] = track;
      }
      if (!batch.hasMore) return List.unmodifiable(result.values);
      final next = batch.nextCursor;
      if (batch.continuationProblem != null ||
          next == null ||
          !cursors.add(next)) {
        throw const QishuiException('歌单续载位置异常，请重新读取');
      }
      cursor = next;
    }
    throw const QishuiException('歌单读取超出本次上限，未将不完整列表当作全部歌曲');
  }

  Future<List<Track>> feed({
    QishuiFeedMode? mode,
    Future<void>? abortTrigger,
  }) async => sodaTracks(
    await call(
      '/luna/feed/song-tab',
      body: {'count': 20, if (mode != null) 'feed_preference': mode.preference},
      abortTrigger: abortTrigger,
    ),
  );
  Future<List<QishuiFeedMode>> modes() async =>
      QishuiFeedMode.parse(await call('/luna/feed/mode'));
  Future<Map<String, dynamic>> profile() => call('/luna/me', get: true);
  Future<List<QishuiPlaylist>> playlists({Future<void>? abortTrigger}) async {
    final result = <String, QishuiPlaylist>{};
    final seen = <String>{};
    var cursor = '';
    for (var page = 0; page < 1000; page++) {
      final data = await call(
        '/luna/me/playlist/v2',
        body: {'cursor': cursor, 'count': 50},
        abortTrigger: abortTrigger,
      );
      for (final list in QishuiPlaylist.parse(data)) {
        result[list.id] = list;
      }
      if (data['has_more'] != true) return List.unmodifiable(result.values);
      final next = '${data['next_cursor'] ?? ''}';
      if (next.isEmpty || next == cursor || !seen.add(next)) {
        throw const QishuiException('歌单目录续载异常，请重试');
      }
      cursor = next;
    }
    throw const QishuiException('歌单目录读取尚未完成');
  }

  Future<List<Track>> favorites({Future<void>? abortTrigger}) async {
    final matches = (await playlists(
      abortTrigger: abortTrigger,
    )).where((p) => p.kind == 1).toList();
    if (matches.length != 1) throw const QishuiException('汽水未返回唯一的我喜欢歌单，请刷新核对');
    return playlist(matches.single.id, abortTrigger: abortTrigger);
  }

  Future<void> setFavorite(Track track, bool favorite) async {
    if (track.source != TrackSource.qishui) {
      throw const QishuiException('汽水收藏仅支持汽水歌曲');
    }
    await call(
      favorite
          ? '/luna/me/collection/media'
          : '/luna/me/collection/media/delete',
      body: {
        'media': [
          {'id': track.platformSongId, 'type': 'track'},
        ],
      },
      write: true,
    );
    final confirmed = (await favorites()).any((t) => t.id == track.id);
    if (confirmed != favorite) {
      throw const QishuiException('已提交收藏，服务端状态尚未确认，请刷新核对');
    }
  }

  Future<List<Track>> recent({Future<void>? abortTrigger}) =>
      QishuiHistoryRepository(
        call: call,
        current: () => current,
      ).all(abortTrigger: abortTrigger);
  Future<Map<String, dynamic>> commerce({Future<void>? abortTrigger}) async {
    final result = await call(
      '/luna/commerce/v2/commerce_info',
      abortTrigger: abortTrigger,
      body: {
        'includes': [
          'treasure',
          'play_entitlements',
          'incentive',
          'activity_free_vip',
          'membership',
          'benefit_base',
        ],
      },
    );
    final rights = QishuiEntitlements(result);
    MusicNetworkDiagnostics.shared.record(
      platform: 'qishui',
      operation: MusicNetworkOperation.read,
      outcome: MusicNetworkOutcome.success,
      phase: MusicDiagnosticPhase.entitlementRead,
      freeListeningActive: rights.freeListeningActive,
      membershipActive: rights.membershipActive,
    );
    return result;
  }

  Future<Map<String, dynamic>> media(String id, {Future<void>? abortTrigger}) =>
      call(
        '/luna/media_v2',
        body: {
          'media': [
            {'id': id, 'type': 'track'},
          ],
        },
        abortTrigger: abortTrigger,
      );

  /// Media can be embedded or deferred to a signed first-party player-info
  /// link. Keep this transport separate from account API calls and selection.
  Future<Map<String, dynamic>> _playbackData(
    String id,
    Future<void>? abortTrigger, {
    Duration catalogDuration = Duration.zero,
  }) async {
    abortTrigger = _abort(abortTrigger);
    final data = await media(id, abortTrigger: abortTrigger);
    return QishuiPlayerInfoLoader(api.client).load(
      data,
      catalogDuration: catalogDuration,
      abort: abortTrigger,
      current: () => current,
    );
  }

  Future<Set<PlatformAudioQuality>> qualities(String id) async {
    final values = QishuiMedia.parse(
      await _playbackData(id.replaceFirst('qishui_', ''), null),
    );
    return {
      for (final value in values.where(
        (v) => v.canDecodeOfficial && v.bitrate > 0,
      ))
        value.bitrate > 220000
            ? PlatformAudioQuality.high
            : PlatformAudioQuality.standard,
    };
  }

  Future<Track> resolve(
    Track track, {
    bool download = false,
    PlatformAudioQuality? quality,
    bool requireQuality = true,
    Future<void>? abortTrigger,
    bool Function()? stillCurrent,
  }) async {
    if (track.source != TrackSource.qishui ||
        !current ||
        stillCurrent?.call() == false) {
      throw const QishuiException('请先切换到汽水账号');
    }
    if (track.duration <= Duration.zero) {
      throw const QishuiException('汽水未返回歌曲时长，暂不能确认完整版');
    }
    abortTrigger = _abort(abortTrigger);
    final data = await _playbackData(
      track.platformSongId,
      abortTrigger,
      catalogDuration: track.duration,
    );
    final streams = QishuiMedia.parse(data);
    MusicNetworkDiagnostics.shared.record(
      platform: 'qishui',
      operation: MusicNetworkOperation.playbackUrl,
      outcome: streams.isEmpty
          ? MusicNetworkOutcome.format
          : MusicNetworkOutcome.success,
      transport: 'local',
      phase: MusicDiagnosticPhase.mediaModelParse,
      streamCandidates: streams.length,
      decodableStreams: streams
          .where((media) => media.canDecodeOfficial)
          .length,
    );
    final candidates = QishuiPlaybackSelection.candidates(
      streams,
      catalogDuration: track.duration,
      download: download,
      quality: quality,
      requireQuality: requireQuality,
    );
    var cancelled = false;
    unawaited(abortTrigger.then((_) => cancelled = true));
    return prepareQishuiMediaCandidates(
      candidates,
      current: () => current && !cancelled && stillCurrent?.call() != false,
      prepare: (selected, attempt) async {
        final candidate = selected.media;
        MusicNetworkDiagnostics.shared.record(
          platform: 'qishui',
          operation: MusicNetworkOperation.playbackUrl,
          outcome: MusicNetworkOutcome.success,
          transport: 'local',
          phase: MusicDiagnosticPhase.mediaSelection,
          mediaCandidateAttempt: attempt,
          preview: selected.isPreview,
          catalogDurationMs: track.duration.inMilliseconds,
          mediaDurationMs: candidate.duration.inMilliseconds,
        );
        if (download) {
          await _requireDownloadPermission(
            track.platformSongId,
            candidate,
            abortTrigger,
          );
        }
        final localPath = candidate.encrypted
            ? await _audioCache.resolve(
                candidate,
                ownerKey: credential!,
                trackId: track.platformSongId,
                abort: abortTrigger!,
                current: () => current && stillCurrent?.call() != false,
              )
            : null;
        final probe = localPath != null
            ? await QishuiOfficialAudioCache.inspectFile(
                localPath,
                expectedDuration: selected.isPreview
                    ? candidate.duration
                    : track.duration,
              )
            : await inspectNeteaseAudio(
                api.client,
                candidate.url,
                expectedDuration: selected.isPreview
                    ? candidate.duration
                    : track.duration,
                abortTrigger: abortTrigger,
                prefixBytes: 65536,
              );
        if (!current || stillCurrent?.call() == false) {
          throw const QishuiException(
            '账号或播放选择已变化，请重新播放',
            kind: QishuiFailureKind.cancelled,
          );
        }
        if (!probe.playable || !{'mp3', 'm4a', 'flac'}.contains(probe.format)) {
          MusicNetworkDiagnostics.shared.record(
            platform: 'qishui',
            operation: MusicNetworkOperation.audio,
            outcome: MusicNetworkOutcome.format,
            transport: 'local',
            phase: MusicDiagnosticPhase.audioVerify,
          );
          throw const QishuiException(
            '汽水音频完整性或格式核验未通过',
            kind: QishuiFailureKind.format,
          );
        }
        MusicNetworkDiagnostics.shared.record(
          platform: 'qishui',
          operation: MusicNetworkOperation.audio,
          outcome: MusicNetworkOutcome.success,
          transport: 'local',
          phase: MusicDiagnosticPhase.audioVerify,
        );
        final bitrate = probe.bitrate > 0 ? probe.bitrate : candidate.bitrate;
        final actual = bitrate <= 0
            ? null
            : bitrate > 220000
            ? PlatformAudioQuality.high
            : PlatformAudioQuality.standard;
        if (requireQuality && quality != null && actual != quality) {
          throw const QishuiException(
            '汽水音频的实际音质未通过核验',
            kind: QishuiFailureKind.format,
          );
        }
        return track.copyWith(
          audioAsset: localPath == null
              ? candidate.url
              : Uri.file(localPath).toString(),
          isPreview: selected.isPreview,
          playbackQuality: actual?.code ?? '',
          audioBitrate: bitrate,
          audioHeaders: const {},
          audioOrigin: AudioOrigin(AudioOrigin.qishui, track.platformSongId),
        );
      },
    );
  }

  Future<void> _requireDownloadPermission(
    String id,
    QishuiMedia media,
    Future<void>? abort,
  ) async {
    // Values are Quality.getValue(), not the enum ordinal. Verified against
    // the installed official 19.0.0 DEX; serverKey/definition is the wire name.
    const officialQualities = {
      'medium': 1,
      'higher': 2,
      'higherer': 3,
      'highest': 4,
      'lossless': 5,
      'spatial': 6,
      'hi_res': 7,
      'original': 8,
    };
    final quality = media.qualityCode ?? officialQualities[media.qualityName];
    if (quality == null) throw const QishuiException('汽水未返回本音质的下载资格参数，暂不能保存');
    final result = await call(
      '/luna/commerce/v2/check_download',
      body: {
        'tracks': [
          {'track_id': id, 'quality': quality},
        ],
      },
      abortTrigger: abort,
    );
    final rows = sodaRows(result['track_download_info_list'])
        .where((row) => row['track_id'] == id && row['quality'] == quality)
        .toList();
    if (rows.length != 1 || rows.single['need_download_quota'] != false) {
      // Quota consumption is a distinct write contract. Never silently spend
      // quota, synthesize a grant or infer downloads from a playable URL.
      throw const QishuiException(
        '汽水未确认本音质无需额外扣额的下载资格，暂不能保存',
        kind: QishuiFailureKind.entitlement,
      );
    }
  }

  Future<String> lyrics(String id) async {
    final data = await media(id);
    String? content;
    void visit(Object? value, int depth) {
      if (depth > 12 || content != null) return;
      if (value is List) {
        for (final item in value) {
          visit(item, depth + 1);
        }
      }
      if (value is Map) {
        final lyric = sodaMap(value['lyric']);
        if (lyric['content'] is String &&
            (lyric['content'] as String).trim().isNotEmpty) {
          content = lyric['content'] as String;
          return;
        }
        for (final key in [
          'media',
          'entity',
          'track_wrapper',
          'track',
          'data',
        ]) {
          visit(value[key], depth + 1);
        }
      }
    }

    visit(data, 0);
    if (content == null) throw const QishuiException('汽水暂未提供这首歌的歌词');
    return qishuiLrc(content!);
  }
}

/// Preserve real line timing while removing the proprietary word-tag syntax.
/// Existing LRC is passed through; no synthetic lyrics or timestamps are made.
String qishuiLrc(String source) {
  if (RegExp(r'^\[\d+:\d+', multiLine: true).hasMatch(source)) return source;
  final lines = <String>[];
  for (final line in source.split('\n')) {
    final match = RegExp(r'^\[(\d+),(\d+)\](.*)$').firstMatch(line.trim());
    if (match == null) continue;
    final ms = int.parse(match[1]!);
    final text = match[3]!.replaceAll(RegExp(r'<\d+,\d+(?:,\d+)?>'), '');
    lines.add(
      '[${(ms ~/ 60000).toString().padLeft(2, '0')}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}.${(ms % 1000).toString().padLeft(3, '0')}]$text',
    );
  }
  return lines.isEmpty ? source : lines.join('\n');
}
