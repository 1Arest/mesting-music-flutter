import '../domain/platform_audio_quality.dart';
import 'music_platform_api.dart';

/// Resource existence and account entitlement are independent. Only positive
/// file hashes/explicit resource records establish a tier; VIP flags never
/// manufacture one. Missing metadata stays unknown and is retryable.
class PlatformQualityCatalog {
  static Set<PlatformAudioQuality> parse(Object? payload) {
    final result = resources(payload).keys.toSet();
    if (result.isEmpty) throw const MusicPlatformException('暂未获取到歌曲音质信息，请重试');
    return Set.unmodifiable(result);
  }

  /// Preserve each tier's resource identity. Asking for 128 kbps with a FLAC
  /// hash can legitimately return that same FLAC, despite the quality argument.
  static Map<PlatformAudioQuality, String> resources(Object? payload) {
    final result = <PlatformAudioQuality, String>{};
    const keys = {
      PlatformAudioQuality.standard: [
        'hash_128',
        'Hash128',
        '128Hash',
        'sd_hash',
        'ogg_128_hash',
      ],
      PlatformAudioQuality.high: [
        'hash_320',
        'Hash320',
        '320Hash',
        'hq_hash',
        'HQHash',
        'ogg_320_hash',
      ],
      PlatformAudioQuality.lossless: [
        'hash_flac',
        'flac_hash',
        'sq_hash',
        'SQHash',
        'hash_sq',
        'hash_lossless',
      ],
      PlatformAudioQuality.hiRes: [
        'hash_high',
        'high_hash',
        'hires_hash',
        'hash_hires',
        'HiResHash',
      ],
    };
    bool positive(Object? value) =>
        value is String &&
        value.trim().isNotEmpty &&
        !RegExp(r'^0+$').hasMatch(value.trim());
    void visit(Object? node, int depth) {
      if (depth > 7) return;
      if (node is List) {
        for (final entry in node) {
          visit(entry, depth + 1);
        }
      } else if (node is Map) {
        final explicitTier = PlatformAudioQuality.fromCode(node['quality']);
        if (positive(node['hash']) &&
            (explicitTier == null ||
                explicitTier == PlatformAudioQuality.standard)) {
          result.putIfAbsent(
            PlatformAudioQuality.standard,
            () => '${node['hash']}',
          );
        }
        for (final tier in keys.entries) {
          for (final key in tier.value) {
            if (positive(node[key])) result[tier.key] = '${node[key]}';
          }
        }
        final tier = PlatformAudioQuality.fromCode(node['quality']);
        if (tier != null && positive(node['hash'])) {
          result[tier] = '${node['hash']}';
        }
        for (final key in [
          'data',
          'audio_info',
          'info',
          'list',
          'audio',
          'trans_param',
          'qualities',
          'resources',
        ]) {
          visit(node[key], depth + 1);
        }
      }
    }

    visit(payload, 0);
    return Map.unmodifiable(result);
  }
}
