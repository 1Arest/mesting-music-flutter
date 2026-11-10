import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// P2P logs use a closed schema. Never pass request/response maps, exceptions,
/// URLs, SDP, credentials, identifiers or candidate addresses to this class.
class AppUpgradeP2PDiagnostic {
  const AppUpgradeP2PDiagnostic({
    required this.stage,
    required this.code,
    this.status,
    this.peerCount,
    this.peerBytes,
    this.seedBytes,
    this.verified,
    this.task,
    this.elapsedMs,
    this.durationMs,
    this.source,
    this.attempt,
    this.appVersion,
    this.eligiblePeerCount,
    this.verifiedPieces,
    this.verifiedBytes,
    this.expectedBytes,
    this.actualBytes,
    this.metrics = const {},
  });
  final String stage;
  final String code;
  final int? status;
  final int? peerCount;
  final int? peerBytes;
  final int? seedBytes;
  final bool? verified;
  // Process-local sequence, not a device/session/idempotency identifier.
  final int? task;
  final int? elapsedMs, durationMs;
  final String? source, appVersion, attempt;
  final int? eligiblePeerCount, verifiedPieces, verifiedBytes;
  // Artifact sizes diagnose stale metadata without exposing headers or identity.
  final int? expectedBytes, actualBytes;
  // Local aggregate diagnostics only. Keep this separate from the server's
  // negotiated outcome schema so older services remain compatible.
  final Map<String, int> metrics;
  static const _metricKeys = {
    'peer_race_limit',
    'peak_ordinary_peer_owners',
    'attempt_native_ready',
    'attempt_offer_accepted',
    'attempt_answer_seen',
    'attempt_remote_sdp_applied',
    'attempt_local_trickle_posted',
    'attempt_remote_trickle_applied',
    'attempt_local_candidate_types',
    'attempt_remote_candidate_types',
    'attempt_ice_state',
    'attempt_channel_opened',
    'attempt_first_body_seen',
    'ice_stats_sampled',
    'ice_stats_age_ms',
    'ice_pair_count',
    'ice_pairs_truncated',
    'ice_requests_sent',
    'ice_requests_received',
    'ice_responses_sent',
    'ice_responses_received',
    'ice_pairs_succeeded',
    'admitted_peer_limit',
    'request_timeout_us',
    'reserved_slots',
    'snapshot_sequence',
    'slot_position',
    'slot_phase',
    'piece_ahead',
    'body_bytes',
    'body_expected_bytes',
    'request_age_us',
    'request_remaining_us',
    'owner_closed',
    'source_peer1_requests',
    'source_peer1_verified_bytes',
    'source_peer1_busy_us',
    'source_peer1_cancelled',
    'source_peer1_failures',
    'source_peer2_requests',
    'source_peer2_verified_bytes',
    'source_peer2_busy_us',
    'source_peer2_cancelled',
    'source_peer2_failures',
    'source_peer3_requests',
    'source_peer3_verified_bytes',
    'source_peer3_busy_us',
    'source_peer3_cancelled',
    'source_peer3_failures',
    'source_peer4_requests',
    'source_peer4_verified_bytes',
    'source_peer4_busy_us',
    'source_peer4_cancelled',
    'source_peer4_failures',
    'source_seed_requests',
    'source_seed_verified_bytes',
    'source_seed_busy_us',
    'source_seed_cancelled',
    'source_seed_failures',
    'source_https_requests',
    'source_https_verified_bytes',
    'source_https_busy_us',
    'source_https_cancelled',
    'source_https_failures',
    'piece_verify_us',
    'piece_verify_calls',
    'piece_write_us',
    'piece_write_calls',
    'piece_flush_us',
    'piece_flush_calls',
    'piece_open_count',
    'persisted_bytes',
    'source_wait_us',
    'steady_source_wait_us',
    'full_sha_us',
    'full_sha_scans',
    'p8p_window',
    'requests',
    'prefix_rescues',
    'source_recoveries',
    'source_rejoins',
    'hedges',
    'verified_bytes',
    'source_failures',
    'source_deferred',
    'cleanup_failures',
    'peak_reservations',
    'peak_reserved_bytes',
    'repeat_reserved_bytes',
  };

  Map<String, Object?> toJson() => {
    'at': DateTime.now().toUtc().toIso8601String(),
    'stage': safeCode(stage),
    'code': safeCode(code),
    if (status != null) 'http_status': status,
    if (peerCount != null) 'peer_count': peerCount,
    if (peerBytes != null) 'peer_bytes': peerBytes,
    if (seedBytes != null) 'seed_bytes': seedBytes,
    if (verified != null) 'verified': verified,
    if (task != null) 'task': task,
    if (elapsedMs != null) 'elapsed_ms': elapsedMs,
    if (durationMs != null) 'duration_ms': durationMs,
    if (source != null) 'source': safeCode(source!),
    if (const {
      'peer1',
      'peer2',
      'peer3',
      'peer4',
      'seed',
      'seed2',
    }.contains(attempt))
      'attempt': attempt,
    if (appVersion != null &&
        RegExp(r'^[A-Za-z0-9._+\-]{1,40}$').hasMatch(appVersion!))
      'app_version': appVersion,
    if (eligiblePeerCount != null) 'eligible_peer_count': eligiblePeerCount,
    if (verifiedPieces != null) 'verified_pieces': verifiedPieces,
    if (verifiedBytes != null) 'verified_bytes': verifiedBytes,
    if (expectedBytes != null) 'expected_bytes': expectedBytes,
    if (actualBytes != null) 'actual_bytes': actualBytes,
    if (metrics.isNotEmpty)
      'metrics': {
        for (final entry in metrics.entries)
          if (_metricKeys.contains(entry.key) &&
              entry.value >= 0 &&
              entry.value <= (1 << 60) &&
              (entry.key != 'p8p_window' ||
                  (entry.value >= 1 && entry.value <= 4)))
            entry.key: entry.value,
      },
  };

  // A fixed vocabulary also excludes opaque credentials composed only of
  // letters/digits. A formatting regex alone would not provide that guarantee.
  static const _vocabulary = {
    'p8p',
    'p8p_window_selected',
    'multisource_started',
    'multisource_profile',
    'peer_race_profile',
    'peer_staggered_probe',
    'peer_failure_detail',
    'ice_candidate_grace',
    'source_profile',
    'window_changed',
    'offer_post_started',
    'offer_accepted',
    'remote_description_applied',
    'remote_candidate_applied',
    'first_local_candidate_posted',
    'first_payload_received',
    'channel_wait_started',
    'performance',
    'transfer_profile',
    'file_hash_profile',
    'verified_hash_reused',
    'https_file_promoted',
    'https_file_copied',
    'verified_https_hash_reused',
    'file_write_failed',
    'attempt',
    'race_lost',
    'seed_waiting_for_peers',
    'pipeline_four_selected',
    'https_completed',
    'health',
    'metadata_refreshed',
    'metadata_compared',
    'health_unavailable',
    'health_metadata_invalid',
    'artifact_not_newer',
    'ice_gather',
    'ice_connection',
    'rtc',
    'peer_connect',
    'seed_connect',
    'transfer',
    'request_deadline_exceeded',
    'stop_grace_exceeded',
    'source_cleanup_failed',
    'source_completed',
    'source_stopped',
    'source_busy',
    'source_failed',
    'prefix_rescued',
    'hello_ready', 'piece_request_allocated', 'piece_request_enqueued',
    'first_piece_header', 'rescue_slot',
    'invalid_piece_size',
    'piece_identity_mismatch',
    'discovered',
    'no_peer_available',
    'no_matching_piece',
    'eligible_peers',
    'request_started',
    'peer_upload_report',
    'native_transport_released',
    'native_close_timeout',
    'native_close_failed',
    'native_dispose_timeout',
    'native_dispose_failed',
    'retry',
    'offer_ready',
    'answer_received',
    'hybrid',
    'probe_verified',
    'https_nearly_complete',
    'source_selected',
    'batch_six_selected',
    'answer_ready',
    'ice_new',
    'ice_gathering',
    'ice_complete',
    'ice_checking',
    'ice_connected',
    'ice_completed',
    'ice_disconnected',
    'ice_closed',
    'channel_connecting',
    'channel_open',
    'channel_closing',
    'rtc_operation_timeout',
    'peer_connect_timeout',
    'peer_transfer_timeout',
    'peer_integrity_error',
    'server_seed_connect_timeout',
    'server_seed_transfer_timeout',
    'server_seed_integrity_error',
    'outcome_conflict',
    'idempotency_conflict',
    'p2p_session_already_active',
    'invalid_idempotency_key',
    'routing',
    'manifest',
    'session',
    'peers',
    'peer',
    // This fixed protocol decision exposes no peer/session identity.
    'batch_four_selected',
    'seed',
    'sharing',
    'signal',
    'signals',
    'server_offer',
    'candidate',
    'server_candidate',
    'server_candidates_invalid',
    'p2p_budget_exhausted',
    'server_offer_timeout',
    'server_cancel',
    'seed_connect_retry',
    'seed_connect_retry_timeout',
    'server_offer_cancel_pending',
    'server_offer_cancel_capacity',
    'server_offer_cancel_unavailable',
    'offer_cancelled',
    'candidate_queue_full',
    'candidate_too_large',
    'invalid_candidate',
    'invalid_offer_id',
    'candidate_processing_timeout',
    'server_candidate_offer_limit',
    'p2p_session_invalid',
    'invalid_p2p_diagnostics',
    'heartbeat',
    'network',
    'channel',
    'result',
    'result_reason',
    'outcome',
    'leave',
    'final',
    'https',
    'source_not_p2p',
    'platform_unsupported',
    'legacy_source_selected',
    'manifest_disabled',
    'manifest_auto_start_disabled',
    'manifest_protocol_unsupported',
    'manifest_slug_mismatch',
    'manifest_version_mismatch',
    'manifest_build_mismatch',
    'metadata',
    'release_metadata_refreshed',
    'transient_download_limit',
    'p8p_contention_wait',
    'download_quota_limit',
    'https_etag_mismatch',
    'https_range_mismatch',
    'https_body_oversized',
    'https_body_incomplete',
    'https_response_rejected',
    'service_main',
    'service_backup',
    'cos',
    'manifest_size_mismatch',
    'manifest_sha_mismatch',
    'manifest_chunk_size_invalid',
    'manifest_piece_hashes_invalid',
    'manifest_stun_invalid',
    'manifest_api_base_invalid',
    'manifest_seed_url_invalid',
    'manifest_fallback_url_invalid',
    'invalid_request',
    'invalid_piece',
    'validated',
    'http_ok',
    'started',
    'cache_verified',
    'partial_https_prefix',
    'file_checksum_mismatch',
    'file_verified',
    'sharing_network_disallowed',
    'sharing_expired',
    'sharing_stopped',
    'sharing_unavailable',
    'cache_available',
    'session_response_invalid',
    'peers_response_invalid',
    'signals_response_invalid',
    'sources_unavailable',
    'piece_verified',
    'session_stopped',
    'peer_capacity',
    'server_offer_attempt_limit',
    'server_answer_invalid',
    'local_sdp_invalid',
    'ice_gather_timeout',
    'ice_failed',
    'channel_missing',
    'channel_closed',
    'signal_invalid',
    'unexpected_binary',
    'invalid_message',
    'unexpected_control',
    'busy',
    'upload_timeout',
    'upload_send_timeout',
    'upload_queue_timeout',
    'upload_buffer_query_timeout',
    'upload_buffer_unavailable',
    'batch_sent',
    'sharing_wifi_available',
    'sharing_disabled',
    'session_unauthorized',
    'http_error',
    'client_interrupted',
    'local_cache_complete',
    'p2p_complete',
    'https_fallback',
    'source_timeout',
    'local_storage_error',
    'http_timeout',
    'request_cancelled',
    'network_error',
    'protocol_error',
    'p2p_disabled',
    'release_changed',
    'release_not_available',
    'application_package_conflict',
    'p2p_app_client_required',
    'peer_not_shareable',
    'peer_not_available',
    'signal_queue_full',
    'server_seed_busy',
    'server_seed_unavailable',
    'invalid_offer',
    'piece_unavailable',
    'seed_send_failed',
    'session_capacity_exceeded',
    'rate_limited',
    'invalid_session',
    'network_not_allowed',
    'invalid_network',
    'invalid_sha256',
    'invalid_piece_header',
    'invalid_piece_frame',
    'piece_length_mismatch',
    'piece_checksum_mismatch',
    'prefix_changed',
    'apk_verified',
    'download_failed',
    'http_response',
    'unknown_error',
  };
  static String safeCode(String value) =>
      _vocabulary.contains(value) ? value : 'unknown_error';
}

class AppUpgradeP2PDiagnostics {
  static const _key = 'app_upgrade.p2p.diagnostics';
  static Future<void> _pendingWrite = Future<void>.value();
  static Future<String>? _installedVersion;

  /// Send the running client version, not the target APK's version. No device
  /// or installation identifier is included in this metadata.
  static Future<String> clientVersion() =>
      _installedVersion ??= _loadInstalledVersion();

  static Future<String> _loadInstalledVersion() async {
    try {
      final info = await PackageInfo.fromPlatform().timeout(
        const Duration(seconds: 1),
      );
      final value = '${info.version}+${info.buildNumber}';
      return RegExp(r'^[A-Za-z0-9._+\-]{1,40}$').hasMatch(value)
          ? value
          : 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  /// Persist asynchronously, serialize writes, and cap disk use. Logging must
  /// never delay downloading or become an unhandled asynchronous error.
  static void record(AppUpgradeP2PDiagnostic event) {
    final encoded = jsonEncode(event.toJson());
    debugPrint('[AppUpgradeP2P] $encoded');
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final entries = [...?prefs.getStringList(_key), encoded];
        if (entries.length > 200) entries.removeRange(0, entries.length - 200);
        await prefs.setStringList(_key, entries);
      } catch (_) {
        // Disk/plugin availability is unrelated to the download result.
      }
    });
  }

  static Future<List<Object?>> read() async {
    await _pendingWrite;
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_key) ?? [])
          .map<Object?>((raw) {
            try {
              return jsonDecode(raw);
            } catch (_) {
              return null;
            }
          })
          .where((entry) => entry != null)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
