import '../domain/listen_together.dart';

abstract interface class ListenTogetherRepository {
  Future<ListenTogetherSession?> getListenTogetherSession();

  Future<ListenTogetherSession> inviteToListenTogether(
    String uid, {
    required ListenTogetherPlayback playback,
  });

  Future<ListenTogetherSession> respondToListenTogetherInvite(
    String invitationId, {
    required bool accept,
  });

  Future<ListenTogetherSession> updateListenTogetherPlayback(
    ListenTogetherPlayback playback, {
    required int baseRevision,
  });

  Future<ListenTogetherSession> leaveListenTogether();

  Future<List<ListenTogetherTrackRecord>> listListenTogetherRecords(String uid);
}

class UnsupportedListenTogetherRepository implements ListenTogetherRepository {
  const UnsupportedListenTogetherRepository();

  Never _unsupported() => throw UnsupportedError('当前好友服务尚未提供一起听能力');

  @override
  Future<ListenTogetherSession?> getListenTogetherSession() async => null;

  @override
  Future<ListenTogetherSession> inviteToListenTogether(
    String uid, {
    required ListenTogetherPlayback playback,
  }) async => _unsupported();

  @override
  Future<ListenTogetherSession> respondToListenTogetherInvite(
    String invitationId, {
    required bool accept,
  }) async => _unsupported();

  @override
  Future<ListenTogetherSession> updateListenTogetherPlayback(
    ListenTogetherPlayback playback, {
    required int baseRevision,
  }) async => _unsupported();

  @override
  Future<ListenTogetherSession> leaveListenTogether() async => _unsupported();

  @override
  Future<List<ListenTogetherTrackRecord>> listListenTogetherRecords(
    String uid,
  ) async => _unsupported();
}
