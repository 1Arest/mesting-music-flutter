import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../shared/models/track.dart';
import '../domain/platform_session.dart';
import 'music_platform_api.dart';
import 'platform_song_identity.dart';
import 'platform_quality_catalog.dart';
import 'platform_artwork.dart';
import 'platform_track_duration.dart';
import '../domain/platform_audio_quality.dart';

/// Resolves media independently of search, catalog UI and the audio engine.
/// Guest requests keep the upstream permitted-preview fallback. A membership
/// credential is never replaced with an anonymous preview after a VIP failure.
class PlatformPlaybackResolver {
  PlatformPlaybackResolver(this.api);
  final MusicPlatformApi api;
  Future<void>? _registration;

  static Map<String, dynamic> audioData(Map<String, dynamic> payload) {
    final data = payload['data'];
    return MusicPlatformApi.objectMap(
      data is List && data.isNotEmpty ? data.first : data ?? payload,
    );
  }

  static String mediaUrl(Map<String, dynamic> data) {
    final raw = data['url'] ?? data['play_url'];
    for (final candidate in raw is List ? raw : [raw]) {
      if (candidate is! String) continue;
      final uri = Uri.tryParse(candidate.trim());
      if (uri != null &&
          uri.host.isNotEmpty &&
          {'http', 'https'}.contains(uri.scheme)) {
        return uri.toString();
      }
    }
    return '';
  }

  /// Prefer measured lossy bitrate over a native adapter's requested label.
  /// Explicit lossless labels remain meaningful when bitrate is unavailable.
  static PlatformAudioQuality? deliveredQuality(Map<String, dynamic> data) {
    final raw = num.tryParse(
      '${data['bitRate'] ?? data['bit_rate'] ?? data['bitrate'] ?? ''}',
    );
    final bitrate = raw == null
        ? null
        : raw < 1000
        ? raw * 1000
        : raw;
    if (bitrate != null && bitrate > 0 && bitrate <= 400000) {
      return bitrate > 220000
          ? PlatformAudioQuality.high
          : PlatformAudioQuality.standard;
    }
    return PlatformAudioQuality.fromCode(data['quality']);
  }

  bool _sameAccount(PlatformSession? expected) =>
      api.session?.userId == expected?.userId &&
      api.session?.token == expected?.token;

  Future<void> _register() =>
      _registration ??= api.registerDevice().whenComplete(() {
        _registration = null;
      });

  Future<Track> resolve(
    Track track, {
    Future<void>? abortTrigger,
    PlatformAudioQuality quality = PlatformAudioQuality.standard,
    bool requireRequestedQuality = false,
  }) async {
    final identity = api.session;
    final abort = Completer<void>();
    var timedOut = false;
    final timer = Timer(const Duration(seconds: 40), () {
      timedOut = true;
      if (!abort.isCompleted) abort.complete();
    });
    if (abortTrigger != null) {
      unawaited(
        abortTrigger.then((_) {
          if (!abort.isCompleted) abort.complete();
        }),
      );
    }
    var registered = false;
    final query = <String, String>{
      'hash': track.id.substring('kugou_'.length).toLowerCase(),
      'quality': quality.code,
    };

    Future<Map<String, dynamic>> request(
      String path, {
      bool preview = false,
    }) async {
      if (!_sameAccount(identity)) {
        throw const MusicPlatformException('账号已变化，请重新选择歌曲');
      }
      if (abort.isCompleted) throw http.RequestAbortedException();
      final payload = await api.get(
        path,
        query: {...query, if (preview) 'free_part': '1'},
        allowBusinessError: true,
        abortTrigger: abort.future,
        expectedSession: identity,
      );
      if (!_sameAccount(identity)) {
        throw const MusicPlatformException('账号已变化，请重新选择歌曲');
      }
      return payload;
    }

    Future<Map<String, dynamic>> load(
      String path, {
      bool preview = false,
    }) async {
      var payload = await request(path, preview: preview);
      final data = audioData(payload);
      final error =
          '${data['errcode'] ?? data['error_code'] ?? payload['errcode'] ?? payload['error_code'] ?? ''}';
      if (error == '20028' && !registered) {
        registered = true;
        await _register();
        payload = await request(path, preview: preview);
      }
      return audioData(payload);
    }

    Track resolved(Map<String, dynamic> data, {bool preview = false}) {
      final fail = data['fail_process'];
      if (requireRequestedQuality) {
        if (preview || (fail is List && fail.contains('buy'))) {
          throw const MusicPlatformException('需要会员／相应权限');
        }
        // Some native adapters stamp the requested tier into `quality` when
        // upstream omits it. A supplied measured bitrate must take precedence
        // for lossy sources; otherwise a 320kbps stream can claim 128 success.
        final delivered = deliveredQuality(data);
        if (delivered == null) {
          throw const MusicPlatformException('平台未确认所选音质，已保留原音源');
        }
        if (delivered != quality) {
          throw const MusicPlatformException('平台暂未提供所选音质，已保留原音源');
        }
      }
      final size =
          int.tryParse('${data['fileSize'] ?? data['file_size'] ?? 0}') ?? 0;
      final isPreview =
          preview ||
          (fail is List && fail.contains('buy')) ||
          (size > 0 && size < 200 * 1024);
      return track.copyWith(
        // A permitted preview's short stream length is not the song's total.
        duration: isPreview ? null : PlatformTrackDuration.fromFields(data),
        audioAsset: mediaUrl(data),
        audioOrigin: AudioOrigin(AudioOrigin.kugou, track.id),
        coverAsset: PlatformArtwork.fromPayload(data).isEmpty
            ? track.coverAsset
            : PlatformArtwork.fromPayload(data),
        playbackQuality: deliveredQuality(data)?.code ?? '',
        platformSongId: PlatformSongIdentity.fromPayload(data).isEmpty
            ? track.platformSongId
            : PlatformSongIdentity.fromPayload(data),
        isPreview: isPreview,
        availabilityMessage: preview ? '平台提供的试听片段' : '',
      );
    }

    try {
      if (requireRequestedQuality) {
        // Metadata describes resources independently of membership. Use the
        // selected encoding's hash instead of reusing the current FLAC hash.
        final metadata = await request('/audio');
        final resources = PlatformQualityCatalog.resources(metadata);
        final hash = resources[quality];
        if (hash != null) query['hash'] = hash.toLowerCase();
      }
      final vip = identity?.vipToken.isNotEmpty == true;
      for (final tier
          in requireRequestedQuality ? [quality] : quality.fallbackChain) {
        query['quality'] = tier.code;
        if (vip) {
          final data = await load('/song/url/new');
          final fail = data['fail_process'];
          if (mediaUrl(data).isNotEmpty &&
              '${data['priv_status']}' == '1' &&
              (fail is! List || fail.isEmpty) &&
              (!requireRequestedQuality ||
                  PlatformAudioQuality.fromCode(data['quality']) == quality)) {
            return resolved(data);
          }
        }
        final data = await load('/song/url');
        final fail = data['fail_process'];
        if (requireRequestedQuality) {
          if ((fail is List && fail.contains('buy')) ||
              '${data['priv_status']}' == '0') {
            throw const MusicPlatformException('需要会员／相应权限');
          }
          final delivered = PlatformAudioQuality.fromCode(data['quality']);
          if (delivered != null && delivered != quality) {
            throw const MusicPlatformException('平台暂未提供所选音质，已保留原音源');
          }
        }
        // The platform can return a trial URL for an unavailable paid tier.
        // First try the next permitted tier; do not silently label a trial as
        // the selected full-quality stream.
        if (mediaUrl(data).isNotEmpty &&
            (tier == PlatformAudioQuality.standard ||
                fail is! List ||
                !fail.contains('buy'))) {
          return resolved(data);
        }
      }
      if (!vip && !requireRequestedQuality) {
        final preview = await load('/song/url', preview: true);
        if (mediaUrl(preview).isNotEmpty) {
          return resolved(preview, preview: true);
        }
      }
      return track.copyWith(
        audioAsset: '',
        isPreview: false,
        availabilityMessage: identity == null
            ? '平台未提供游客播放或试听地址，请登录酷狗后重试'
            : '平台暂未提供可用播放地址，请核对账号权限或稍后重试',
      );
    } on http.RequestAbortedException {
      if (timedOut) throw const MusicPlatformException('获取播放地址超时，请重试');
      rethrow;
    } finally {
      timer.cancel();
    }
  }
}
