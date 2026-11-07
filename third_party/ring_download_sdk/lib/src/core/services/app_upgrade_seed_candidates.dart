import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'app_upgrade_p2p_protocol.dart';

/// One authenticated download session's ordered seed generation delivery.
/// Acknowledgement covers a validated bounded local queue, never an HTTP reply
/// that has not been inspected. Closed generations are drained without reuse.
class AppUpgradeSeedCandidates {
  final _offers = <String>{};
  final _seen = <int, String>{};
  final _ended = <String>{};
  final _counts = <String, int>{};
  int acknowledged = 0;

  void register(String offer) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(offer) ||
        (!_offers.contains(offer) && _offers.length >= 2)) {
      throw const AppUpgradeP2PFailure('server_candidates_invalid');
    }
    _offers.add(offer);
  }

  List<RTCIceCandidate?> accept(Object? raw, {required String? currentOffer}) {
    if (raw is! List || raw.length > 66) {
      throw const AppUpgradeP2PFailure('server_candidates_invalid');
    }
    final seen = Map<int, String>.of(_seen);
    final ended = Set<String>.of(_ended);
    final counts = Map<String, int>.of(_counts);
    var ack = acknowledged;
    var previous = 0;
    final accepted = <RTCIceCandidate?>[];
    for (final row in raw) {
      if (row is! Map || row.length != 3 || !row.containsKey('candidate')) {
        throw const AppUpgradeP2PFailure('server_candidates_invalid');
      }
      final sequence = row['sequence'], offer = row['offer_id'];
      if (sequence is! int ||
          sequence <= previous ||
          sequence > 66 ||
          offer is! String ||
          !_offers.contains(offer)) {
        throw const AppUpgradeP2PFailure('server_candidates_invalid');
      }
      previous = sequence;
      final value = row['candidate'];
      RTCIceCandidate? candidate;
      Map<String, Object?>? normalized;
      if (value != null) {
        if (value is! Map ||
            value['candidate'] is! String ||
            (value['candidate'] as String).isEmpty ||
            !(value['candidate'] as String).startsWith('candidate:') ||
            (value['candidate'] as String).contains(RegExp(r'[\r\n\x00]')) ||
            (value['sdpMid'] != null &&
                (value['sdpMid'] is! String ||
                    (value['sdpMid'] as String).length > 64)) ||
            (value['sdpMLineIndex'] != null &&
                (value['sdpMLineIndex'] is! int ||
                    (value['sdpMLineIndex'] as int) < 0 ||
                    (value['sdpMLineIndex'] as int) > 64)) ||
            value['sdpMid'] == null && value['sdpMLineIndex'] == null ||
            value['usernameFragment'] != null &&
                (value['usernameFragment'] is! String ||
                    (value['usernameFragment'] as String).length > 256)) {
          throw const AppUpgradeP2PFailure('server_candidates_invalid');
        }
        normalized = {
          'candidate': value['candidate'],
          'sdpMid': value['sdpMid'],
          'sdpMLineIndex': value['sdpMLineIndex'],
          'usernameFragment': value['usernameFragment'],
        };
        if (utf8.encode(jsonEncode(normalized)).length > 512) {
          throw const AppUpgradeP2PFailure('server_candidates_invalid');
        }
        candidate = RTCIceCandidate(
          normalized['candidate'] as String,
          normalized['sdpMid'] as String?,
          normalized['sdpMLineIndex'] as int?,
        );
      }
      final fingerprint = jsonEncode({'offer': offer, 'candidate': normalized});
      if (seen.containsKey(sequence)) {
        if (seen[sequence] != fingerprint) {
          throw const AppUpgradeP2PFailure('server_candidates_invalid');
        }
        continue;
      }
      if (sequence <= ack ||
          ended.contains(offer) ||
          seen.length >= 66 ||
          value != null && (counts[offer] ?? 0) >= 32) {
        throw const AppUpgradeP2PFailure('server_candidates_invalid');
      }
      seen[sequence] = fingerprint;
      if (value == null) {
        ended.add(offer);
      } else {
        counts[offer] = (counts[offer] ?? 0) + 1;
      }
      ack = sequence;
      if (offer == currentOffer) accepted.add(candidate);
    }
    _seen
      ..clear()
      ..addAll(seen);
    _ended
      ..clear()
      ..addAll(ended);
    _counts
      ..clear()
      ..addAll(counts);
    acknowledged = ack;
    return accepted;
  }
}
