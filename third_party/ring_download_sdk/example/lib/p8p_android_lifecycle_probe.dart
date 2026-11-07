// Private stage-specific acceptance. Real SDK, TLS and native RTC owners.
// Stage-specific inputs share unchanged SDK/runtime owners; the fixed 18-case
// plan remains authoritative; file/report cases require their own real owners.
// Test-only seams preserve the exact real clients and capture actual native PCs.
// These imports and withEngine are intentionally absent from host integration.
// ignore_for_file: implementation_imports, invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:ring_download_sdk/ring_download_sdk.dart';
import 'package:ring_download_sdk/src/core/services/app_upgrade_v40_download_client.dart';
import 'package:ring_download_sdk/src/core/services/app_upgrade_file_io.dart';
import 'package:ring_download_sdk/src/core/services/app_upgrade_v40_p2p_client.dart';
import 'package:ring_download_sdk/src/sdk/engine.dart';
import 'package:ring_download_sdk/src/sdk/network.dart';
import 'p8p_lifecycle_file_io.dart';

const _native = MethodChannel('p8p/native_probe_config');
final _records = <Map<String, Object?>>[];
final _asyncErrors = <String>[];

void _require(bool value, String reason) {
  if (!value) throw StateError(reason);
}

void _record(String kind, Map<String, Object?> value) {
  final encoded = jsonEncode(value);
  _require(
    _records.length < 64 && utf8.encode(encoded).length < 4000,
    'Lifecycle evidence bounds exceeded',
  );
  _records.add({'kind': kind, 'value': jsonDecode(encoded)});
}

class _FixtureHttp extends HttpOverrides {
  _FixtureHttp(this.port, String certificate)
    : context = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificatesBytes(base64Decode(certificate));
  final int port;
  final SecurityContext context;

  @override
  HttpClient createHttpClient(SecurityContext? ignored) {
    final client = super.createHttpClient(context);
    client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      _require(
        uri.scheme == 'https' &&
            const {
              'download.csnas.asia',
              'download1.csnas.asia',
            }.contains(uri.host),
        'Private probe tried a non-fixture origin',
      );
      final attempt = await Socket.startConnect(
        InternetAddress.loopbackIPv4,
        port,
      );
      Socket? owner;
      var cancelled = false;
      final secured = attempt.socket.then((socket) async {
        owner = socket;
        final tls = await SecureSocket.secure(
          socket,
          host: uri.host,
          context: context,
        );
        owner = tls;
        if (cancelled) tls.destroy();
        return tls;
      });
      return ConnectionTask.fromSocket<Socket>(secured, () {
        cancelled = true;
        attempt.cancel();
        owner?.destroy();
      });
    };
    return client;
  }
}

Future<Map<String, dynamic>> _control(String name) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(
      Uri.parse('https://download.csnas.asia/__lifecycle__/$name'),
    );
    final response = await req.close();
    _require(response.statusCode == 200, 'Private lifecycle control rejected');
    final body = await utf8.decodeStream(response);
    _require(
      utf8.encode(body).length < 131072,
      'Private status exceeded bound',
    );
    return Map<String, dynamic>.from(jsonDecode(body) as Map);
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, int>> _owners() async {
  final value = await _native.invokeMapMethod<String, int>('rtcOwners');
  _require(
    value != null && value.length == 3 && value.values.every((n) => n >= 0),
    'Missing native RTC owner observation',
  );
  return value!;
}

Future<int> _fds() async {
  final value = await _native.invokeMethod<int>('udpOwnedDescriptorCount');
  _require(
    value != null && value >= 0 && value <= 2048,
    'Invalid datagram FD count',
  );
  return value!;
}

Future<List<Map<String, Object?>>> _bindings() async {
  final text = await _native.invokeMethod<String>('udpOwnedBindings');
  _require(text != null && text.length <= 8192, 'Missing own UDP bindings');
  final value = jsonDecode(text!);
  _require(value is List && value.length <= 32, 'UDP binding bound exceeded');
  final rows = (value as List)
      .map((r) => Map<String, Object?>.from(r as Map))
      .toList();
  final seen = <String>{};
  for (final row in rows) {
    final ip = row['address'], port = row['port'], family = row['family'];
    _require(
      row.length == 3 &&
          ip is String &&
          port is int &&
          port > 0 &&
          port <= 65535 &&
          (family == 4 || family == 6) &&
          seen.add('$family/$ip/$port'),
      'Invalid or duplicated UDP binding',
    );
  }
  return rows;
}

Future<List<Map<String, Object?>>> _bindProbe(
  List<Map<String, Object?>> rows,
) async {
  final value = await _native.invokeListMethod<Object?>('udpBindProbe', {
    'bindings': [
      for (final row in rows) {'address': row['address'], 'port': row['port']},
    ],
  });
  _require(
    value != null && value.length == rows.length,
    'Missing OS bind observations',
  );
  return value!.map((r) => Map<String, Object?>.from(r as Map)).toList();
}

Future<bool> _phaseActive(
  RTCPeerConnection peer,
  String stage,
  bool verifiedSeedProbe,
) async {
  if (stage == 'gather') {
    return await peer.getIceGatheringState() ==
        RTCIceGatheringState.RTCIceGatheringStateGathering;
  }
  final state = await peer.getIceConnectionState();
  if (stage == 'checks') {
    return state == RTCIceConnectionState.RTCIceConnectionStateChecking;
  }
  return stage == 'connected' &&
      verifiedSeedProbe &&
      (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted);
}

Future<Map<String, Object?>> _runRead(
  Map<String, dynamic> meta,
  NativeFileIoGate gate,
) async {
  final initial = await _owners();
  _require(
    initial.values.every((n) => n == 0) &&
        await _fds() == 0 &&
        (await _bindings()).isEmpty,
    'Read case lacks a cold native baseline',
  );
  _record('baseline', {'owners': initial, 'UDP_FDs': 0});
  final network = await RingNetwork.read();
  _require(
    network.mayShare &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    'Real foreground unmetered Wi-Fi required',
  );
  final storage = await Directory.systemTemp.createTemp('p8p-lifecycle-read-');
  var cacheAvailable = false;
  final sdk = RingDownloadSdk(
    RingDownloadConfig(
      appId: 'lifering',
      enableP8P: true,
      allowSharing: false,
      storageDirectory: storage,
      onDiagnostic: (event) {
        if (event.stage == 'sharing' && event.code == 'cache_available') {
          cacheAvailable = true;
        }
      },
    ),
  );
  final task = sdk.download(
    RingDownloadRequest(
      releaseId: meta['release_id'] as String,
      version: meta['version'] as String,
      url: Uri.parse(meta['url'] as String),
      fileSize: meta['file_size'] as int,
      sha256: meta['sha256'] as String,
      etag: meta['etag'] as String,
    ),
  );
  final receipt = await task.completed.timeout(const Duration(seconds: 60));
  await receipt.revalidate();
  _record('verified_cache', {
    'bytes': receipt.fileSize,
    'sha256_matches_expected': receipt.sha256 == meta['sha256'],
  });
  sdk.setSharingEnabled(true);
  final starting = Stopwatch()..start();
  while (!cacheAvailable) {
    _require(
      starting.elapsedMilliseconds < 15000,
      'Actual verified-cache sharing did not become available',
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  gate.armRead(receipt.file.path);
  await _control('start-read-receiver');
  await gate.entered.timeout(const Duration(seconds: 15));
  final heldIo = gate.snapshot();
  final held = await _bindings();
  final fds = await _fds();
  final owners = await _owners();
  final remote = await _control('status');
  final receiver = remote['read_receiver'] as Map;
  _require(
    heldIo['target_handles'] == 1 &&
        heldIo['pending_operations'] == 1 &&
        (heldIo['native_bytes'] as int) > 0 &&
        heldIo['valid'] == true &&
        held.isNotEmpty &&
        fds >= held.length &&
        (owners['peerConnections'] ?? 0) > 0 &&
        receiver['channel_opened'] == true &&
        receiver['request_sent'] == true &&
        (await _bindProbe(
          held,
        )).every((r) => r['exclusiveBindSucceeded'] == false),
    'Read cancellation lacks actual native file and connected RTC owners',
  );
  _record('read_positive', {
    'IO': heldIo,
    'ports': held,
    'UDP_FDs': fds,
    'owners': owners,
    'receiver_requested': true,
    'cache_verified': true,
    'foreground_unmetered_WiFi': true,
  });
  final closing = Stopwatch()..start();
  gate.retire();
  final disposing = sdk.dispose();
  disposing.ignore();
  // Both Futures are the real owners. Returning dispose before the pending
  // file operation ends is a failure, even if native RTC already closed.
  final disposedFirst = await Future.any<bool>([
    disposing.then((_) => true),
    gate.released.then((_) => false),
  ]);
  if (disposedFirst && gate.snapshot()['pending_operations'] != 0) {
    _record('read_dispose_returned_early', {
      'elapsed_ms': closing.elapsedMilliseconds,
      'IO': gate.snapshot(),
      'owners': await _owners(),
      'UDP_FDs': await _fds(),
    });
    throw StateError(
      'SDK disposal returned with a live upload file-read owner',
    );
  }
  var physicalMs = -1;
  while (closing.elapsedMilliseconds <= 6000) {
    final io = gate.snapshot();
    if (io['target_handles'] == 0 &&
        io['pending_operations'] == 0 &&
        (await _owners()).values.every((n) => n == 0) &&
        await _fds() == 0 &&
        (await _bindings()).isEmpty &&
        (await _bindProbe(
          held,
        )).every((r) => r['exclusiveBindSucceeded'] == true)) {
      physicalMs = closing.elapsedMilliseconds;
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  _require(
    physicalMs >= 0 && physicalMs <= 6000,
    'Actual read/RTC resources exceeded 6 seconds',
  );
  await disposing.timeout(
    Duration(milliseconds: 12000 - closing.elapsedMilliseconds),
  );
  Map<String, dynamic> finalServer;
  do {
    finalServer = await _control('status');
    if (finalServer['idle'] == true) break;
    _require(
      closing.elapsedMilliseconds < 12000,
      'Read server owners still active',
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
  } while (true);
  await Future<void>.delayed(const Duration(milliseconds: 200));
  final io = gate.snapshot();
  _require(
    io['valid'] == true &&
        io['target_handles'] == 0 &&
        io['pending_operations'] == 0 &&
        _asyncErrors.isEmpty &&
        closing.elapsedMilliseconds <= 12000 &&
        finalServer['quotas_unchanged'] == true,
    'Read retirement or quiet-period invariant failed',
  );
  _record('read_terminal', {
    'IO': io,
    'server_idle': true,
    'receiver': finalServer['read_receiver'],
    'physical_close_ms': physicalMs,
    'whole_close_ms': closing.elapsedMilliseconds,
  });
  return {
    'passed': true,
    'stage': 'read',
    'round': meta['round'],
    'physical_close_ms': physicalMs,
    'whole_close_ms': closing.elapsedMilliseconds,
    'actual_regular_file_read_held_ms': 3000,
    'disposed_after_read_operation': true,
    'SDK_runtime_changed': true,
    'production_contacted': false,
    'full_T15_complete': false,
    'async_errors': _asyncErrors,
  };
}

RingDownloadRequest _requestFor(Map<String, dynamic> meta) => RingDownloadRequest(
  releaseId: meta['release_id'] as String, version: meta['version'] as String,
  url: Uri.parse(meta['url'] as String), fileSize: meta['file_size'] as int,
  sha256: meta['sha256'] as String, etag: meta['etag'] as String,
);

Future<Map<String, dynamic>> _idleBefore(Stopwatch closing) async {
  while (true) {
    final status = await _control('status');
    _require(closing.elapsedMilliseconds <= 12000, 'Whole retirement exceeded 12 seconds');
    if (status['idle'] == true && status['quotas_unchanged'] == true) {
      return status;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<int> _physicalBefore(Stopwatch closing,
    List<Map<String, Object?>> held, {NativeFileIoGate? gate}) async {
  while (closing.elapsedMilliseconds <= 6000) {
    final io = gate?.snapshot();
    final owners = await _owners();
    final fds = await _fds();
    final bindings = await _bindings();
    final rebound = await _bindProbe(held);
    if ((io == null || (io['target_handles'] == 0 && io['pending_operations'] == 0)) &&
        owners.values.every((n) => n == 0) && fds == 0 &&
        bindings.isEmpty && rebound.every((r) =>
            r['exclusiveBindSucceeded'] == true)) {
      final elapsed = closing.elapsedMilliseconds;
      _require(elapsed <= 6000, 'Physical observation exceeded 6 seconds');
      _record('physical_released', {'owners': owners, 'UDP_FDs': fds,
        'current_bindings': bindings, 'historical_bindings': held,
        'exclusive_rebind': rebound, 'physical_close_ms': elapsed,
        'IO': ?io});
      return elapsed;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw StateError('Actual physical resources remain after 6 seconds');
}

Future<void> _postQuietNative(Stopwatch closing,
    List<Map<String, Object?>> held) async {
  final owners = await _owners();
  final fds = await _fds();
  final bindings = await _bindings();
  final rebound = await _bindProbe(held);
  final elapsed = closing.elapsedMilliseconds;
  _record('post_quiet_native', {'owners': owners, 'UDP_FDs': fds,
    'current_bindings': bindings, 'historical_bindings': held,
    'exclusive_rebind': rebound, 'elapsed_ms': elapsed});
  _require(owners.values.every((n) => n == 0) && fds == 0 && bindings.isEmpty &&
      rebound.every((r) => r['exclusiveBindSucceeded'] == true) && elapsed <= 12000,
      'Native owners reappeared after the quiet observation period');
}

Future<Map<String, Object?>> _runWrite(Map<String, dynamic> meta,
    NativeFileIoGate gate) async {
  final initial = await _owners();
  _require(initial.values.every((n) => n == 0) && await _fds() == 0 &&
      (await _bindings()).isEmpty, 'Write case lacks cold native baseline');
  _record('baseline', {'owners': initial, 'UDP_FDs': 0});
  final storage = await Directory.systemTemp.createTemp('p8p-lifecycle-write-');
  final request = _requestFor(meta);
  final stem = 'ring:lifering:${request.releaseId}'.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final part = File('${storage.path}/ring_download_sdk/lifering/app-upgrades/'
      '$stem-${request.sha256.substring(0, 12)}.apk.part');
  gate.armWrite(part.path);
  var verifiedSeedProbe = false, terminal = false;
  String? taskError;
  final sdk = RingDownloadSdk(RingDownloadConfig(appId: 'lifering', enableP8P: true,
      allowSharing: false, storageDirectory: storage, onDiagnostic: (event) {
        if (event.stage == 'hybrid' && event.code == 'probe_verified' &&
            event.source == 'seed') {
          verifiedSeedProbe = true;
        }
      }));
  final task = sdk.download(request);
  task.completed.then<void>((_) { terminal = true; }, onError: (Object error) {
    terminal = true;
    taskError = error is RingDownloadException ? error.code.name : error.runtimeType.toString();
  });
  await gate.entered.timeout(const Duration(seconds: 15));
  final heldIo = gate.snapshot(), owners = await _owners();
  final held = await _bindings();
  final positiveServer = await _control('status');
  final prefixBytes = await part.length();
  final prefixSha = await appUpgradeFileSha256(part.path);
  final occupied = await _bindProbe(held);
  _require(!terminal && heldIo['target_handles'] == 1 && heldIo['pending_operations'] == 1 &&
      heldIo['native_bytes'] == meta['chunk_size'] && prefixBytes == meta['chunk_size'] &&
      prefixSha == meta['first_piece_sha256'] && verifiedSeedProbe &&
      held.isNotEmpty && (owners['peerConnections'] ?? 0) > 0 &&
      (positiveServer['active_rtc'] as int) > 0 &&
      occupied.every((r) => r['exclusiveBindSucceeded'] == false),
      'Write case lacks a real verified prefix, open writer and connected RTC');
  _record('write_positive', {'IO': heldIo, 'owners': owners, 'ports': held,
      'exclusive_bind': occupied,
      'prefix_bytes': prefixBytes, 'prefix_sha256_verified': true,
      'prefix_sha256': prefixSha,
      'verified_seed_probe': true, 'task_terminal': terminal});
  final beforeRetire = gate.snapshot();
  _require(beforeRetire['pending_operations'] == 1 &&
      beforeRetire['target_handles'] == 1 && beforeRetire['valid'] == true &&
      beforeRetire['claimed'] == true && !terminal,
      'Actual write ended during positive-control observation');
  final closing = Stopwatch()..start();
  gate.retire();
  Map<String, Object?>? atDispose;
  var disposeMs = -1;
  task.cancel();
  final disposing = sdk.dispose().then((_) {
    atDispose = gate.snapshot();
    disposeMs = closing.elapsedMilliseconds;
    _require(atDispose!['target_handles'] == 0 && atDispose!['pending_operations'] == 0,
        'SDK disposal returned with a live file-write owner');
  });
  disposing.ignore();
  final physicalMs = await _physicalBefore(closing, held, gate: gate);
  await disposing.timeout(Duration(milliseconds: 12000-closing.elapsedMilliseconds));
  final idle = await _idleBefore(closing);
  await Future<void>.delayed(const Duration(milliseconds: 200));
  await _postQuietNative(closing, held);
  final stoppedIo = gate.snapshot();
  _require(terminal && taskError == 'cancelled' && stoppedIo['valid'] == true &&
      stoppedIo['all_wrapped_handles'] == 0 && _asyncErrors.isEmpty &&
      closing.elapsedMilliseconds <= 12000, 'Write cancellation failed to settle');
  final persistedBytes = await part.length();
  final persistedSha = await appUpgradeFileSha256(part.path);
  _require(persistedBytes == prefixBytes && persistedSha == prefixSha,
      'Cancelled writer changed its verified prefix after retirement');
  _record('write_terminal', {'IO': stoppedIo, 'at_dispose_return': atDispose,
      'dispose_return_ms': disposeMs, 'physical_close_ms': physicalMs,
      'whole_close_ms': closing.elapsedMilliseconds, 'prefix_preserved': true,
      'prefix_bytes': persistedBytes, 'persisted_sha256': persistedSha,
      'server_idle': idle['idle'], 'task_error': taskError});
  // Resume only after all first-operation owners ended. Outside the retired
  // test gate, the new SDK uses the same real file and HTTPS-only configuration.
  return IOOverrides.runWithIOOverrides(() async {
    await _control('mark-resume');
    final resumed = RingDownloadSdk(RingDownloadConfig(appId: 'lifering',
        enableP2P: false, enableP8P: false, allowSharing: false, storageDirectory: storage));
    final receipt = await resumed.download(request).completed.timeout(const Duration(seconds: 60));
    await receipt.revalidate();
    await resumed.dispose();
    final finalStatus = await _control('status');
    final index = finalStatus['resume_event_index'] as int;
    final events = (finalStatus['http_events'] as List).skip(index).cast<Map>();
    final downloads = events.where((r) => r['path'] == '/lifering/download').toList();
    _require(finalStatus['idle'] == true && downloads.isNotEmpty &&
        downloads.first['status'] == 206 &&
        (downloads.first['range'] as String).startsWith('bytes=$persistedBytes-') &&
        events.every((r) => !(r['path'] as String).contains('/p2p/')) &&
        (await _owners()).values.every((n) => n == 0) && await _fds() == 0,
        'Actual HTTPS continuation did not preserve the cancelled prefix');
    _record('HTTPS_resume_verified', {'bytes': receipt.fileSize,
        'sha256': receipt.sha256,
        'sha256_matches_expected': receipt.sha256 == request.sha256,
        'start_offset': persistedBytes, 'first_HTTP_status': downloads.first['status'],
        'P2P_requests_after_resume': 0});
    return {'passed': true, 'stage': 'write', 'round': meta['round'],
      'physical_close_ms': physicalMs, 'whole_close_ms':
          (_records.firstWhere((r) => r['kind'] == 'write_terminal')['value'] as Map)['whole_close_ms'],
      'dispose_return_ms': disposeMs, 'actual_file_write_hold_ms': 3000,
      'prefix_preserved_bytes': persistedBytes, 'HTTPS_resume_verified': true,
      'SDK_runtime_changed': true, 'production_contacted': false,
      'full_T15_complete': false, 'async_errors': _asyncErrors};
  }, _PassThroughIo());
}

final class _PassThroughIo extends IOOverrides {}

Future<Map<String, Object?>> _runFinalReport(Map<String, dynamic> meta) async {
  final initial = await _owners();
  _require(initial.values.every((n) => n == 0) && await _fds() == 0 &&
      (await _bindings()).isEmpty, 'Final report case lacks cold native baseline');
  _record('baseline', {'owners': initial, 'UDP_FDs': 0});
  final storage = await Directory.systemTemp.createTemp('p8p-lifecycle-report-');
  final config = RingDownloadConfig(appId: 'lifering', enableP8P: true,
      allowSharing: false, storageDirectory: storage);
  final http = Dio(BaseOptions(connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(minutes: 15)));
  final signal = Dio(BaseOptions(connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 5), sendTimeout: const Duration(seconds: 5)));
  final clientEvents = <Map<String, Object?>>[];
  var outcomeAcks = 0, leaves = 0, leaveAcks = 0;
  final clock = Stopwatch()..start();
  void event(String kind, int? status) {
    _require(clientEvents.length < 16, 'Final response observation bound exceeded');
    clientEvents.add({'event': kind, 'at_us': clock.elapsedMicroseconds,
      'status': ?status});
  }
  signal.interceptors.add(InterceptorsWrapper(onRequest: (options, next) {
    if (Uri.parse(options.path).path.endsWith('/leave')) {
      leaves++;
      event('leave_started', null);
    }
    next.next(options);
  }, onResponse: (response, next) {
    if ((response.statusCode ?? 0) >= 200 && (response.statusCode ?? 0) < 300) {
      final path = Uri.parse(response.requestOptions.path).path;
      if (path.endsWith('/outcome')) {
        outcomeAcks++;
        event('actual_outcome_response_received', response.statusCode);
      } else if (path.endsWith('/leave')) {
        leaveAcks++;
        event('actual_leave_response_received', response.statusCode);
      }
    }
    next.next(response);
  }));
  final p2p = AppUpgradeV40P2PClient(dio: signal, networkReader: RingNetwork.read,
      networkEvents: RingNetwork.events, isAndroid: true, allowSharing: false,
      enableP8P: true, sharingDuration: null, hybridStartup: true,
      fastSignaling: true, preferredPeerBatchPieces: 4);
  final client = AppUpgradeV40DownloadClient(dio: http, p2pClient: p2p,
      httpsHeadStart: true, allowExternalHttps: true,
      supportDirectoryLoader: () async => Directory('${storage.path}/ring_download_sdk/lifering'));
  final sdk = RingDownloadSdk.withEngine(config, DefaultRingTransferEngine.forTesting(config,
      http: http, signal: signal, p2p: p2p, downloadClient: client));
  var taskTerminal = false;
  String? taskError;
  RingDownloadResult? receipt;
  final task = sdk.download(_requestFor(meta));
  task.completed.then<void>((value) { taskTerminal = true; receipt = value; },
      onError: (Object error) {
    taskTerminal = true;
    taskError = error is RingDownloadException ? error.code.name : error.runtimeType.toString();
  });
  final held = <Map<String, Object?>>[];
  final occupiedProof = <Map<String, Object?>>[];
  final seen = <String>{};
  Map<String, dynamic> positive;
  while (true) {
    _require(clock.elapsedMilliseconds < 60000, 'Actual final response hold was not observed');
    final rows = await _bindings();
    if (rows.isNotEmpty) {
      final occupied = await _bindProbe(rows);
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        if (occupied[i]['exclusiveBindSucceeded'] == false &&
            seen.add('${row['family']}/${row['address']}/${row['port']}')) {
          held.add(row);
          occupiedProof.add(occupied[i]);
        }
      }
      _require(held.length <= 32, 'Final report historical port bound exceeded');
    }
    positive = await _control('status');
    final gate = positive['report_gate'] as Map;
    final events = (gate['events'] as List).cast<Map>();
    if (gate['entered'] == true && (gate['pending_responses'] as int) > 0 &&
        events.any((e) => e['phase'] == 'accepted_response_held') &&
        !events.any((e) => e['phase'] == 'fixed_hold_finished')) {
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  _require(outcomeAcks == 0 && leaves == 0 && held.isNotEmpty &&
      (positive['live_sessions'] as int) > 0 && (positive['seed_sent_bytes'] as int) > 0,
      'Final report lacks real in-flight TLS, session and historical UDP proof');
  _record('final_report_positive', {'gate': positive['report_gate'],
      'task_terminal': taskTerminal, 'outcome_responses_received': outcomeAcks,
      'leave_requests_started': leaves, 'historical_occupied_UDP_ports': held.length,
      'historical_bindings': held, 'exclusive_bind': occupiedProof,
      'live_sessions': positive['live_sessions'], 'seed_sent_bytes': positive['seed_sent_bytes']});
  final closing = Stopwatch()..start();
  Map<String, Object?>? atDispose;
  final disposing = sdk.dispose().then((_) {
    event('dispose_returned', null);
    atDispose = {'outcome_responses_received': outcomeAcks,
      'leave_requests_started': leaves, 'leave_responses_received': leaveAcks,
      'dispose_return_ms': closing.elapsedMilliseconds};
    _require(outcomeAcks == 1 && leaves == 1 && leaveAcks == 1,
        'SDK disposal returned before actual report/leave responses settled');
  });
  disposing.ignore();
  final physicalMs = await _physicalBefore(closing, held);
  await disposing.timeout(Duration(milliseconds: 12000-closing.elapsedMilliseconds));
  final finalStatus = await _idleBefore(closing);
  await Future<void>.delayed(const Duration(milliseconds: 200));
  await _postQuietNative(closing, held);
  final names = clientEvents.map((e) => e['event']).toList();
  _require(outcomeAcks == 1 && leaves == 1 && leaveAcks == 1 &&
      names.indexOf('actual_outcome_response_received') < names.indexOf('leave_started') &&
      names.indexOf('leave_started') < names.indexOf('actual_leave_response_received') &&
      names.indexOf('actual_leave_response_received') < names.indexOf('dispose_returned') && taskTerminal &&
      (taskError == null || taskError == 'cancelled') && _asyncErrors.isEmpty &&
      closing.elapsedMilliseconds <= 12000, 'Final response acknowledgement/leave ownership failed');
  _record('final_report_terminal', {'gate': finalStatus['report_gate'],
      'at_dispose_return': atDispose,
      'client_events': clientEvents, 'physical_close_ms': physicalMs,
      'whole_close_ms': closing.elapsedMilliseconds, 'server_idle': true,
      'task_terminal': taskTerminal, 'task_error': taskError,
      'download_completed': receipt != null});
  if (receipt != null) {
    await receipt!.revalidate();
  }
  return {'passed': true, 'stage': 'final-report', 'round': meta['round'],
      'physical_close_ms': physicalMs, 'whole_close_ms':
          (_records.firstWhere((r) => r['kind'] == 'final_report_terminal')['value'] as Map)['whole_close_ms'],
      'actual_outcome_response_received_before_leave': true,
      'actual_report_hold_ms': 1500, 'SDK_runtime_changed': true,
      'production_contacted': false, 'full_T15_complete': false, 'async_errors': _asyncErrors};
}

Future<Map<String, Object?>> _run() async {
  final fixture = await _native.invokeMapMethod<String, dynamic>('fixture');
  final cert = fixture?['certificate'] as String? ?? '';
  final port = fixture?['port'] as int? ?? 0;
  _require(cert.isNotEmpty && port > 0, 'Missing private fixture connection');
  HttpOverrides.global = _FixtureHttp(port, cert);
  final meta = await _control('metadata');
  final stage = meta['stage'] as String;
  if (stage == 'write') {
    final gate = NativeFileIoGate();
    return IOOverrides.runWithIOOverrides(() => _runWrite(meta, gate), gate);
  }
  if (stage == 'final-report') return _runFinalReport(meta);
  if (stage == 'read') {
    final gate = NativeFileIoGate();
    return IOOverrides.runWithIOOverrides(() => _runRead(meta, gate), gate);
  }
  _require(
    const ['gather', 'checks', 'connected'].contains(stage) &&
        const [1, 2, 3].contains(meta['round']),
    'Stage not implemented or outside fixed batch',
  );
  final initial = await _owners();
  _require(
    initial.values.every((n) => n == 0) &&
        (await _fds()) == 0 &&
        (await _bindings()).isEmpty,
    'Cold private process lacks a zero-owner baseline',
  );
  _record('baseline', {'owners': initial, 'UDP_FDs': 0});
  final storage = await Directory.systemTemp.createTemp('p8p-lifecycle-');
  final peers = <RTCPeerConnection>[];
  final diagnostics = <String, int>{};
  var verifiedSeedProbe = false;
  var transferred = 0, taskTerminal = false;
  String? taskError;
  final config = RingDownloadConfig(
    appId: 'lifering',
    enableP8P: true,
    allowSharing: false,
    storageDirectory: storage,
  );
  final http = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(minutes: 15),
    ),
  );
  final signal = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 5),
      sendTimeout: const Duration(seconds: 5),
    ),
  );
  final p2p = AppUpgradeV40P2PClient(
    dio: signal,
    networkReader: RingNetwork.read,
    networkEvents: RingNetwork.events,
    isAndroid: true,
    allowSharing: false,
    enableP8P: true,
    sharingDuration: null,
    hybridStartup: true,
    fastSignaling: true,
    preferredPeerBatchPieces: 4,
    peerFactory: (configuration) async {
      _require(peers.length < 8, 'Unexpected native peer count');
      final pc = await createPeerConnection(configuration);
      peers.add(pc);
      return pc;
    },
    diagnostic: (event) {
      final key = '${event.stage}/${event.code}';
      _require(
        diagnostics.containsKey(key) || diagnostics.length < 128,
        'Diagnostic count bound exceeded',
      );
      diagnostics.update(key, (v) => v + 1, ifAbsent: () => 1);
      if (event.source == 'seed' &&
          ((event.stage == 'hybrid' && event.code == 'probe_verified') ||
              (event.stage == 'seed' && event.code == 'piece_verified'))) {
        verifiedSeedProbe = true;
      }
    },
  );
  final downloadClient = AppUpgradeV40DownloadClient(
    dio: http,
    p2pClient: p2p,
    httpsHeadStart: true,
    allowExternalHttps: true,
    supportDirectoryLoader: () async =>
        Directory('${storage.path}/ring_download_sdk/lifering'),
  );
  final engine = DefaultRingTransferEngine.forTesting(
    config,
    http: http,
    signal: signal,
    p2p: p2p,
    downloadClient: downloadClient,
  );
  final sdk = RingDownloadSdk.withEngine(config, engine);
  final request = RingDownloadRequest(
    releaseId: meta['release_id'] as String,
    version: meta['version'] as String,
    url: Uri.parse(meta['url'] as String),
    fileSize: meta['file_size'] as int,
    sha256: meta['sha256'] as String,
    etag: meta['etag'] as String,
  );
  final task = sdk.download(request);
  task.completed.then<void>(
    (_) {
      taskTerminal = true;
    },
    onError: (Object error) {
      taskTerminal = true;
      taskError = error is RingDownloadException
          ? error.code.name
          : error.runtimeType.toString();
    },
  );
  final progress = task.progress.listen((event) {
    transferred = event.receivedBytes;
  });
  final stageWatch = Stopwatch()..start();
  List<Map<String, Object?>> held = [];
  Map<String, int> positiveOwners = {};
  var positiveFds = 0, positiveStun = 0;
  var positiveCheckRequests = 0, positiveSeedSent = 0;
  var readinessSamples = 0, unstableSamples = 0, unmatchedStunSamples = 0;
  final receiptKey = stage == 'checks'
      ? 'tablet_check_bindings'
      : 'tablet_stun_bindings';
  final requestKey = stage == 'checks'
      ? 'tablet_check_requests'
      : 'tablet_stun_received';
  // Poll actual native phases, not a synthetic callback or elapsed sleep.
  while (true) {
    _require(
      !taskTerminal && stageWatch.elapsedMilliseconds < 15000,
      '$stage positive control unavailable before task completion',
    );
    if (peers.isNotEmpty &&
        await _phaseActive(peers.first, stage, verifiedSeedProbe)) {
      final rows = await _bindings();
      positiveFds = await _fds();
      positiveOwners = await _owners();
      if (rows.isNotEmpty &&
          positiveFds >= rows.length &&
          (positiveOwners['peerConnections'] ?? 0) > 0 &&
          (positiveOwners['dataChannels'] ?? 0) > 0) {
        final observed = await _control('status');
        _require(
          observed['stun_worker_error'] == null,
          'Real STUN observation worker failed',
        );
        positiveStun = observed[requestKey] as int;
        positiveCheckRequests = observed['tablet_check_requests'] as int;
        positiveSeedSent = observed['seed_sent_bytes'] as int;
        if (positiveStun > 0 &&
            await _phaseActive(peers.first, stage, verifiedSeedProbe)) {
          if (stage == 'checks') {
            final fault = observed['candidate_fault'] as Map;
            final counts = fault['candidate_destinations_rewritten'] as Map;
            _require(
              fault['enabled'] == true &&
                  (counts['to_seed'] as int) > 0 &&
                  (counts['to_tablet'] as int) > 0 &&
                  (observed['active_rtc'] as int) > 0,
              'Bidirectional real ICE checking fault lacks a native owner',
            );
          }
          if (stage == 'connected') {
            _require(
              verifiedSeedProbe &&
                  positiveSeedSent > 0 &&
                  (observed['active_rtc'] as int) > 0,
              'Connected phase lacks verified actual seed payload',
            );
          }
          final stunBindings = observed[receiptKey];
          _require(
            stunBindings is List &&
                stunBindings.isNotEmpty &&
                stunBindings.length <= 32,
            'Missing actual STUN source bindings',
          );
          final matchesStun = rows.any(
            (row) => (stunBindings as List).any(
              (stun) =>
                  stun is Map &&
                  row['family'] == stun['family'] &&
                  row['port'] == stun['port'] &&
                  (row['address'] == stun['address'] ||
                      row['address'] == '0.0.0.0' ||
                      row['address'] == '::'),
            ),
          );
          readinessSamples++;
          if (!matchesStun) {
            unmatchedStunSamples++;
            if (readinessSamples <= 8) {
              _record('${stage}_snapshot_not_yet_ready', {
                'bindings': rows,
                'tablet_STUN_bindings': stunBindings,
                'UDP_FDs': positiveFds,
                'matched_actual_STUN': false,
              });
            }
            // Independent native calls sample a moving gathering process.
            // An earlier short-lived UDP socket is not proof that the actual
            // STUN socket is currently owned. Keep the original 15s stage
            // acquisition budget; do not start cancellation without proof.
            await Future<void>.delayed(const Duration(milliseconds: 10));
            continue;
          }
          final probes = await _bindProbe(rows);
          // Preserve every per-port observation before the positive-control
          // assertion. A gathering socket may retire between two native calls;
          // the first failed batch had no evidence identifying which port.
          final occupied = probes.every(
            (r) => r['exclusiveBindSucceeded'] == false,
          );
          final stillInPhase = await _phaseActive(
            peers.first,
            stage,
            verifiedSeedProbe,
          );
          if (readinessSamples <= 8 || (occupied && stillInPhase)) {
            _record('${stage}_binding_probe', {
              'stage': stage,
              'bindings': rows,
              'exclusive_bind_succeeded': [
                for (final row in probes) row['exclusiveBindSucceeded'],
              ],
              'tablet_STUN_bindings': observed[receiptKey],
              'STUN_receipt_kind': stage == 'checks'
                  ? 'connectivity_check'
                  : 'discovery_or_check',
              'tablet_ICE_check_requests': positiveCheckRequests,
              'server_active_RTC': observed['active_rtc'],
              'candidate_fault': observed['candidate_fault'],
              'verified_seed_probe': verifiedSeedProbe,
              'seed_sent_bytes': positiveSeedSent,
              'owners': positiveOwners,
              'UDP_FDs': positiveFds,
              'matched_actual_STUN': matchesStun,
              'all_sampled_bindings_occupied': occupied,
              'native_state_after_sampling': stillInPhase
                  ? (stage == 'gather' ? 'gathering' : stage)
                  : 'left_phase',
              'native_ICE_state': (await peers.first.getIceConnectionState())
                  .toString(),
            });
          }
          if (!occupied || !stillInPhase) {
            unstableSamples++;
            await Future<void>.delayed(const Duration(milliseconds: 10));
            continue;
          }
          held = rows;
          _record('positive', {
            'stage': stage,
            'owners': positiveOwners,
            'UDP_FDs': positiveFds,
            'ports': held,
            'tablet_STUN_requests': positiveStun,
            'tablet_ICE_check_requests': positiveCheckRequests,
            'verified_seed_probe': verifiedSeedProbe,
            'seed_sent_bytes': positiveSeedSent,
            'task_terminal': taskTerminal,
            'received_bytes': transferred,
          });
          break;
        }
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  _require(
    await _phaseActive(peers.first, stage, verifiedSeedProbe),
    'Native $stage phase ended before cancellation',
  );
  final closing = Stopwatch()..start();
  var disposeDone = false;
  final disposing = sdk.dispose().then((_) {
    disposeDone = true;
  });
  disposing.ignore();
  _record('dispose_started', {'stage': stage, 'received_bytes': transferred});
  var physicalMs = -1;
  while (closing.elapsedMilliseconds <= 6000) {
    final current = await _owners();
    final ports = await _bindings();
    final fds = await _fds();
    final rebound = await _bindProbe(held);
    if (current.values.every((n) => n == 0) &&
        ports.isEmpty &&
        fds == 0 &&
        rebound.every((r) => r['exclusiveBindSucceeded'] == true)) {
      physicalMs = closing.elapsedMilliseconds;
      _record('physical_released', {
        'elapsed_ms': physicalMs,
        'owners': current,
        'UDP_FDs': fds,
        'ports_rebound': rebound.length,
      });
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  _require(
    physicalMs >= 0 && physicalMs <= 6000,
    'Physical resource release exceeded 6 seconds',
  );
  final remaining = 12000 - closing.elapsedMilliseconds;
  _require(remaining > 0, 'Whole cancellation exceeded 12 seconds');
  await disposing.timeout(Duration(milliseconds: remaining));
  Map<String, dynamic> server;
  do {
    server = await _control('status');
    if (server['idle'] == true) break;
    _require(
      closing.elapsedMilliseconds < 12000,
      'Actual server owners remain after cancellation',
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
  } while (true);
  _require(
    closing.elapsedMilliseconds <= 12000 &&
        disposeDone &&
        taskTerminal &&
        taskError == 'cancelled' &&
        server['quotas_unchanged'] == true,
    'Incomplete task retirement or changed quotas',
  );
  await progress.cancel();
  await Future<void>.delayed(const Duration(milliseconds: 200));
  _require(
    (await _owners()).values.every((n) => n == 0) &&
        await _fds() == 0 &&
        (await _bindings()).isEmpty &&
        _asyncErrors.isEmpty,
    'Late native ownership or asynchronous failure',
  );
  final wholeMs = closing.elapsedMilliseconds;
  _require(
    wholeMs <= 12000,
    'Whole quiet-period observation exceeded 12 seconds',
  );
  _record('sdk_terminal', {
    'whole_close_ms': wholeMs,
    'task_error': taskError,
    'server_idle': true,
    'available_OS_slots': server['available_os_slots'],
    'live_sessions': server['live_sessions'],
    'report_pending': (server['report_gate'] as Map)['pending_responses'],
    'quotas_unchanged': true,
  });
  return {
    'passed': true,
    'stage': meta['stage'],
    'round': meta['round'],
    'physical_close_ms': physicalMs,
    'whole_close_ms': wholeMs,
    'native_peers_created': peers.length,
    'positive_UDP_bindings': held.length,
    'positive_datagram_FDs': positiveFds,
    'tablet_STUN_requests': positiveStun,
    'tablet_ICE_check_requests': positiveCheckRequests,
    'verified_seed_probe': verifiedSeedProbe,
    'seed_sent_bytes_before_cancel': positiveSeedSent,
    'matched_actual_STUN_before_cancel': true,
    'readiness_samples': readinessSamples,
    'unmatched_STUN_samples': unmatchedStunSamples,
    'unstable_binding_samples': unstableSamples,
    'task_error': taskError,
    'original_6_12_limits_preserved': true,
    'SDK_runtime_changed': true,
    'production_contacted': false,
    'full_T15_complete': false,
    'async_errors': _asyncErrors,
  };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final status = ValueNotifier<String>('P8P Android 会话阶段验收中');
  PlatformDispatcher.instance.onError = (error, stack) {
    if (_asyncErrors.length < 16) {
      _asyncErrors.add(error.runtimeType.toString());
    }
    return false;
  };
  final previousFlutterError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (_asyncErrors.length < 16) {
      _asyncErrors.add(details.exception.runtimeType.toString());
    }
    previousFlutterError?.call(details);
  };
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: ValueListenableBuilder<String>(
          valueListenable: status,
          builder: (context, value, child) =>
              SingleChildScrollView(child: Text(value)),
        ),
      ),
    ),
  );
  var terminal = 'failed';
  String? failure;
  try {
    _record('result', await _run());
    terminal = 'passed';
  } catch (error) {
    failure = '${error.runtimeType}: $error';
    if (failure.length > 1600) {
      failure = failure.substring(0, 1600);
    }
  }
  final envelope = <String, Object?>{
    'schema': 1,
    'terminal': terminal,
    'records': _records,
  };
  if (failure != null) {
    envelope['error'] = failure;
  }
  final packet = jsonEncode(envelope);
  _require(
    utf8.encode(packet).length <= 60000,
    'Lifecycle UI evidence overflow',
  );
  status.value = 'P8P_LIFECYCLE_EVIDENCE $packet';
  debugPrintSynchronously('P8P_LIFECYCLE_TERMINAL $terminal');
}
