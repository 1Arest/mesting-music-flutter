/// Read-only DTOs for NetEase's ending report and full-record history. Field
/// names/units follow each public ending/list render call on 2026-11-02.
/// The v142 investigation corrects v140's unit inference: ending QmAe.e reads
/// seconds, whereas list QmAe.c reads milliseconds. Supporting expressions are
/// kept privately under .codex-artifacts/2026-11-02-release142-record-duration.
///
/// These models never derive an ended room's statistics from a live room clock.
/// Keep each endpoint's unit explicit; never guess it from the number's size.
class NeteaseTogetherProfile {
  const NeteaseTogetherProfile({
    required this.id,
    this.name = '',
    this.avatar = '',
    this.online,
  });
  final String id, name, avatar;
  final bool? online;

  factory NeteaseTogetherProfile.fromJson(Object? value) {
    final row = _object(value);
    return NeteaseTogetherProfile(
      id: _userId(row['userId']),
      name: _text(row['nickname'] ?? row['nick']),
      avatar: _text(row['avatarUrl'] ?? row['avatar'], 4096),
      online: _flag(row['online']),
    );
  }
}

class NeteaseTogetherRecord {
  const NeteaseTogetherRecord({
    required this.id,
    required this.roomId,
    this.self,
    this.peer,
    this.startedAt,
    this.endedAt,
    this.dateLabel = '',
    this.duration,
    this.totalDuration,
    this.songCount,
    this.totalSongCount,
    this.distanceKilometres,
    this.canInvite,
    this.online,
    this.roomType,
    this.scene,
    this.recordRoomType,
    this.ltType,
    this.officialUrl,
    this.oldData,
    this.fateDeleted,
    this.showCollectButton,
    this.songIds,
  });
  final String id, roomId, dateLabel;
  final NeteaseTogetherProfile? self, peer;
  final DateTime? startedAt, endedAt;
  final Duration? duration, totalDuration;
  final int? songCount, totalSongCount, ltType;
  final double? distanceKilometres;
  final bool? canInvite, online, oldData, fateDeleted, showCollectButton;
  final String? roomType, scene, recordRoomType;
  final Uri? officialUrl;

  /// Null means the separate room/songs/list read has not been made. Empty is
  /// reserved for a completed read that really returned an empty songIds list.
  final List<String>? songIds;

  bool get isMultiRoom => recordRoomType == 'multi_room';

  factory NeteaseTogetherRecord.fromHistory(
    Map<String, dynamic> row, {
    NeteaseTogetherProfile? self,
  }) {
    final type = _nonnegativeInt(row['ltType']);
    return NeteaseTogetherRecord(
      id: _text(row['id']),
      roomId: togetherRecordRoomId(row['roomId']),
      self: self,
      peer: NeteaseTogetherProfile.fromJson(row),
      dateLabel: _text(row['date']),
      startedAt: _timestamp(row['startTime']),
      duration: _milliseconds(row['duration']),
      songCount: _nonnegativeInt(row['totalSong']),
      canInvite: _flag(row['canInvite']),
      online: _flag(row['online']),
      ltType: type,
      recordRoomType: _optionalText(row['recordRoomType']),
      // The list client maps FRIEND=1 to these two ending-page arguments.
      roomType: type == 1 ? 'FRIEND' : null,
      scene: type == 1 ? 'MOBILE_FRIEND' : null,
      officialUrl: _officialUrl(row['targetUrl']),
    );
  }

  factory NeteaseTogetherRecord.fromReport(
    Map<String, dynamic> row, {
    required String roomId,
    required String selfId,
    String? peerId,
  }) {
    final participants = [
      NeteaseTogetherProfile.fromJson(row['userInfo']),
      NeteaseTogetherProfile.fromJson(row['anotherUserInfo']),
    ].where((profile) => profile.id.isNotEmpty).toList();
    NeteaseTogetherProfile? self, peer;
    for (final profile in participants) {
      if (profile.id == selfId) {
        self = profile;
      } else if (peer == null || profile.id == peerId) {
        peer = profile;
      }
    }
    return NeteaseTogetherRecord(
      id: _text(row['id']),
      roomId: roomId,
      self: self,
      peer: peer,
      startedAt: _timestamp(row['startTime']),
      endedAt: _timestamp(row['endTime']),
      // The ending client divides each raw value by 60 to obtain minutes.
      // Reusing the history-list millisecond reader shortens these 1000-fold.
      duration: _seconds(row['duration']),
      totalDuration: _seconds(row['totalDuration']),
      songCount: _nonnegativeInt(row['songCount']),
      totalSongCount: _nonnegativeInt(row['totalSongCount']),
      distanceKilometres: _distance(row['distance']),
      canInvite: _flag(row['canInvite']),
      online: _flag(row['online']),
      roomType: _optionalText(row['roomType']),
      scene: _optionalText(row['scene']),
      oldData: _flag(row['oldData']),
      fateDeleted: _flag(row['fateDel']),
      showCollectButton: _flag(row['showCollectBtn']),
    );
  }

  NeteaseTogetherRecord withProfiles({
    NeteaseTogetherProfile? self,
    NeteaseTogetherProfile? peer,
  }) => NeteaseTogetherRecord(
    id: id,
    roomId: roomId,
    self: self ?? this.self,
    peer: peer ?? this.peer,
    startedAt: startedAt,
    endedAt: endedAt,
    dateLabel: dateLabel,
    duration: duration,
    totalDuration: totalDuration,
    songCount: songCount,
    totalSongCount: totalSongCount,
    distanceKilometres: distanceKilometres,
    canInvite: canInvite,
    online: online,
    roomType: roomType,
    scene: scene,
    recordRoomType: recordRoomType,
    ltType: ltType,
    officialUrl: officialUrl,
    oldData: oldData,
    fateDeleted: fateDeleted,
    showCollectButton: showCollectButton,
    songIds: songIds,
  );
}

class NeteaseTogetherHistoryPageData {
  const NeteaseTogetherHistoryPageData({
    required this.records,
    this.mostListened,
    this.nextCursor,
    this.hasMore,
    this.vip,
    this.vipType,
  });
  final List<NeteaseTogetherRecord> records;
  final NeteaseTogetherRecord? mostListened;
  final String? nextCursor;
  final bool? hasMore, vip;
  final int? vipType;
  bool get membershipLimited => vip == false;

  factory NeteaseTogetherHistoryPageData.fromJson(
    Map<String, dynamic> row, {
    NeteaseTogetherProfile? self,
  }) {
    final most = _object(row['mostListen']);
    return NeteaseTogetherHistoryPageData(
      records: List.unmodifiable([
        if (row['records'] is List)
          for (final value in row['records'] as List)
            if (value is Map)
              NeteaseTogetherRecord.fromHistory(_object(value), self: self),
      ]),
      mostListened: most.isEmpty
          ? null
          : NeteaseTogetherRecord(
              id: '',
              roomId: '',
              self: self == null
                  ? null
                  : NeteaseTogetherProfile(
                      id: self.id,
                      name: self.name,
                      avatar: _optionalText(most['selfAvatar']) ?? self.avatar,
                    ),
              peer: NeteaseTogetherProfile(
                id: _userId(most['friendUid']),
                name: _text(most['friendNick']),
                avatar: _text(most['friendAvatar'], 4096),
                online: _flag(most['online']),
              ),
              totalDuration: _milliseconds(most['totalDuration']),
              totalSongCount: _nonnegativeInt(most['totalSong']),
              ltType: _nonnegativeInt(most['ltType']),
              online: _flag(most['online']),
            ),
      // Cursor is an opaque server value, never a locally incremented page.
      nextCursor: _cursor(row['nextCursor']),
      hasMore: _flag(row['hasMore']),
      vip: _flag(row['vip']),
      vipType: _nonnegativeInt(row['vipType']),
    );
  }
}

String togetherRecordRoomId(Object? value) {
  final id = value is String ? value : '${value ?? ''}';
  return RegExp(r'^[A-Za-z0-9_-]{1,160}$').hasMatch(id) ? id : '';
}

Map<String, dynamic> _object(Object? value) => value is Map
    ? Map<String, dynamic>.fromEntries(
        value.entries
            .where((e) => e.key is String)
            .map((e) => MapEntry(e.key as String, e.value)),
      )
    : const {};
String _text(Object? value, [int limit = 600]) => value is String
    ? (value.length <= limit ? value.trim() : '')
    : value is num
    ? '$value'
    : '';
String? _optionalText(Object? value) {
  final text = _text(value);
  return text.isEmpty ? null : text;
}

String _userId(Object? value) {
  final id = _text(value);
  return RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(id) ? id : '';
}

int? _nonnegativeInt(Object? value) {
  final integer = int.tryParse('$value');
  return integer != null && integer >= 0 ? integer : null;
}

bool? _flag(Object? value) => switch (value) {
  true || 1 || '1' || 'true' => true,
  false || 0 || '0' || 'false' => false,
  _ => null,
};
Duration? _milliseconds(Object? value) {
  final millis = _nonnegativeInt(value);
  return millis != null && millis <= 100 * 366 * 86400000
      ? Duration(milliseconds: millis)
      : null;
}

/// record/get uses seconds for both this session and the relationship total;
/// full/records keeps milliseconds. Separate readers also retain known zero,
/// unknown/malformed values and the same duration limit without a heuristic.
Duration? _seconds(Object? value) {
  final seconds = _nonnegativeInt(value);
  return seconds != null && seconds <= 100 * 366 * 86400
      ? Duration(seconds: seconds)
      : null;
}

DateTime? _timestamp(Object? value) {
  final millis = _nonnegativeInt(value);
  return millis != null && millis > 0 && millis < 7258118400000
      ? DateTime.fromMillisecondsSinceEpoch(millis)
      : null;
}

double? _distance(Object? value) {
  final distance = double.tryParse('$value');
  return distance != null && distance.isFinite && distance >= 0
      ? distance
      : null;
}

String? _cursor(Object? value) => value is String && value.length <= 4096
    ? value
    : value is num
    ? '$value'
    : null;
Uri? _officialUrl(Object? value) {
  if (value is! String || value.length > 16384) return null;
  final uri = Uri.tryParse(value);
  return uri != null &&
          uri.scheme == 'https' &&
          uri.userInfo.isEmpty &&
          (!uri.hasPort || uri.port == 443) &&
          {
            'music.163.com',
            'st.music.163.com',
            'y.music.163.com',
            'mp.music.163.com',
          }.contains(uri.host)
      ? uri
      : null;
}
