import 'dart:async';

import 'qishui_api.dart';
import 'qishui_models.dart';
import 'qishui_repository.dart';
import 'qishui_social_models.dart';
import 'qishui_write_journal.dart';
import 'qishui_diagnostics.dart';

/// Owns only the current Soda account. Reads and mutations use the official
/// common API paths; there are no guessed PC social routes or other-platform
/// fallbacks. The caller owns page cancellation and presentation state.
class QishuiSocialRepository {
  QishuiSocialRepository(this.music, {QishuiWriteJournal? journal})
    : _journal = journal ?? QishuiWriteJournal();

  final QishuiRepository music;
  final QishuiWriteJournal _journal;
  Future<void> _tail = Future.value();
  bool get current => music.current;
  String get owner => music.api.session?.userId ?? '';

  void _guard() {
    if (!current) throw const QishuiException('汽水账号已变化，请返回后重新打开');
  }

  /// DTO failures happen after an HTTP 200 and were absent from the generic
  /// network log. Keep their feature and safe structure, never the user data.
  T _parse<T>(
    QishuiDiagnosticFeature feature,
    Map<String, dynamic> response,
    T Function() parse,
  ) {
    try {
      final result = parse();
      QishuiDiagnostics.shared.record(
        feature: feature,
        stage: QishuiDiagnosticStage.parse,
        outcome: QishuiDiagnosticOutcome.success,
      );
      return result;
    } on Object {
      QishuiDiagnostics.shared.record(
        feature: feature,
        stage: QishuiDiagnosticStage.parse,
        outcome: QishuiDiagnosticOutcome.format,
        reason: QishuiDiagnosticReason.responseShape,
        response: response,
      );
      rethrow;
    }
  }

  QishuiSocialStats _stats(Map<String, dynamic> response) {
    final stats = QishuiSocialStats.parse(response);
    QishuiDiagnostics.shared.record(
      feature: QishuiDiagnosticFeature.socialStats,
      stage: QishuiDiagnosticStage.parse,
      outcome: stats.hasCounts
          ? QishuiDiagnosticOutcome.success
          : QishuiDiagnosticOutcome.format,
      reason: stats.hasCounts ? null : QishuiDiagnosticReason.missingFields,
      response: stats.hasCounts ? null : response,
    );
    return stats;
  }

  Future<QishuiSocialStats> fetchStats({Future<void>? abortTrigger}) async {
    _guard();
    final root = qishuiSocialPayload(
      await music.call('/luna/me', get: true, abortTrigger: abortTrigger),
    );
    final user = sodaMap(root['my_info']);
    if ('${user['id'] ?? ''}' != owner) {
      QishuiDiagnostics.shared.record(
        feature: QishuiDiagnosticFeature.socialStats,
        stage: QishuiDiagnosticStage.identity,
        outcome: QishuiDiagnosticOutcome.refused,
        reason: QishuiDiagnosticReason.identityMismatch,
      );
      throw const QishuiException('汽水账号资料不匹配');
    }
    final stats = _stats(root);
    if (root['my_stats'] is Map) return stats;
    // Some PC responses omit statistics. The official UserApi has a common
    // GET /luna/user/info returning user_stats, with its user ID checked before
    // accepting counts. This is an explicit verified route, not a blind retry
    // of a failed profile request or a speculative /pc path substitution.
    final full = await _userInfo(owner, abortTrigger: abortTrigger);
    return _stats(full);
  }

  Future<Map<String, dynamic>> _userInfo(
    String userId, {
    Future<void>? abortTrigger,
  }) async {
    _guard();
    final id = _id(userId);
    final result = await music.call(
      '/luna/user/info',
      get: true,
      query: {'user_id': id},
      abortTrigger: abortTrigger,
    );
    _parse(
      QishuiDiagnosticFeature.userInfo,
      result,
      () => QishuiSocialPerson.parseUserInfo(result, id),
    );
    _guard();
    return result;
  }

  Future<QishuiSocialPerson> userInfo(
    String userId, {
    Future<void>? abortTrigger,
  }) async => QishuiSocialPerson.parseUserInfo(
    await _userInfo(userId, abortTrigger: abortTrigger),
    userId,
  );

  Future<QishuiSocialPage> list(
    QishuiFollowListKind kind, {
    String? userId,
    String cursor = '',
    int count = 20,
    QishuiFollowSource source = QishuiFollowSource.qishui,
    Future<void>? abortTrigger,
  }) async {
    _guard();
    if (!qishuiSocialCursorValid(cursor) || count < 1 || count > 100) {
      throw const QishuiException('汽水列表续载参数无效，请刷新');
    }
    final id = _id(userId ?? owner);
    final result = await music.call(
      '/luna/users/$id/${kind.pathName}',
      get: true,
      // Official pages have separate SourceLuna=2 and SourceAweme=1 groups.
      // Each group owns a cursor chain. The service initial cursor is empty.
      query: {'cursor': cursor, 'count': '$count', 'scene': source.scene},
      abortTrigger: abortTrigger,
    );
    _guard();
    return _parse(
      kind == QishuiFollowListKind.following
          ? QishuiDiagnosticFeature.following
          : QishuiDiagnosticFeature.followers,
      result,
      () => QishuiSocialPage.parse(result, cursor),
    );
  }

  Future<QishuiSocialPerson> setFollowing(
    String userId,
    bool value, {
    Future<void>? abortTrigger,
  }) {
    final result = _tail.then(
      (_) => _setFollowing(userId, value, abortTrigger),
    );
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// Artist collection is the official artist-follow operation. Even an
  /// artist associated with a user keeps its artist namespace here.
  Future<QishuiSocialPerson> setArtistFollowing(
    QishuiSocialPerson artist,
    bool value, {
    Future<void>? abortTrigger,
  }) {
    final result = _tail.then(
      (_) => _setArtistFollowing(artist, value, abortTrigger),
    );
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<bool> artistMembership(
    String artistId, {
    Future<void>? abortTrigger,
  }) async {
    _guard();
    final id = _id(artistId);
    String? cursor;
    final visited = <String>{};
    // Only full pagination can establish absence. A failed or repeated cursor
    // is unknown, never a successful unfollow readback.
    for (var page = 0; page < 500; page++) {
      final root = qishuiSocialPayload(
        await music.call(
          '/luna/me/collection/artist',
          get: true,
          query: {'count': '50', 'cursor': ?cursor},
          abortTrigger: abortTrigger,
        ),
      );
      _guard();
      final artists = root['artists'];
      if (artists is! List || artists.length > 200) {
        QishuiDiagnostics.shared.record(
          feature: QishuiDiagnosticFeature.artistCollection,
          stage: QishuiDiagnosticStage.parse,
          outcome: QishuiDiagnosticOutcome.format,
          reason: QishuiDiagnosticReason.responseShape,
          response: root,
        );
        throw const QishuiException('汽水歌手关注列表格式异常');
      }
      if (artists.any((a) => qishuiSocialId(sodaMap(a)['id']) == id)) {
        return true;
      }
      final hasMore = root['has_more'];
      if (hasMore == false || hasMore == 0 || hasMore == '0') return false;
      if (hasMore != true && hasMore != 1 && hasMore != '1') {
        QishuiDiagnostics.shared.record(
          feature: QishuiDiagnosticFeature.artistCollection,
          stage: QishuiDiagnosticStage.parse,
          outcome: QishuiDiagnosticOutcome.format,
          reason: QishuiDiagnosticReason.missingFields,
          response: root,
        );
        throw const QishuiException('汽水未返回完整歌手关注列表的续载状态');
      }
      final next = root['next_cursor'];
      if (next is! String ||
          next.isEmpty ||
          !qishuiSocialCursorValid(next) ||
          !visited.add(next)) {
        QishuiDiagnostics.shared.record(
          feature: QishuiDiagnosticFeature.artistCollection,
          stage: QishuiDiagnosticStage.parse,
          outcome: QishuiDiagnosticOutcome.format,
          reason: QishuiDiagnosticReason.invalidFields,
          response: root,
        );
        throw const QishuiException('汽水歌手关注列表续载位置异常');
      }
      cursor = next;
    }
    throw const QishuiException('汽水歌手关注列表尚未全部读取，请到官版核对');
  }

  Future<QishuiSocialPerson> _setArtistFollowing(
    QishuiSocialPerson artist,
    bool value,
    Future<void>? abortTrigger,
  ) async {
    _guard();
    if (!artist.artistEntity || artist.artistId == null) {
      throw const QishuiException('此记录不是可核对的汽水歌手');
    }
    final id = _id(artist.artistId!);
    final yes = _journal.key(owner, 'social-artist:$id:true');
    final no = _journal.key(owner, 'social-artist:$id:false');
    final key = value ? yes : no;
    if (await artistMembership(id, abortTrigger: abortTrigger) == value) {
      await _journal.finish(yes);
      await _journal.finish(no);
      return artist.withArtistMembership(value);
    }
    if (await _journal.pending(yes) || await _journal.pending(no)) {
      throw const QishuiException(
        '上次歌手关注结果尚未确认，请先到官版核对；本次没有重复提交',
        unknownWrite: true,
        kind: QishuiFailureKind.uncertainWrite,
      );
    }
    _guard();
    await _journal.begin(key);
    Map<String, dynamic> response;
    try {
      response = qishuiSocialPayload(
        await music.call(
          value
              ? '/luna/me/collection/artist'
              : '/luna/me/collection/artist/delete',
          body: {
            'artist_ids': [id],
          },
          write: true,
          abortTrigger: abortTrigger,
        ),
      );
    } on QishuiException catch (error) {
      if (!error.unknownWrite) await _journal.finish(key);
      rethrow;
    }
    try {
      final accepted = response[value ? 'artist_ids' : 'deleted_artists'];
      if (accepted is List &&
          accepted.contains(id) &&
          await artistMembership(id, abortTrigger: abortTrigger) == value) {
        _guard();
        await _journal.finish(key);
        QishuiDiagnostics.shared.record(
          feature: QishuiDiagnosticFeature.artistCollection,
          stage: QishuiDiagnosticStage.readback,
          outcome: QishuiDiagnosticOutcome.success,
        );
        return artist.withArtistMembership(value);
      }
    } on Object {
      // Keep the digest when the official readback cannot settle the write.
    }
    QishuiDiagnostics.shared.record(
      feature: QishuiDiagnosticFeature.artistCollection,
      stage: QishuiDiagnosticStage.readback,
      outcome: QishuiDiagnosticOutcome.unconfirmed,
      reason: QishuiDiagnosticReason.receiptRejected,
      response: response,
    );
    throw const QishuiException(
      '歌手关注操作已提交，官方列表尚未确认；不会自动重发，请刷新或到官版核对',
      unknownWrite: true,
      kind: QishuiFailureKind.uncertainWrite,
    );
  }

  Future<QishuiSocialPerson> _setFollowing(
    String userId,
    bool value,
    Future<void>? abortTrigger,
  ) async {
    _guard();
    final id = _id(userId);
    if (id == owner) throw const QishuiException('不能关注自己');
    var cancelled = false;
    if (abortTrigger != null) {
      unawaited(abortTrigger.then((_) => cancelled = true));
    }
    void guard() {
      _guard();
      if (cancelled) throw const QishuiException('本次操作已取消');
    }

    final positiveKey = _journal.key(owner, 'social-follow:$id:true');
    final negativeKey = _journal.key(owner, 'social-follow:$id:false');
    final key = value ? positiveKey : negativeKey;
    final before = await userInfo(id, abortTrigger: abortTrigger);
    guard();
    if (before.following == value || value && before.requested) {
      await _journal.finish(positiveKey);
      await _journal.finish(negativeKey);
      return before;
    }
    if (await _journal.pending(positiveKey) ||
        await _journal.pending(negativeKey)) {
      throw const QishuiException(
        '上次关注操作尚未确认，请先到官版核对；本次没有重复提交',
        unknownWrite: true,
        kind: QishuiFailureKind.uncertainWrite,
      );
    }
    guard();
    await _journal.begin(key);
    Map<String, dynamic> receipt;
    try {
      receipt = qishuiSocialPayload(
        await music.api.request(
          value ? '/luna/me/follow' : '/luna/me/unfollow',
          form: {'user_id': id},
          write: true,
          expectedCredential: music.credential,
          abortTrigger: abortTrigger,
        ),
      );
    } on QishuiException catch (error) {
      if (!error.unknownWrite) await _journal.finish(key);
      rethrow;
    }
    // Both the response identity and a fresh state read must agree. HTTP 200
    // alone is not follow acceptance, and a private-account request is shown
    // as requested rather than incorrectly displayed as an accepted follow.
    try {
      guard();
      final responseId = qishuiSocialId(receipt['user_id']);
      final responseState = qishuiSocialCount(receipt['follow_status']);
      final after = await userInfo(id, abortTrigger: abortTrigger);
      guard();
      if (responseId == id &&
          responseState == after.followStatus &&
          (after.following == value || value && after.requested)) {
        await _journal.finish(key);
        QishuiDiagnostics.shared.record(
          feature: value
              ? QishuiDiagnosticFeature.userFollow
              : QishuiDiagnosticFeature.userUnfollow,
          stage: QishuiDiagnosticStage.readback,
          outcome: QishuiDiagnosticOutcome.success,
        );
        return after;
      }
    } on Object {
      // The server may already have committed it. Keep the operation digest
      // pending after cancellation, account changes or an unreadable readback.
    }
    QishuiDiagnostics.shared.record(
      feature: value
          ? QishuiDiagnosticFeature.userFollow
          : QishuiDiagnosticFeature.userUnfollow,
      stage: QishuiDiagnosticStage.readback,
      outcome: QishuiDiagnosticOutcome.unconfirmed,
      reason: QishuiDiagnosticReason.receiptRejected,
      response: receipt,
    );
    throw const QishuiException(
      '关注操作已提交，官方状态尚未确认；请刷新或到官版核对，不会自动重发',
      unknownWrite: true,
      kind: QishuiFailureKind.uncertainWrite,
    );
  }

  String _id(String value) =>
      qishuiSocialId(value) ??
      (throw const QishuiException('汽水用户标识无效，请重新打开列表'));
}
