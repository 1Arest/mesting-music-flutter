import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/network/music_http_client.dart';
import '../../../core/network/music_network_diagnostics.dart';
import 'qishui_api.dart';
import 'qishui_models.dart';
import 'qishui_playback_media.dart';

/// Resolves a first-party signed player-info link without account headers.
/// Successful embedded audio is retained if an optional player-info read fails.
/// Transport, DTO parsing and stream selection have separate diagnostic stages.
class QishuiPlayerInfoLoader {
  const QishuiPlayerInfoLoader(this.client);
  final http.Client client;
  // Fixed public player-info UA from the pinned myMusic adapter. It contains
  // no installation/account identity and is separate from the signed PC UA.
  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/134.0.0.0 Safari/537.36';

  Future<Map<String, dynamic>> load(
    Map<String, dynamic> data, {
    required Duration catalogDuration,
    required Future<void>? abort,
    required bool Function() current,
  }) async {
    void check() {
      if (!current()) {
        throw const QishuiException(
          '账号已变化，请重新播放',
          kind: QishuiFailureKind.cancelled,
        );
      }
    }

    final embedded = QishuiMedia.parse(data);
    final urls = qishuiPlayerInfoUris(data);
    final models = <Object>[];
    void record(MusicNetworkOutcome outcome, {int? status}) =>
        MusicNetworkDiagnostics.shared.record(
          platform: 'qishui',
          operation: MusicNetworkOperation.playbackUrl,
          outcome: outcome,
          transport: 'dart',
          phase: MusicDiagnosticPhase.playerInfoRead,
          status: status,
          playerInfoUrls: urls.length,
        );
    check();
    // The optional link must never turn an already granted full recording
    // into an error, or require another account request before it can play.
    final hasComplete =
        catalogDuration > Duration.zero &&
        embedded.any(
          (media) =>
              media.canDecodeOfficial &&
              media.duration > Duration.zero &&
              media.duration + const Duration(seconds: 5) >= catalogDuration,
        );
    if (hasComplete) return {'media': data, 'player_models': models};
    if (urls.isEmpty && embedded.isEmpty) {
      // A 200 response may contain catalog/lyric data but no player media. Keep
      // this distinct from failed native decoding, without exporting the DTO.
      record(MusicNetworkOutcome.format);
    }
    QishuiException? failure;
    for (final uri in urls) {
      check();
      if (!qishuiTrustedPlayerInfo(uri)) {
        record(MusicNetworkOutcome.format);
        failure ??= const QishuiException(
          '汽水返回的播放资料地址暂不受支持，请导出连接诊断',
          kind: QishuiFailureKind.format,
        );
        continue;
      }
      try {
        final response = await sendMusicRequest(
          client: client,
          platform: 'qishui',
          operation: MusicNetworkOperation.playbackUrl,
          abortTrigger: abort,
          maximumResponseBytes: 2 * 1024 * 1024,
          timeout: const Duration(seconds: 16),
          retryRead: false,
          build: (cancel) =>
              http.AbortableRequest('GET', uri, abortTrigger: cancel)
                ..followRedirects = false
                ..headers.addAll(const {
                  'accept': 'application/json',
                  'user-agent': userAgent,
                }),
        );
        check();
        if (response.statusCode != 200) {
          record(MusicNetworkOutcome.http, status: response.statusCode);
          failure = QishuiException(
            '汽水播放资料请求未完成（HTTP ${response.statusCode}）',
            code: 'http_${response.statusCode}',
            kind: QishuiFailureKind.refused,
          );
          continue;
        }
        final model = jsonDecode(utf8.decode(response.bodyBytes));
        if (model == null) throw const FormatException();
        models.add(model);
        record(MusicNetworkOutcome.success, status: 200);
      } on QishuiException catch (error) {
        if (error.kind == QishuiFailureKind.cancelled) rethrow;
        failure = error;
      } on FormatException {
        record(MusicNetworkOutcome.format);
        failure = const QishuiException(
          '汽水播放资料的返回格式无法读取',
          kind: QishuiFailureKind.format,
        );
      } on Object catch (error) {
        check();
        final outcome = classifyMusicNetworkError(error);
        record(outcome);
        if (outcome == MusicNetworkOutcome.cancelled) {
          throw const QishuiException(
            '操作已取消',
            kind: QishuiFailureKind.cancelled,
          );
        }
        failure = QishuiException(
          outcome == MusicNetworkOutcome.timeout
              ? '汽水播放资料读取超时，请重试'
              : '汽水播放资料连接未完成，请重试',
          kind: outcome == MusicNetworkOutcome.timeout
              ? QishuiFailureKind.timeout
              : QishuiFailureKind.connection,
        );
      }
    }
    check();
    if (failure != null &&
        models.isEmpty &&
        !embedded.any(
          (media) => media.canDecodeOfficial && media.duration > Duration.zero,
        )) {
      throw failure;
    }
    return {'media': data, 'player_models': models};
  }
}
