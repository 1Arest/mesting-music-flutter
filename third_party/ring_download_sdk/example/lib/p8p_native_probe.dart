// Manual Android acceptance entry point. Never import this from a host app.
// Fixture mode maps synthetic hosts to an ADB-reversed TLS socket. Direct
// service mode leaves SDK DNS/TLS untouched and maps only private test control.
// SDK logic, platform network detection and flutter_webrtc remain unmodified.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:ring_download_sdk/ring_download_sdk.dart';

final _phaseWatch = Stopwatch()..start();
final _probePhases = <Map<String, Object>>[];
final _nativeEvidence = NativeProbeEvidence();
_FixtureHttp? _directControlTransport;

HttpClient _probeControlHttp() =>
    _directControlTransport?.createHttpClient(null) ?? HttpClient();

/// Bounded observations for this manual probe, never an SDK or host App API.
/// Samples are copied at the original observation point; nothing is inferred
/// from a completed transfer, buffer presence, or a missing log line.
class NativeProbeEvidence {
  static const _ownerKeys = {
    'peerConnections',
    'dataChannels',
    'channelObservers',
  };
  static const _states = {
    'resumed',
    'inactive',
    'hidden',
    'paused',
    'detached',
  };
  int _queries = 0, _lastTime = 0, _bufferQueries = 0;
  int? _peak;
  bool _paused = false, _invalid = false;
  Map<String, Object?>? _initial, _final, _positiveOne, _positiveTwo;
  final _lifecycle = <Map<String, Object?>>[];
  final _overlap = <String, Map<String, Object?>?>{'start': null, 'end': null};

  Never _fail(String reason) {
    _invalid = true;
    throw StateError(reason);
  }

  void _time(int elapsed) {
    if (elapsed < _lastTime || elapsed < 0 || elapsed > 600000) {
      _fail('Invalid native probe observation time');
    }
    _lastTime = elapsed;
  }

  void recordOwners(Map<String, int> counts, int elapsed) {
    _time(elapsed);
    if (counts.length != 3 ||
        !counts.keys.every(_ownerKeys.contains) ||
        counts.values.any((v) => v < 0 || v > 1024) ||
        _queries >= 100000) {
      _fail('Invalid or overflowing native owner observation');
    }
    final row = Map<String, Object?>.unmodifiable({
      'query': ++_queries,
      'elapsed_ms': elapsed,
      'counts': Map<String, int>.unmodifiable(counts),
    });
    _initial ??= row;
    _final = row;
    if (counts.values.every((v) => v >= 1)) _positiveOne ??= row;
    if (counts.values.every((v) => v >= 2)) _positiveTwo ??= row;
  }

  void recordLifecycle(String state, int elapsed) {
    _time(elapsed);
    if (!_states.contains(state) || _lifecycle.length >= 16) {
      _fail('Invalid or overflowing native lifecycle observation');
    }
    _lifecycle.add({'state': state, 'elapsed_ms': elapsed});
    if (state == 'paused') _paused = true;
  }

  void recordBuffers(List<int> values, int elapsed) {
    _time(elapsed);
    if (values.any((v) => v < 0)) {
      _fail('Invalid native buffer observation');
    }
    if (_paused) return;
    if (_bufferQueries >= 100000) {
      _fail('Native buffer observation count overflow');
    }
    _bufferQueries++;
    var peak = 0;
    for (final value in values) {
      if (value > peak) peak = value;
    }
    if (_peak == null || peak > _peak!) _peak = peak;
  }

  void recordOverlap(String name, Map<String, Object?> sample, int elapsed) {
    _time(elapsed);
    const keys = {'state', 'received', 'total', 'terminal', 'lifecycle'};
    if (!_overlap.containsKey(name) ||
        _overlap[name] != null ||
        sample.length != keys.length ||
        !sample.keys.every(keys.contains) ||
        sample['received'] is! int ||
        sample['total'] is! int ||
        !_states.contains(sample['lifecycle']) ||
        sample['state'] != (name == 'start' ? 'transferring' : 'cancelled') ||
        sample['terminal'] != (name == 'start' ? null : 'cancelled')) {
      _fail('Invalid or duplicate native overlap observation');
    }
    _overlap[name] = {
      'elapsed_ms': elapsed,
      'sample': Map<String, Object?>.unmodifiable(sample),
    };
  }

  String encode(List<Map<String, Object>> phases) {
    if (_invalid || _initial == null || _final == null || phases.length > 32) {
      _fail('Incomplete or invalid native probe evidence');
    }
    final encoded = jsonEncode({
      'version': 1,
      'phases': phases,
      'native': {
        'queries': _queries,
        'initial': _initial,
        'final': _final,
        'positive_one': _positiveOne,
        'positive_two': _positiveTwo,
      },
      'lifecycle': _lifecycle,
      'buffers': {
        'queries_before_pause': _bufferQueries,
        'peak_bytes_before_pause': _peak,
      },
      'overlap': _overlap,
    });
    if (utf8.encode(encoded).length > 3500) {
      _fail('Native evidence exceeds the fixed encoded line bound');
    }
    return encoded;
  }

  // This tablet truncates a single Flutter log message at 1023 bytes. Keep
  // the same actual observations in one smaller, lossless diagnostic record.
  String encodeLogRecord(List<Map<String, Object>> phases) {
    final raw = utf8.encode(encode(phases));
    final record = 'P8P_NATIVE_EVIDENCE_GZIP ${base64Encode(gzip.encode(raw))}';
    if (utf8.encode(record).length > 900) {
      _fail('Native evidence exceeds the fixed log transport bound');
    }
    return record;
  }
}

// A handful of direct phase records distinguish a blocked SDK/native owner
// from probe cleanup or delayed throttled logging. Never used by host apps.
void _probePhase(String phase) {
  if (_probePhases.length >= 32) {
    throw StateError('Bounded probe phase record overflow');
  }
  final record = <String, Object>{
    'phase': phase,
    'elapsed_ms': _phaseWatch.elapsedMilliseconds,
  };
  _probePhases.add(record);
  debugPrintSynchronously('P8P_NATIVE_PHASE ${jsonEncode(record)}');
}

class _SharingLifecycleLog with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _nativeEvidence.recordLifecycle(
      state.name,
      _phaseWatch.elapsedMilliseconds,
    );
    debugPrint('P8P_NATIVE_SHARING_LIFECYCLE ${state.name}');
  }
}

// Exercise the public task/SDK lifetime while the same receive session also
// uploads verified pieces. A completed download cannot satisfy this probe.
Future<void> _receiveSharingCommands(
  RingDownloadSdk sdk,
  RingDownloadTask task,
  String completionNonce,
) async {
  final http = HttpClient();
  final watch = Stopwatch()..start();
  String? terminal;
  final completion = task.completed.then<void>(
    (_) => terminal = 'completed',
    onError: (Object error) {
      terminal = error is RingDownloadException
          ? error.code.name
          : error.runtimeType.toString();
    },
  );
  Map<String, Object?> sample() => {
    'state': task.latest.state.name,
    'received': task.latest.receivedBytes,
    'total': task.latest.totalBytes,
    'terminal': terminal,
    'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
  };
  debugPrint(
    'P8P_NATIVE_OVERLAP_READY ${jsonEncode((await sdk.inspect()).toJson())}',
  );
  try {
    while (watch.elapsed < const Duration(minutes: 2)) {
      if (terminal != null) {
        throw StateError('Download ended before overlap disposal: $terminal');
      }
      final owners = await _rtcOwners();
      debugPrint('P8P_NATIVE_RTC_OWNERS ${jsonEncode(owners)}');
      final request = await http.getUrl(
        Uri.parse('https://download.csnas.asia/__overlap__/next'),
      );
      final response = await request.close();
      if (response.statusCode != 200) {
        throw StateError('Overlap control unavailable');
      }
      final value = jsonDecode(await utf8.decodeStream(response)) as Map;
      final command = value['command'];
      if (command == 'enable') {
        sdk.setSharingEnabled(true);
      } else if (command == 'finish') {
        final before = sample();
        if (task.latest.state != RingDownloadState.transferring ||
            task.latest.receivedBytes <= 0 ||
            task.latest.receivedBytes >= task.latest.totalBytes ||
            terminal != null) {
          throw StateError('Disposal requires an incomplete active download');
        }
        _nativeEvidence.recordOverlap(
          'start',
          before,
          _phaseWatch.elapsedMilliseconds,
        );
        debugPrint('P8P_NATIVE_OVERLAP_DISPOSE_START ${jsonEncode(before)}');
        await sdk.dispose();
        await completion;
        if (terminal != RingDownloadError.cancelled.name ||
            task.latest.state != RingDownloadState.cancelled) {
          throw StateError('SDK disposal did not cancel the receiving task');
        }
        final after = sample();
        _nativeEvidence.recordOverlap(
          'end',
          after,
          _phaseWatch.elapsedMilliseconds,
        );
        debugPrint('P8P_NATIVE_OVERLAP_DISPOSE_END ${jsonEncode(after)}');
        return;
      } else if (command != 'inspect' && command != 'wait') {
        throw StateError('Unknown overlap command');
      }
      if (command != 'wait') {
        final actual = jsonEncode({
          'sequence': value['sequence'],
          'command': command,
          ...sample(),
          'status': (await sdk.inspect()).toJson(),
        });
        debugPrint('P8P_NATIVE_OVERLAP_COMMAND $actual');
        if (completionNonce.isNotEmpty) {
          await _sendProbeRecord(completionNonce, actual, true, 'observation');
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError('Receive-sharing acceptance deadline exceeded');
  } finally {
    http.close(force: true);
    // The completion listener above owns both success and failure even if
    // fixture control fails before the explicit SDK disposal command.
  }
}

Future<void> _sharingCommands(RingDownloadSdk sdk) async {
  final http = HttpClient();
  final watch = Stopwatch()..start();
  Map<String, int>? lastOwners;
  String? lastBuffers;
  debugPrint(
    'P8P_NATIVE_SHARING_READY ${jsonEncode((await sdk.inspect()).toJson())}',
  );
  try {
    while (watch.elapsed < const Duration(minutes: 3)) {
      final owners = await _rtcOwners();
      if (jsonEncode(owners) != jsonEncode(lastOwners)) {
        debugPrint('P8P_NATIVE_RTC_OWNERS ${jsonEncode(owners)}');
        lastOwners = owners;
      }
      final buffers = await const MethodChannel('p8p/native_probe_config')
          .invokeListMethod<int>('rtcBuffers')
          .timeout(const Duration(milliseconds: 500));
      if (buffers == null || buffers.any((value) => value < 0)) {
        throw StateError('Native RTC buffer observation unavailable');
      }
      _nativeEvidence.recordBuffers(buffers, _phaseWatch.elapsedMilliseconds);
      final encodedBuffers = jsonEncode(buffers);
      if (encodedBuffers != lastBuffers) {
        debugPrint(
          'P8P_NATIVE_SEND_BUFFERS ${jsonEncode({'elapsed_ms': watch.elapsedMilliseconds, 'native_buffered_bytes': buffers})}',
        );
        lastBuffers = encodedBuffers;
      }
      final request = await http.getUrl(
        Uri.parse('https://download.csnas.asia/__sharing__/next'),
      );
      final response = await request.close();
      if (response.statusCode != 200) {
        throw StateError('Sharing control unavailable');
      }
      final value = jsonDecode(await utf8.decodeStream(response)) as Map;
      final command = value['command'];
      if (command == 'finish') {
        _probePhase('sharing_finish_received');
        return;
      }
      if (command == 'enable' || command == 'disable') {
        sdk.setSharingEnabled(command == 'enable');
        debugPrint(
          'P8P_NATIVE_SHARING_COMMAND ${jsonEncode({'sequence': value['sequence'], 'command': command, 'status': (await sdk.inspect()).toJson(), 'lifecycle': WidgetsBinding.instance.lifecycleState?.name})}',
        );
      } else if (command != 'wait') {
        throw StateError('Unknown sharing control');
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw StateError('Sharing acceptance deadline exceeded');
  } finally {
    http.close(force: true);
  }
}

class _FixtureHttp extends HttpOverrides {
  _FixtureHttp(this.port, String certificate, {this.blockHosted = false})
    : context = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificatesBytes(base64Decode(certificate));

  final int port;
  final SecurityContext context;
  final bool blockHosted;

  @override
  HttpClient createHttpClient(SecurityContext? ignored) {
    final client = super.createHttpClient(context);
    client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      if (uri.scheme != 'https' ||
          !const {
            'download.csnas.asia',
            'download1.csnas.asia',
            'cos.p8p-fixture.invalid',
          }.contains(uri.host)) {
        throw StateError('Probe cannot contact a non-fixture host');
      }
      if (blockHosted && uri.host != 'cos.p8p-fixture.invalid') {
        throw const SocketException('Hosted service deliberately offline');
      }
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

Future<Map<String, int>> _rtcOwners() async {
  final raw = await const MethodChannel(
    'p8p/native_probe_config',
  ).invokeMapMethod<String, dynamic>('rtcOwners');
  if (raw == null ||
      raw.length != 3 ||
      raw.values.any((v) => v is! int || v < 0)) {
    throw StateError('Native RTC counts unavailable');
  }
  final counts = raw.map((key, value) => MapEntry(key, value as int));
  _nativeEvidence.recordOwners(counts, _phaseWatch.elapsedMilliseconds);
  return counts;
}

// Private test acknowledgement only, after the original SDK disposal and
// actual final native query. All timings in the payload predate this request.
Future<void> _sendProbeRecord(
  String nonce,
  String payload,
  bool successful,
  String endpoint,
) async {
  if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(nonce) ||
      utf8.encode(payload).length > 3500 ||
      !const {'completion', 'observation'}.contains(endpoint)) {
    throw StateError('Invalid bounded probe completion');
  }
  final http = _probeControlHttp()
    ..connectionTimeout = const Duration(seconds: 1);
  try {
    final request = await http
        .postUrl(Uri.parse('https://download.csnas.asia/__sharing__/$endpoint'))
        .timeout(const Duration(seconds: 1));
    request.headers
      ..set(HttpHeaders.contentTypeHeader, 'application/json')
      ..set('X-P8P-Probe-Nonce', nonce)
      ..set('X-P8P-Probe-Outcome', successful ? 'completed' : 'failed');
    final body = utf8.encode(payload);
    request.contentLength = body.length;
    request.add(body);
    final response = await request.close().timeout(const Duration(seconds: 1));
    if (response.statusCode != 202) {
      throw StateError('Probe completion was not accepted');
    }
    await response.drain<void>().timeout(const Duration(seconds: 1));
  } finally {
    http.close(force: true);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _probePhase('main_started');
  final fixture = await const MethodChannel(
    'p8p/native_probe_config',
  ).invokeMapMethod<String, dynamic>('fixture');
  final certificate = fixture?['certificate'] as String? ?? '';
  final port = fixture?['port'] as int? ?? 0;
  final sharingProbe = fixture?['sharing'] == true;
  final overlapProbe = fixture?['overlap'] == true;
  final directService = fixture?['directService'] == true;
  final completionNonce = fixture?['completionNonce'] as String? ?? '';
  var probeSuccessful = true;
  final lifecycleLog = sharingProbe || overlapProbe
      ? _SharingLifecycleLog()
      : null;
  if (lifecycleLog != null) WidgetsBinding.instance.addObserver(lifecycleLog);
  if (certificate.isEmpty || port <= 0) {
    throw StateError('Fixture configuration missing');
  }
  if (directService) {
    if (sharingProbe || overlapProbe || HttpOverrides.current != null) {
      throw StateError(
        'Direct service probe requires unmodified SDK transport',
      );
    }
    _directControlTransport = _FixtureHttp(port, certificate);
    _probePhase('sdk_uses_system_tls');
  } else {
    HttpOverrides.global = _FixtureHttp(port, certificate);
  }
  // Every launch gets a cold SDK cache, without deleting another app's data.
  final storage = await Directory.systemTemp.createTemp('p8p-native-');
  var diagnosticEvents = 0;
  var candidateRetryEvents = 0;
  var diagnosticCountsOverflowed = false;
  final sdk = RingDownloadSdk(
    RingDownloadConfig(
      appId: 'lifering',
      enableP8P: true,
      allowSharing: false,
      storageDirectory: storage,
      onDiagnostic: (event) {
        if (diagnosticEvents < 1000000) {
          diagnosticEvents++;
        } else {
          diagnosticCountsOverflowed = true;
        }
        if (event.stage == 'candidate' && event.code == 'retry') {
          if (candidateRetryEvents < 1000000) {
            candidateRetryEvents++;
          } else {
            diagnosticCountsOverflowed = true;
          }
        }
        debugPrint('P8P_NATIVE_DIAGNOSTIC ${jsonEncode(event.toJson())}');
      },
    ),
  );
  final initialOwners = await _rtcOwners();
  if (initialOwners.values.any((v) => v != 0)) {
    throw StateError('Native RTC owners exist before the test');
  }
  debugPrint('P8P_NATIVE_RTC_INITIAL ${jsonEncode(initialOwners)}');
  try {
    debugPrint(
      'P8P_NATIVE_STATUS ${jsonEncode((await sdk.inspect()).toJson())}',
    );
    // Fixture-only selector. The server rejects all unrecognized targets.
    final selector = _probeControlHttp();
    final request = await selector.getUrl(
      Uri.parse('https://download.csnas.asia/__native__/next'),
    );
    final response = await request.close();
    final selected =
        jsonDecode(await utf8.decodeStream(response)) as Map<String, dynamic>;
    selector.close(force: true);
    final scenario = selected['scenario'] as String;
    if (directService &&
        (scenario != 'production-v1' ||
            Uri.parse(selected['url'] as String).host !=
                'download.csnas.asia')) {
      throw StateError('Direct service selector requires a production release');
    }
    if (scenario == 'external-cos') {
      HttpOverrides.global = _FixtureHttp(port, certificate, blockHosted: true);
    }
    debugPrint('P8P_NATIVE_START $scenario');
    final task = sdk.download(
      RingDownloadRequest(
        releaseId: selected['release_id'] as String? ?? '',
        version: selected['version'] as String? ?? '',
        url: Uri.parse(selected['url'] as String),
        fileSize: selected['file_size'] as int? ?? 0,
        sha256: selected['sha256'] as String? ?? '',
        etag: selected['etag'] as String? ?? '',
      ),
    );
    int lastMiB = -1;
    final subscription = task.progress.listen((progress) {
      final mib = progress.receivedBytes ~/ 1048576;
      if (mib != lastMiB) {
        lastMiB = mib;
        debugPrint(
          'P8P_NATIVE_PROGRESS ${progress.receivedBytes}/${progress.totalBytes}',
        );
      }
    });
    try {
      if (overlapProbe) {
        await _receiveSharingCommands(sdk, task, completionNonce);
      } else {
        final receipt = await task.completed.timeout(
          const Duration(minutes: 2),
        );
        await receipt.revalidate();
        debugPrint(
          'P8P_NATIVE_COMPLETE ${jsonEncode({'scenario': scenario, 'bytes': receipt.fileSize, 'sha256': receipt.sha256, 'verification': receipt.verification.name, 'elapsed_ms': receipt.elapsed.inMilliseconds})}',
        );
        if (sharingProbe) await _sharingCommands(sdk);
      }
    } finally {
      _probePhase('progress_subscription_cancel_begin');
      await subscription.cancel();
      _probePhase('progress_subscription_cancel_end');
    }
  } catch (error) {
    probeSuccessful = false;
    debugPrint('P8P_NATIVE_FAILURE ${error.runtimeType}: $error');
  } finally {
    _probePhase('sdk_dispose_begin');
    await sdk.dispose();
    _probePhase('sdk_dispose_end');
    if (lifecycleLog != null) {
      WidgetsBinding.instance.removeObserver(lifecycleLog);
    }
    _probePhase('probe_storage_delete_begin');
    await storage.delete(recursive: true);
    _probePhase('probe_storage_delete_end');
    // Android may drop a startup log burst. Preserve callback counts in one
    // small final record; a missing/overflowed record still fails acceptance.
    debugPrint(
      'P8P_NATIVE_DIAGNOSTIC_COUNTS ${jsonEncode({'events': diagnosticEvents, 'candidateRetries': candidateRetryEvents, 'overflowed': diagnosticCountsOverflowed})}',
    );
    _probePhase('final_native_owners_begin');
    final owners = await _rtcOwners();
    _probePhase('final_native_owners_end');
    debugPrint('P8P_NATIVE_RTC_FINAL ${jsonEncode(owners)}');
    if (owners.values.any((v) => v != 0)) {
      throw StateError('Native RTC owners remain after SDK disposal');
    }
    debugPrint('P8P_NATIVE_DISPOSED');
    _probePhase('disposed_marker_queued');
    if (completionNonce.isNotEmpty) {
      await _sendProbeRecord(
        completionNonce,
        _nativeEvidence.encode(_probePhases),
        probeSuccessful,
        'completion',
      );
    }
    // Android can drop several consecutive log lines during a burst. One
    // bounded aggregate preserves all times actually sampled above, without
    // changing SDK cleanup, waiting longer, or inferring missing timestamps.
    debugPrintSynchronously('P8P_NATIVE_PHASES ${jsonEncode(_probePhases)}');
    debugPrintSynchronously(_nativeEvidence.encodeLogRecord(_probePhases));
  }
}
