import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Public download telemetry is isolated from the account-authenticated API.
/// A persisted, bounded queue preserves event IDs and ordering across restarts.
class AppUpgradeServiceEvents {
  AppUpgradeServiceEvents({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 2),
              receiveTimeout: const Duration(seconds: 2),
              followRedirects: false,
              validateStatus: (_) => true,
            ),
          );

  static const _queueKey = 'app_upgrade.service_events.v1';
  static const _installKey = 'app_upgrade.service_install.v1';
  final Dio _dio;
  Future<void> _serial = Future.value();
  Future<void>? _sending;
  Future<void>? _reconciling;

  String _uuid() {
    final bytes = List.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  bool _validContext(Map context) {
    final uri = Uri.tryParse('${context['origin']}');
    return uri != null &&
        uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        (uri.port == 443) &&
        uri.path.isEmpty &&
        uri.query.isEmpty &&
        uri.fragment.isEmpty &&
        const {
          'download.csnas.asia',
          'download1.csnas.asia',
        }.contains(uri.host) &&
        RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$').hasMatch('${context['slug']}') &&
        RegExp(r'^[a-f0-9]{64}$').hasMatch('${context['sha256']}') &&
        RegExp(r'^[a-f0-9]{16}$').hasMatch('${context['session_id']}');
  }

  Future<void> enqueue(
    Map<String, Object?> context,
    String type, {
    int? bytes,
    int? durationMs,
    String? errorCode,
  }) {
    if (!_validContext(context)) return Future.value();
    // Freeze caller-owned data before joining the asynchronous persistence queue.
    context = Map<String, Object?>.unmodifiable(context);
    final work = _serial
        .then((_) async {
          final prefs = await SharedPreferences.getInstance();
          final queue = List<String>.from(prefs.getStringList(_queueKey) ?? []);
          final body = <String, Object?>{
            'event_id': _uuid(),
            'session_id': context['session_id'],
            'release_sha256': context['sha256'],
            'event_type': type,
            'error_code': ?errorCode,
            if (bytes != null && durationMs != null) ...{
              'persisted_bytes': bytes,
              'download_duration_ms': durationMs,
            },
          };
          queue.add(jsonEncode({'context': context, 'body': body}));
          // Old unreported telemetry cannot grow without bound or delay downloads.
          while (queue.length > 32) {
            queue.removeAt(0);
          }
          await prefs.setStringList(_queueKey, queue);
        })
        .catchError((_) {});
    _serial = work;
    unawaited(work.then((_) => flush()));
    return work;
  }

  Future<void> flush() {
    if (_sending != null) return _sending!;
    late Future<void> flight;
    flight = _flush().catchError((_) {}).whenComplete(() {
      if (identical(_sending, flight)) _sending = null;
    });
    _sending = flight;
    return flight;
  }

  Future<void> _flush() async {
    for (var count = 0; count < 32; count++) {
      await _serial;
      final prefs = await SharedPreferences.getInstance();
      final queue = prefs.getStringList(_queueKey) ?? [];
      if (queue.isEmpty) return;
      final raw = queue.first;
      Map? entry;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map &&
            decoded['context'] is Map &&
            decoded['body'] is Map &&
            _validContext(decoded['context'])) {
          entry = decoded;
        }
      } catch (_) {}
      if (entry == null) {
        await _removeQueued(raw);
        continue;
      }
      final context = entry['context'] as Map;
      final response = await _dio.post<Object?>(
        '${context['origin']}/api/app/${context['slug']}/update-event',
        data: entry['body'],
        options: Options(
          headers: const {'Accept': 'application/json'},
          contentType: Headers.jsonContentType,
          followRedirects: false,
          validateStatus: (_) => true,
        ),
      );
      final status = response.statusCode ?? 0;
      final data = response.data;
      final permanentEventLimit =
          status == 429 &&
          data is Map &&
          data['error'] == 'session_event_limit';
      if (status >= 500 ||
          (status == 429 && !permanentEventLimit) ||
          status == 0) {
        return;
      }
      // Final 4xx cannot be repaired by generating another ID. Successful and
      // rejected records are removed serially without losing newly enqueued ones.
      await _removeQueued(raw);
    }
  }

  Future<void> _removeQueued(String raw) {
    final remove = _serial.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final current = List<String>.from(prefs.getStringList(_queueKey) ?? []);
      current.remove(raw);
      await prefs.setStringList(_queueKey, current);
    });
    _serial = remove.catchError((_) {});
    return _serial;
  }

  Future<void> rememberInstall(Map<String, Object?> context, int build) async {
    if (!_validContext(context) || build <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _installKey,
      jsonEncode({'context': context, 'build': build}),
    );
  }

  /// Only observing the new installed build proves success; starting the
  /// Android installer never counts as successful installation.
  Future<void> reconcileInstalledBuild(int build) {
    if (_reconciling != null) return _reconciling!;
    late Future<void> flight;
    flight = _reconcileInstalledBuild(build).catchError((_) {}).whenComplete(
      () {
        if (identical(_reconciling, flight)) _reconciling = null;
      },
    );
    _reconciling = flight;
    return flight;
  }

  Future<void> _reconcileInstalledBuild(int build) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_installKey);
    if (raw != null) {
      Map? entry;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map &&
            decoded['build'] is int &&
            decoded['context'] is Map &&
            _validContext(decoded['context'])) {
          entry = decoded;
        }
      } catch (_) {}
      if (entry == null) {
        await prefs.remove(_installKey);
      } else if (entry['build'] == build) {
        await enqueue(
          Map<String, Object?>.from(entry['context']),
          'install_success',
        );
        await prefs.remove(_installKey);
      }
    }
    unawaited(flush());
  }
}
