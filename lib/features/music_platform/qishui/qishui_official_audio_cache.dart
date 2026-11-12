import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../core/network/music_network_diagnostics.dart';
import '../netease/fallback/netease_audio_probe.dart';
import 'qishui_api.dart';
import 'qishui_models.dart';
import 'qishui_native_audio_failure.dart';

/// Temporary playback material, not a user download or a grant of download
/// rights. The repository must first validate official ownership/entitlements.
/// CDN requests are anonymous and never inherit API Cookies or signing headers.
class QishuiOfficialAudioCache {
  QishuiOfficialAudioCache(
    this.client, {
    MethodChannel? channel,
    Future<Directory> Function()? temporaryDirectory,
  }) : _channel = channel ?? channelDefault,
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  static const channelDefault = MethodChannel(
    'com.mesting.music/qishui_official_audio',
  );
  static const directoryName = 'qishui_official_audio';
  static const maximumBytes = 128 * 1024 * 1024;
  static const maximumCacheBytes = 512 * 1024 * 1024;
  static int _reservedBytes = 0;
  static final _recentPaths = <String>[];
  final http.Client client;
  final MethodChannel _channel;
  final Future<Directory> Function() _temporaryDirectory;

  /// Returns an absolute private temporary path. Callers put only this path
  /// (never PlayAuth/key/URL credentials) in the current playback Track.
  Future<String> resolve(
    QishuiMedia media, {
    required String ownerKey,
    required String trackId,
    required Future<void> abort,
    required bool Function() current,
  }) async {
    if (ownerKey.isEmpty || trackId.isEmpty || !current()) {
      throw const QishuiException(
        '账号已变化，请重新播放',
        kind: QishuiFailureKind.cancelled,
      );
    }
    if (!media.canDecodeOfficial || media.duration <= Duration.zero) {
      throw const QishuiException(
        '汽水返回的加密音频暂不受支持',
        kind: QishuiFailureKind.format,
      );
    }
    final uri = Uri.tryParse(media.url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        media.fileSize > maximumBytes) {
      throw const QishuiException(
        '汽水音频地址或大小无效',
        kind: QishuiFailureKind.format,
      );
    }
    final cancelled = Completer<void>();
    var completed = false;
    var externalCancel = false;
    final id = List.generate(
      16,
      (_) => Random.secure().nextInt(256),
    ).map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    unawaited(
      abort.then((_) {
        if (completed) return;
        externalCancel = true;
        if (!cancelled.isCompleted) cancelled.complete();
        unawaited(
          _channel
              .invokeMethod<void>('cancel', {'id': id})
              .catchError((Object _) {}),
        );
      }),
    );
    var timedOut = false;
    final timer = Timer(const Duration(minutes: 3), () {
      if (completed) return;
      timedOut = true;
      if (!cancelled.isCompleted) cancelled.complete();
      unawaited(
        _channel
            .invokeMethod<void>('cancel', {'id': id})
            .catchError((Object _) {}),
      );
    });
    void check() {
      if (timedOut) {
        throw const QishuiException(
          '汽水音频读取超时，请重试',
          kind: QishuiFailureKind.timeout,
        );
      }
      if (externalCancel || !current()) {
        throw const QishuiException(
          '账号或播放选择已变化，操作已取消',
          kind: QishuiFailureKind.cancelled,
        );
      }
    }

    File? source;
    File? output;
    IOSink? sink;
    var published = false;
    var reservation = 0;
    var phase = MusicDiagnosticPhase.audioRead;
    QishuiNativeAudioFailure? nativeFailure;
    void record(MusicNetworkOutcome outcome) =>
        MusicNetworkDiagnostics.shared.record(
          platform: 'qishui',
          operation: MusicNetworkOperation.audio,
          outcome: outcome,
          transport: phase == MusicDiagnosticPhase.audioRead
              ? 'dart'
              : 'nativeAudio',
          phase: phase,
          family: nativeFailure?.family,
          nativeStep: nativeFailure?.step,
          nativeReason: nativeFailure?.reason,
        );
    try {
      await Future<void>.value();
      check();
      final root = Directory(
        '${(await _temporaryDirectory()).path}/$directoryName',
      );
      await root.create(recursive: true);
      final used = await _removeExpiredFiles(root);
      reservation = 2 * (media.fileSize > 0 ? media.fileSize : maximumBytes);
      if (used + _reservedBytes + reservation > maximumCacheBytes) {
        reservation = 0;
        throw const QishuiException(
          '汽水临时播放缓存已满，请稍后重试',
          kind: QishuiFailureKind.operation,
        );
      }
      _reservedBytes += reservation;
      source = File('${root.path}/$id.source');
      output = File('${root.path}/$id.m4a');
      final response = await client
          .send(
            http.AbortableRequest('GET', uri, abortTrigger: cancelled.future)
              ..followRedirects = false
              ..headers.addAll(const {
                'Accept': 'audio/*,application/octet-stream',
                'Accept-Encoding': 'identity',
              }),
          )
          .timeout(const Duration(seconds: 20));
      check();
      // Full-file CENC cannot be decoded from an accepted 206/partial body.
      if (response.statusCode != 200) {
        await response.stream.listen((_) {}).cancel();
        throw QishuiException(
          '汽水音频请求未完成（HTTP ${response.statusCode}）',
          code: response.statusCode == 403
              ? 'media_http_403'
              : 'http_${response.statusCode}',
          kind: response.statusCode == 401
              ? QishuiFailureKind.authentication
              : {301, 403, 404, 410}.contains(response.statusCode)
              ? QishuiFailureKind.refused
              : QishuiFailureKind.connection,
        );
      }
      final type = (response.headers['content-type'] ?? '').toLowerCase();
      if (type.contains('text/') ||
          type.contains('json') ||
          type.contains('html')) {
        await response.stream.listen((_) {}).cancel();
        throw const QishuiException(
          '汽水返回的内容不是音频',
          kind: QishuiFailureKind.format,
        );
      }
      final declared = int.tryParse(response.headers['content-length'] ?? '');
      if (declared != null && (declared <= 0 || declared > maximumBytes)) {
        await response.stream.listen((_) {}).cancel();
        throw const QishuiException(
          '汽水音频大小超出本次读取范围',
          kind: QishuiFailureKind.format,
        );
      }
      sink = source.openWrite();
      var count = 0;
      await for (final bytes in response.stream.timeout(
        const Duration(seconds: 20),
      )) {
        check();
        count += bytes.length;
        if (count > maximumBytes ||
            (media.fileSize > 0 && count > media.fileSize)) {
          if (!cancelled.isCompleted) cancelled.complete();
          throw const QishuiException(
            '汽水音频大小超出本次读取范围',
            kind: QishuiFailureKind.format,
          );
        }
        sink.add(bytes);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      check();
      if (count == 0 ||
          (declared != null && count != declared) ||
          (media.fileSize > 0 && count != media.fileSize)) {
        throw const QishuiException(
          '汽水音频未读取完整，请重试',
          kind: QishuiFailureKind.format,
        );
      }
      record(MusicNetworkOutcome.success);
      phase = MusicDiagnosticPhase.audioDecode;
      final result = await _channel
          .invokeMapMethod<String, Object?>('prepare', {
            'id': id,
            'source': source.path,
            'output': output.path,
            'encrypted': media.encrypted,
            'playAuth': media.encrypted ? media.playAuth : '',
          });
      check();
      if (result?['path'] != output.path || !await output.exists()) {
        throw const QishuiException(
          '汽水音频缓存未能完成',
          kind: QishuiFailureKind.format,
        );
      }
      record(MusicNetworkOutcome.success);
      phase = MusicDiagnosticPhase.audioVerify;
      await inspectFile(
        output.path,
        expectedDuration: media.duration,
        channel: _channel,
      );
      check();
      record(MusicNetworkOutcome.success);
      published = true;
      _recentPaths.add(output.absolute.path);
      if (_recentPaths.length > 16) _recentPaths.removeAt(0);
      return output.absolute.path;
    } on QishuiException catch (error) {
      record(switch (error.kind) {
        QishuiFailureKind.cancelled => MusicNetworkOutcome.cancelled,
        QishuiFailureKind.timeout => MusicNetworkOutcome.timeout,
        QishuiFailureKind.connection => MusicNetworkOutcome.connection,
        _ => MusicNetworkOutcome.format,
      });
      rethrow;
    } on TimeoutException {
      record(MusicNetworkOutcome.timeout);
      throw const QishuiException(
        '汽水音频读取超时，请重试',
        kind: QishuiFailureKind.timeout,
      );
    } on PlatformException catch (error) {
      check();
      if (error.code != 'cancelled') {
        nativeFailure = QishuiNativeAudioFailure.from(error);
      }
      record(
        error.code == 'cancelled'
            ? MusicNetworkOutcome.cancelled
            : MusicNetworkOutcome.format,
      );
      throw QishuiException(
        error.code == 'cancelled' ? '操作已取消' : nativeFailure!.message,
        kind: error.code == 'cancelled'
            ? QishuiFailureKind.cancelled
            : QishuiFailureKind.format,
      );
    } on MissingPluginException catch (error) {
      check();
      nativeFailure = QishuiNativeAudioFailure.from(error);
      record(MusicNetworkOutcome.format);
      throw QishuiException(
        nativeFailure.message,
        kind: QishuiFailureKind.format,
      );
    } on Object {
      check();
      record(MusicNetworkOutcome.connection);
      throw const QishuiException(
        '汽水音频读取未完成，请重试',
        kind: QishuiFailureKind.connection,
      );
    } finally {
      completed = true;
      timer.cancel();
      _reservedBytes -= reservation;
      if (!cancelled.isCompleted) cancelled.complete();
      await sink?.close();
      if (source != null && await source.exists()) await source.delete();
      if (!published && output != null && await output.exists()) {
        await output.delete();
      }
    }
  }

  /// Touch only this adapter's random files. Retain recent playback paths and
  /// every file newer than 24h; if no safe eviction exists, admission refuses
  /// extra space rather than deleting a file an active player may still use.
  static Future<int> _removeExpiredFiles(Directory root) async {
    final expiry = DateTime.now().subtract(const Duration(hours: 24));
    var total = 0;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File ||
          !RegExp(
            r'^[0-9a-f]{32}\.(source|m4a)$',
          ).hasMatch(entity.uri.pathSegments.last)) {
        continue;
      }
      final stat = await entity.stat();
      if (stat.type != FileSystemEntityType.file) continue;
      if (stat.modified.isBefore(expiry) &&
          !_recentPaths.contains(entity.absolute.path)) {
        try {
          await entity.delete();
        } on FileSystemException {
          total += stat.size;
        }
      } else {
        total += stat.size;
      }
    }
    return total;
  }

  /// Independent file metadata comes from Android's extractor, never the
  /// request's duration label. A short preview cannot masquerade as a full song.
  static Future<NeteaseAudioProbe> inspectFile(
    String path, {
    Duration? expectedDuration,
    MethodChannel channel = channelDefault,
  }) async {
    final result = await channel.invokeMapMethod<String, Object?>('inspect', {
      'path': path,
    });
    final duration = Duration(
      microseconds: (result?['durationUs'] as num?)?.toInt() ?? 0,
    );
    final format = '${result?['format'] ?? ''}';
    if (duration <= Duration.zero ||
        !{'m4a', 'flac', 'mp3'}.contains(format) ||
        (expectedDuration != null &&
            duration + const Duration(seconds: 3) < expectedDuration)) {
      throw const QishuiException(
        '汽水音频时长或格式核验未通过',
        kind: QishuiFailureKind.format,
      );
    }
    return NeteaseAudioProbe(
      'audio_ready',
      totalBytes: (result?['bytes'] as num?)?.toInt(),
      bitrate: (result?['bitrate'] as num?)?.toInt() ?? 0,
      duration: duration,
      format: format,
    );
  }

  /// Downloads may only copy files produced by this private playback adapter;
  /// arbitrary file:// Tracks must never gain filesystem read privileges.
  static Future<bool> isPrivateCachePath(String path) async {
    final root = Directory(
      '${(await getTemporaryDirectory()).path}/$directoryName',
    );
    final file = File(path);
    if (!await file.exists() ||
        !RegExp(r'^[0-9a-f]{32}\.m4a$').hasMatch(file.uri.pathSegments.last)) {
      return false;
    }
    return await file.parent.resolveSymbolicLinks() ==
            await root.resolveSymbolicLinks() &&
        await FileSystemEntity.type(file.path, followLinks: false) ==
            FileSystemEntityType.file;
  }
}
