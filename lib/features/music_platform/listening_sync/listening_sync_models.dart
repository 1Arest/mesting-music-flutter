import 'dart:convert';

import '../../../shared/models/track.dart';

/// Current-process measurements from a genuine standard authorization only.
/// Legacy grade rows must never be relabelled or copied into this protocol.
const kugouStandardGradeProtocol = 'kugou-standard-v4-new-play-v1';

/// Accepted means the platform acknowledged a write. Verified requires a
/// separate official read-back; the two are deliberately different states.
enum ListeningSyncState {
  queued,
  open,
  dispatched,
  accepted,
  verified,
  unknown,
  rejected,
  coalesced,
  interrupted,
}

class ListeningSyncEntry {
  const ListeningSyncEntry({
    required this.ownerId,
    required this.id,
    required this.kind,
    required this.payload,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
  });
  final String ownerId, id, kind;
  final Map<String, Object?> payload;
  final ListeningSyncState state;
  final DateTime createdAt, updatedAt;

  int number(String key) => int.tryParse('${payload[key]}') ?? 0;
  String text(String key) => '${payload[key] ?? ''}';
}

/// Only an official recording ID is eligible. Hashes, local filenames and
/// generic work/audio IDs cannot be substituted for a mixsongid.
bool isOfficialMusicTrack(Track track) =>
    track.source == TrackSource.kugou &&
    RegExp(r'^kugou_[a-fA-F0-9]{32}$').hasMatch(track.id);

String listeningRecordingId(Track track) {
  if (!isOfficialMusicTrack(track)) return '';
  final value = track.platformSongId;
  return RegExp(r'^[1-9]\d*$').hasMatch(value) ? value : '';
}

Map<String, Object?> listeningPayload(String value) {
  final decoded = jsonDecode(value);
  if (decoded is! Map) throw const FormatException('Invalid listening journal');
  return Map<String, Object?>.from(decoded);
}

class OfficialHistoryFact {
  const OfficialHistoryFact(this.recordingId, this.playCount, this.timeSeconds);
  final String recordingId;
  final int? playCount, timeSeconds;
}

class ListeningSyncSummary {
  const ListeningSyncSummary.counts({
    this.queued = 0,
    this.accepted = 0,
    this.verified = 0,
    this.uncertain = 0,
  });
  ListeningSyncSummary(Iterable<ListeningSyncEntry> rows)
    : queued = rows.where((e) => e.state == ListeningSyncState.queued).length,
      accepted = rows
          .where((e) => e.state == ListeningSyncState.accepted)
          .length,
      verified = rows
          .where((e) => e.state == ListeningSyncState.verified)
          .length,
      uncertain = rows
          .where(
            (e) =>
                e.state == ListeningSyncState.unknown ||
                e.state == ListeningSyncState.dispatched,
          )
          .length;
  final int queued, accepted, verified, uncertain;
}
