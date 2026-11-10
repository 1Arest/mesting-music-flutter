import 'dart:io';
import '../../p8p/window.dart';
import '../../p8p/transfer_protocol.dart';

/// Native network facts, deliberately independent of download eligibility.
/// All networks may receive; only positively identified unmetered Wi-Fi uploads.
enum AppUpgradeP2PNetwork {
  wifiUnmetered('wifi_unmetered'),
  wifiMetered('wifi_metered'),
  cellular('cellular'),
  unknown('unknown');

  const AppUpgradeP2PNetwork(this.wireName);
  final String wireName;
  bool get mayShare => this == wifiUnmetered;

  static AppUpgradeP2PNetwork fromNative(Object? value) => values.firstWhere(
    (network) => network.wireName == value,
    orElse: () => unknown,
  );

  Map<String, Object?> heartbeat(Iterable<int> verifiedPieces) => {
    'network': wireName,
    'share_enabled': mayShare,
    'pieces': mayShare ? (verifiedPieces.toList()..sort()) : <int>[],
  };
}

/// Only fixed, non-sensitive reason codes cross the logging boundary.
class AppUpgradeP2PFailure implements Exception {
  const AppUpgradeP2PFailure(this.code);
  final String code;
  @override
  String toString() => 'P2P: $code';
}

/// Validates the service contract before any session or WebRTC object is made.
/// The backend-selected URL remains the HTTPS source; fallbackUrl is metadata.
class AppUpgradeP2PManifest {
  const AppUpgradeP2PManifest({
    required this.fileSize,
    required this.sha256,
    required this.pieceHashes,
    required this.stunUrls,
    required this.apiBase,
    required this.serverSeedUrl,
    this.trickleIce = false,
    this.serverOfferCancel = false,
    this.serverTrickle = false,
    this.candidateBatch = false,
    this.attemptDiagnostics = false,
    this.peerCandidateReplacement = false,
    this.peerCandidateIdentity = false,
    this.sharedDeadline = false,
    this.p8pAdaptiveWindow = false,
    this.p8pTransfer = false,
    this.fastSignalPollMs,
    this.connectTimeout = const Duration(seconds: 8),
    this.iceGatherTimeout = const Duration(seconds: 6),
  });

  static const chunkSize = 1024 * 1024;
  static const channelLabel = 'lifering-apk-p2p-v1';
  static const maxFrameBytes = 48 * 1024;
  // Keep signaling independent of the business-selected HTTPS download source.
  static const serviceOrigin = 'https://download1.csnas.asia';
  static const allowedHosts = {'download.csnas.asia', 'download1.csnas.asia'};
  static final _shaPattern = RegExp(r'^[a-f0-9]{64}$');

  final int fileSize;
  final String sha256;
  final List<String> pieceHashes;
  final List<String> stunUrls;
  final String apiBase;
  final String serverSeedUrl;
  final bool trickleIce;
  final bool serverOfferCancel;
  final bool serverTrickle;
  final bool candidateBatch, attemptDiagnostics, sharedDeadline;
  final bool peerCandidateReplacement;
  final bool peerCandidateIdentity;
  final bool p8pAdaptiveWindow;
  final bool p8pTransfer;
  final int? fastSignalPollMs;
  final Duration connectTimeout;
  final Duration iceGatherTimeout;

  int pieceSize(int index) {
    if (index < 0 || index >= pieceHashes.length) return 0;
    return (fileSize - index * chunkSize).clamp(0, chunkSize);
  }

  static String? originForDownload(String url, String slug) {
    if (!RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$').hasMatch(slug)) return null;
    final uri = Uri.tryParse(url);
    if (!_trustedUri(uri) || uri!.path != '/$slug/download') return null;
    return 'https://${uri.host.toLowerCase()}';
  }

  static bool _trustedUri(Uri? uri) =>
      uri != null &&
      uri.scheme == 'https' &&
      allowedHosts.contains(uri.host.toLowerCase()) &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || uri.port == 443) &&
      uri.fragment.isEmpty;

  /// STUN uses an opaque URI (RFC 7064), so Dart's Uri.host is normally empty.
  /// Validate its host/port grammar instead of treating it as an HTTPS URL.
  static bool isStunUrl(String value) {
    final match = RegExp(
      r'^(stun|stuns):(\[[0-9a-fA-F:]+\]|[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?)(?::([0-9]{1,5}))?$',
    ).firstMatch(value);
    if (match == null) return false;
    final host = match.group(2)!;
    if (host.startsWith('[') &&
        InternetAddress.tryParse(host.substring(1, host.length - 1))?.type !=
            InternetAddressType.IPv6) {
      return false;
    }
    final port = match.group(3);
    return port == null || (int.parse(port) > 0 && int.parse(port) <= 65535);
  }

  /// Parse an optional Android build identity consistently for health/manifest.
  /// Missing values preserve legacy compatibility; malformed advertised values
  /// fail closed. Do not invent a build from a version name or release ID.
  static int? readAndroidVersionCode(Map<String, dynamic> json) {
    final code = json['android_version_code'];
    if (code == null) return null;
    final major = json['android_version_code_major'] ?? 0;
    final longCode = json['android_long_version_code'];
    if (code is! int ||
        code <= 0 ||
        code > 0x7fffffff ||
        major is! int ||
        major != 0 ||
        (longCode != null && longCode.toString() != '$code')) {
      throw const AppUpgradeP2PFailure('manifest_build_mismatch');
    }
    return code;
  }

  static AppUpgradeP2PManifest parse(
    Map<String, dynamic> json, {
    required String origin,
    required String slug,
    required String version,
    int? versionCode,
    required int fileSize,
    required String sha256,
  }) {
    void require(bool condition, String code) {
      if (!condition) throw AppUpgradeP2PFailure(code);
    }

    require(json['status'] == 'ok', 'manifest_disabled');
    require(json['auto_start'] != false, 'manifest_auto_start_disabled');
    require(json['protocol_version'] == 1, 'manifest_protocol_unsupported');
    require(json['app_slug'] == slug, 'manifest_slug_mismatch');
    require(json['version'] == version, 'manifest_version_mismatch');
    // Compare two artifact identities: health vs manifest, never the business
    // release's update threshold. Older services may omit the actual build.
    final manifestBuild = readAndroidVersionCode(json);
    if (versionCode != null && manifestBuild != null) {
      require(manifestBuild == versionCode, 'manifest_build_mismatch');
    }
    require(
      fileSize > 0 && json['file_size'] == fileSize,
      'manifest_size_mismatch',
    );
    final digest = sha256.toLowerCase();
    require(
      _shaPattern.hasMatch(digest) && json['sha256'] == digest,
      'manifest_sha_mismatch',
    );
    require(json['chunk_size'] == chunkSize, 'manifest_chunk_size_invalid');
    final hashes = json['piece_hashes'];
    require(
      hashes is List &&
          hashes.length == (fileSize + chunkSize - 1) ~/ chunkSize &&
          hashes.every(
            (value) => value is String && _shaPattern.hasMatch(value),
          ),
      'manifest_piece_hashes_invalid',
    );
    final stun = json['stun_urls'];
    require(
      stun is List &&
          stun.isNotEmpty &&
          stun.every((value) => value is String && isStunUrl(value)),
      'manifest_stun_invalid',
    );
    final apiPath = '/api/app/$slug/p2p';
    final api = json['peer_api_base'];
    require(
      api == apiPath ||
          api == '$origin$apiPath' ||
          api == '$serviceOrigin$apiPath',
      'manifest_api_base_invalid',
    );
    final seed = Uri.tryParse('${json['server_seed_url'] ?? ''}');
    require(
      _trustedUri(seed) && seed!.path == '$apiPath/server-offer',
      'manifest_seed_url_invalid',
    );
    require(
      originForDownload('${json['fallback_url'] ?? ''}', slug) != null,
      'manifest_fallback_url_invalid',
    );
    return AppUpgradeP2PManifest(
      fileSize: fileSize,
      sha256: digest,
      pieceHashes: List<String>.unmodifiable((hashes as List).cast<String>()),
      stunUrls: List<String>.unmodifiable((stun as List).cast<String>()),
      apiBase: '$serviceOrigin$apiPath',
      serverSeedUrl: '$serviceOrigin$apiPath/server-offer',
      trickleIce:
          json['trickle_ice_supported'] == true &&
          json['trickle_ice_protocol_version'] == 1,
      candidateBatch: json['candidate_batch_supported'] == true,
      serverTrickle:
          json['server_trickle_candidates_supported'] == true &&
          json['server_trickle_protocol_version'] is int &&
          json['server_trickle_protocol_version'] == 1 &&
          json['trickle_ice_supported'] == true &&
          json['trickle_ice_protocol_version'] == 1,
      serverOfferCancel:
          json['server_offer_cancel_supported'] == true &&
          json['server_offer_cancel_protocol_version'] is int &&
          json['server_offer_cancel_protocol_version'] == 1,
      attemptDiagnostics: json['attempt_diagnostics_supported'] == true,
      peerCandidateReplacement:
          json['peer_candidate_replacement_supported'] == true,
      peerCandidateIdentity: json['peer_candidate_identity_supported'] == true,
      sharedDeadline: json['peer_shared_deadline_supported'] == true,
      p8pAdaptiveWindow: P8PWindowProtocol.advertised(json['p8p']),
      p8pTransfer: P8PTransferProtocol.advertised(json['p8p']),
      fastSignalPollMs:
          json['peer_fast_signal_poll_ms'] is int &&
              (json['peer_fast_signal_poll_ms'] as int) >= 100 &&
              (json['peer_fast_signal_poll_ms'] as int) <= 250
          ? json['peer_fast_signal_poll_ms'] as int
          : null,
      // Never let remote configuration extend the user-visible fallback budget.
      connectTimeout: Duration(
        milliseconds: json['p2p_connect_timeout_ms'] is int
            ? (json['p2p_connect_timeout_ms'] as int).clamp(1, 8000)
            : 8000,
      ),
      iceGatherTimeout: Duration(
        milliseconds: json['p2p_ice_gather_timeout_ms'] is int
            ? (json['p2p_ice_gather_timeout_ms'] as int).clamp(1, 6000)
            : 6000,
      ),
    );
  }

  /// Both single and batch requests share this validator. Fractional, duplicate
  /// and out-of-range indices never reach a file read or an upload queue.
  List<int> requestedIndices(Map<String, dynamic> message) {
    final Object? raw = switch (message['type']) {
      'get-piece' => [message['index']],
      'get-pieces' => message['indices'],
      _ => null,
    };
    if (raw is! List ||
        raw.isEmpty ||
        raw.length > 4 ||
        raw.any((value) => value is! int)) {
      throw const AppUpgradeP2PFailure('invalid_request');
    }
    final indices = raw.cast<int>();
    if (indices.toSet().length != indices.length ||
        indices.any((index) => pieceSize(index) == 0)) {
      throw const AppUpgradeP2PFailure('invalid_piece');
    }
    return indices;
  }
}
