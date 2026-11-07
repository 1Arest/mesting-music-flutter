import 'dart:async';

import '../../../shared/models/track.dart';
import 'qishui_api.dart';
import 'qishui_models.dart';
import 'qishui_write_journal.dart';

/// The history adapter accepts the existing account-bound transport rather
/// than constructing another client, Cookie jar, device identity or signer.
typedef QishuiHistoryCall =
    Future<Map<String, dynamic>> Function(
      String path, {
      Map<String, Object?> body,
      Map<String, String> query,
      bool get,
      bool write,
      Future<void>? abortTrigger,
    });

class QishuiHistoryPage {
  const QishuiHistoryPage(this.tracks, this.hasMore, this.nextCursor);
  final List<Track> tracks;
  final bool hasMore;
  final String nextCursor;
}

/// Read and add only the official recently-played list. Listening duration,
/// play-count actions, ad rewards and historical log replay are separate
/// operations and deliberately do not belong to this adapter.
class QishuiHistoryRepository {
  QishuiHistoryRepository({
    required QishuiHistoryCall call,
    required bool Function() current,
    this.owner = '',
    QishuiWriteJournal? journal,
  }) : _call = call,
       _current = current,
       _journal = journal ?? QishuiWriteJournal();

  static const path = '/luna/me/recently-played-media';
  final QishuiHistoryCall _call;
  final bool Function() _current;
  final String owner;
  final QishuiWriteJournal _journal;
  final _abort = Completer<void>();
  Future<void> _writeTail = Future.value();

  bool get current => !_abort.isCompleted && _current();

  void _guard() {
    if (!current) {
      throw const QishuiException(
        '账号已变化或历史操作已取消，请重新打开',
        kind: QishuiFailureKind.cancelled,
      );
    }
  }

  Future<void> _cancellation(Future<void>? caller) => caller == null
      ? _abort.future
      : Future.any<void>([_abort.future, caller]);

  Future<QishuiHistoryPage> page({
    String cursor = '',
    int count = 50,
    Future<void>? abortTrigger,
  }) async {
    _guard();
    if (count < 1 || count > 100 || cursor.length > 4096) {
      throw const QishuiException('历史读取位置或数量无效');
    }
    final response = await _call(
      path,
      get: true,
      query: {'cursor': cursor, 'count': '$count'},
      abortTrigger: _cancellation(abortTrigger),
    );
    _guard();
    final inner = sodaMap(response['data']);
    bool hasRows(Map<String, dynamic> value) =>
        [
          'media',
          'tracks',
          'items',
          'resources',
          'media_resources',
        ].any((key) => value[key] is List) ||
        value['data'] is List;
    final payload = hasRows(inner) ? inner : response;
    if (!hasRows(payload)) {
      throw const QishuiException(
        '汽水历史响应缺少歌曲列表，请刷新核对',
        kind: QishuiFailureKind.format,
      );
    }
    final more =
        payload['has_more'] ??
        payload['hasMore'] ??
        response['has_more'] ??
        response['hasMore'];
    // Old PC responses may omit pagination for the final page. A present but
    // unknown marker is not interpreted as a complete empty history.
    if (more != null &&
        more != true &&
        more != false &&
        more != 0 &&
        more != 1 &&
        more != '0' &&
        more != '1') {
      throw const QishuiException(
        '汽水历史续载状态无效，请刷新核对',
        kind: QishuiFailureKind.format,
      );
    }
    final next =
        payload['next_cursor'] ??
        payload['nextCursor'] ??
        response['next_cursor'] ??
        response['nextCursor'];
    if (next != null && next is! String && next is! num) {
      throw const QishuiException(
        '汽水历史续载位置无效，请刷新核对',
        kind: QishuiFailureKind.format,
      );
    }
    return QishuiHistoryPage(
      sodaTracks(payload),
      more == true || more == 1 || more == '1',
      next == null ? '' : '$next',
    );
  }

  /// Preserve server order, deduplicate repeated page boundaries and refuse
  /// to label a looping/truncated response as the user's complete history.
  Future<List<Track>> all({Future<void>? abortTrigger}) async {
    final result = <String, Track>{};
    final cursors = <String>{''};
    var cursor = '';
    for (var index = 0; index < 100; index++) {
      final value = await page(cursor: cursor, abortTrigger: abortTrigger);
      for (final track in value.tracks) {
        result.putIfAbsent(track.id, () => track);
      }
      if (!value.hasMore) return List.unmodifiable(result.values);
      if (value.nextCursor.isEmpty ||
          value.nextCursor.length > 4096 ||
          !cursors.add(value.nextCursor)) {
        throw const QishuiException('汽水历史续载位置重复或缺失，请重新读取');
      }
      cursor = value.nextCursor;
    }
    throw const QishuiException('汽水历史超出本次读取上限，未将部分列表当作全部');
  }

  Future<bool> _atTop(String id, Future<void>? abortTrigger) async =>
      (await page(
        abortTrigger: abortTrigger,
      )).tracks.firstOrNull?.platformSongId ==
      id;

  /// A confirmed playback occurrence adds a recent-history row. The journal
  /// key is account + recording, not an app-process revision, so restarting
  /// cannot blindly replay a write whose outcome was lost. Readback confirms
  /// this list's recency position; it makes no claim about listening totals.
  Future<void> record(Track track, {Future<void>? abortTrigger}) {
    final result = _writeTail.then((_) async {
      _guard();
      if (owner.isEmpty ||
          track.source != TrackSource.qishui ||
          track.platformSongId.isEmpty) {
        throw const QishuiException('请选择当前账号的汽水歌曲记录历史');
      }
      final key = _journal.key(owner, 'recent173:${track.platformSongId}');
      if (await _journal.pending(key)) {
        if (await _atTop(track.platformSongId, abortTrigger)) {
          _guard();
          await _journal.finish(key);
          return;
        }
        throw const QishuiException(
          '上次汽水历史提交结果尚未确认，请刷新或到官版核对；未重复上报',
          unknownWrite: true,
          kind: QishuiFailureKind.uncertainWrite,
        );
      }
      _guard();
      await _journal.begin(key);
      try {
        _guard();
        await _call(
          path,
          body: {
            'media': [
              {'id': track.platformSongId, 'type': 'track'},
            ],
          },
          write: true,
          abortTrigger: _cancellation(abortTrigger),
        );
      } on QishuiException catch (error) {
        // Definite local/remote refusals can be submitted on a later real
        // playback. Timeouts after dispatch retain the unknown-write journal.
        if (!error.unknownWrite) await _journal.finish(key);
        rethrow;
      }
      try {
        if (await _atTop(track.platformSongId, abortTrigger)) {
          _guard();
          await _journal.finish(key);
          return;
        }
      } on Object {
        // Account change, cancellation or unreadable readback does not prove
        // the preceding mutation failed. Never clear it merely to retry.
      }
      throw const QishuiException(
        '汽水历史已提交，云端顺序尚未确认；不会自动重发',
        unknownWrite: true,
        kind: QishuiFailureKind.uncertainWrite,
      );
    });
    _writeTail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  void dispose() {
    if (!_abort.isCompleted) _abort.complete();
  }
}
