import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../data/music_platform_api.dart';
import '../domain/platform_session.dart';
import 'listening_sync_models.dart';

class ListeningDeviceInfo {
  const ListeningDeviceInfo(
    this.model,
    this.systemVersion,
    this.width,
    this.height,
  );
  final String model, systemVersion;
  final int width, height;

  static Future<ListeningDeviceInfo> load() async {
    const channel = MethodChannel('com.mesting.music/system_media');
    final value = await channel.invokeMapMethod<String, Object?>(
      'getListeningDeviceInfo',
    );
    final model = '${value?['model'] ?? ''}';
    final version = '${value?['systemVersion'] ?? ''}';
    final width = int.tryParse('${value?['screenWidth']}') ?? 0;
    final height = int.tryParse('${value?['screenHeight']}') ?? 0;
    if (model.isEmpty ||
        model.length > 128 ||
        model.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        !RegExp(r'^\d+(?:\.\d+)*$').hasMatch(version) ||
        width < 1 ||
        width > 65535 ||
        height < 1 ||
        height > 65535) {
      throw StateError('无法读取真实设备信息');
    }
    return ListeningDeviceInfo(model, version, width, height);
  }
}

abstract interface class ListeningPlatformGateway {
  Future<void> prepare(PlatformSession identity);
  Future<String> resolveRecording(PlatformSession identity, String trackId);
  Future<List<OfficialHistoryFact>> history(PlatformSession identity);
  Future<bool> uploadHistory(
    PlatformSession identity,
    String recordingId,
    int time,
    int count,
  );
  Future<int?> gradeSeconds(PlatformSession identity);
  Future<bool> reportGrade(PlatformSession identity, int baseline, int delta);
  Future<bool> reportEvent(
    PlatformSession identity,
    Map<String, Object?> payload,
  );
}

/// A parsed negative business response is final, unlike a lost or malformed
/// reply. Keeping this distinction prevents a known rejection from permanently
/// blocking every later fresh measurement as an ambiguous successful upload.
class KugouListeningRejected implements Exception {
  const KugouListeningRejected();
}

/// The existing API adapter owns loopback transport and credentials. This layer
/// adds typed reporting contracts and never logs payloads, tokens or device IDs.
class KugouListeningRepository implements ListeningPlatformGateway {
  KugouListeningRepository(
    this.api, {
    Future<String> Function()? uuidLoader,
    Future<ListeningDeviceInfo> Function()? deviceLoader,
  }) : _uuidLoader = uuidLoader ?? _loadRuntimeUuid,
       _deviceLoader = deviceLoader ?? ListeningDeviceInfo.load;

  final MusicPlatformApi api;
  final Future<String> Function() _uuidLoader;
  final Future<ListeningDeviceInfo> Function() _deviceLoader;
  String? _uuid;
  ListeningDeviceInfo? _device;

  static bool businessAccepted(Map<String, dynamic> result) {
    final status = '${result['status'] ?? ''}';
    if (status != '1') return false;
    for (final key in ['error_code', 'errcode', 'err_code']) {
      if (result.containsKey(key) && '${result[key]}' != '0') return false;
    }
    // The Rust CSCC adapter normalizes duplicate rejection to status=1.
    // Keep it uncertain: this is not evidence that this event was newly booked.
    return result['duplicate'] != true;
  }

  void _assertIdentity(PlatformSession expected) {
    if (api.session?.userId != expected.userId ||
        api.session?.token != expected.token) {
      throw const MusicPlatformException('账号已变化，请稍后重试');
    }
  }

  @override
  Future<void> prepare(PlatformSession identity) async {
    _assertIdentity(identity);
    await api.ensureRegisteredDevice();
    _assertIdentity(identity);
  }

  /// Grade's upstream handler does not fill uuid from DeviceConfig. Read only
  /// this app's own small persisted registration record after registration;
  /// no user credential storage or foreign app/phone file is involved.
  static Future<String> _loadRuntimeUuid() async {
    final directory = await getApplicationSupportDirectory();
    final file = File(
      '${directory.path}/music_platform/runtime/device_info.json',
    );
    if (!await file.exists() || await file.length() > 16384) {
      throw StateError('设备注册尚未完成');
    }
    final decoded = jsonDecode(await file.readAsString());
    final uuid = decoded is Map ? '${decoded['uuid'] ?? ''}' : '';
    if (!RegExp(r'^[a-zA-Z0-9]{32}$').hasMatch(uuid)) {
      throw StateError('设备注册尚未完成');
    }
    return uuid;
  }

  Future<String> _registeredUuid() async => _uuid ??= await _uuidLoader();

  @override
  Future<String> resolveRecording(
    PlatformSession identity,
    String trackId,
  ) async {
    if (!RegExp(r'^kugou_[a-fA-F0-9]{32}$').hasMatch(trackId)) return '';
    final hash = trackId.substring(6).toLowerCase();
    final payload = await api.get(
      '/audio',
      query: {'hash': hash},
      expectedSession: identity,
    );
    String find(Object? node, int depth) {
      if (depth > 7) return '';
      if (node is List) {
        for (final row in node.take(256)) {
          final id = find(row, depth + 1);
          if (id.isNotEmpty) return id;
        }
      } else if (node is Map) {
        final receivedHash =
            '${node['hash'] ?? node['FileHash'] ?? node['audio_hash'] ?? ''}'
                .toLowerCase();
        if (receivedHash.isNotEmpty && receivedHash != hash) return '';
        for (final key in [
          'mixsongid',
          'album_audio_id',
          'AlbumAudioID',
          'MixSongID',
          'albumAudioId',
        ]) {
          final id = '${node[key] ?? ''}';
          if (RegExp(r'^[1-9]\d*$').hasMatch(id)) return id;
        }
        for (final key in [
          'data',
          'base',
          'info',
          'audio_info',
          'song_info',
          'audio',
          'list',
        ]) {
          final id = find(node[key], depth + 1);
          if (id.isNotEmpty) return id;
        }
      }
      return '';
    }

    return find(payload, 0);
  }

  @override
  Future<List<OfficialHistoryFact>> history(PlatformSession identity) async {
    final payload = await api.get('/user/history', expectedSession: identity);
    return parseHistory(payload);
  }

  static List<OfficialHistoryFact> parseHistory(Object? payload) {
    final result = <OfficialHistoryFact>[];
    void walk(Object? node, int depth) {
      if (depth > 7 || result.length >= 1000) return;
      if (node is List) {
        for (final row in node.take(1000)) {
          walk(row, depth + 1);
        }
      } else if (node is Map) {
        final base = node['base'] is Map ? node['base'] as Map : const {};
        final id =
            '${node['mxid'] ?? node['mixsongid'] ?? node['album_audio_id'] ?? base['mixsongid'] ?? base['album_audio_id'] ?? ''}';
        if (RegExp(r'^[1-9]\d*$').hasMatch(id)) {
          final count = int.tryParse(
            '${node['pc'] ?? node['play_count'] ?? node['playcount']}',
          );
          final time = int.tryParse(
            '${node['ot'] ?? node['time'] ?? node['last_play_time']}',
          );
          result.add(OfficialHistoryFact(id, count, time));
        }
        for (final key in ['data', 'list', 'songs', 'songlist', 'info']) {
          walk(node[key], depth + 1);
        }
      }
    }

    walk(payload, 0);
    return result;
  }

  @override
  Future<bool> uploadHistory(
    PlatformSession identity,
    String recordingId,
    int time,
    int count,
  ) async => businessAccepted(
    await api.post(
      '/playhistory/upload',
      expectedSession: identity,
      query: {'mxid': recordingId, 'time': '$time', 'pc': '$count'},
    ),
  );

  @override
  Future<int?> gradeSeconds(PlatformSession identity) async {
    final uuid = await _registeredUuid();
    final result = await api.get(
      '/user/grade/info',
      expectedSession: identity,
      query: {'uuid': uuid},
    );
    if (!businessAccepted(result)) return null;
    final data = result['data'];
    final seconds = data is Map ? int.tryParse('${data['d_sec']}') : null;
    return seconds != null && seconds >= 0 ? seconds : null;
  }

  @override
  Future<bool> reportGrade(
    PlatformSession identity,
    int baseline,
    int delta,
  ) async {
    final uuid = await _registeredUuid();
    final result = await api.post(
      '/user/grade/info',
      expectedSession: identity,
      query: {
        'uuid': uuid,
        // d_sec is the separately observed server baseline. The expected
        // post-write target is journal evidence, never an input baseline.
        'd_sec': '$baseline',
        'diff_sec': '$delta',
        'y_type': '0',
        'm_type': '0',
      },
    );
    if ('${result['status']}' == '0' ||
        ['errcode', 'error_code', 'err_code'].any(
          (key) =>
              result.containsKey(key) &&
              int.tryParse('${result[key]}') != null &&
              int.parse('${result[key]}') != 0,
        )) {
      throw const KugouListeningRejected();
    }
    return businessAccepted(result);
  }

  @override
  Future<bool> reportEvent(
    PlatformSession identity,
    Map<String, Object?> payload,
  ) async {
    final device = _device ??= await _deviceLoader();
    final event = '${payload['event']}';
    return businessAccepted(
      await api.post(
        '/user/listen/report',
        expectedSession: identity,
        query: {
          'mixsongid': '${payload['recordingId']}',
          'event': event,
          if (event == 'end') 'duration': '${payload['heardMs']}',
          // Retain detailed local reasons in the journal, but use the two
          // CSCC states emitted by the upstream client on the wire.
          if (event == 'end')
            'state': payload['reason'] == '完整播放' ? '完整播放' : '中断播放',
          'device_model': device.model,
          'system_version': device.systemVersion,
          'screen_width': '${device.width}',
          'screen_height': '${device.height}',
        },
      ),
    );
  }
}
