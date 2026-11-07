// Manual benchmark: flutter test tool/full_engine_benchmark_test.dart. The
// version runner copies this SAME workload into both SDKs; only the small
// profile factory changes to omit the absent enableP8P argument in SDK 1.0.3.
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:ring_download_sdk/compat.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/loopback_payload.dart';
import 'full_engine_profile.dart' as profile;

const _chunk = 1048576;
const _url = 'https://download.csnas.asia/lifering/download';
const _capability = {
  'version': 1,
  'channel': 'p8p-file-v1',
  'header_bytes': 16,
  'max_frame_bytes': 49152,
  'max_inflight': 4,
  'cancel': true,
};

/// All requests on a source share this queue. More Range requests do not
/// increase its byte grant. A common queue models a receiver bottleneck.
class _Pump {
  _Pump({this.bytesPerTick = 32768});
  final int bytesPerTick;
  final jobs = Queue<_Job>();
  late final Timer timer;
  bool busy = false;
  int ticks = 0;
  void start() {
    timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
      if (!busy) unawaited(_tick());
    });
  }

  Future<void> _tick() async {
    busy = true;
    ticks++;
    try {
      while (jobs.isNotEmpty && jobs.first.cancelled) {
        jobs.removeFirst().finish();
      }
      if (jobs.isEmpty) return;
      final job = jobs.removeFirst();
      try {
        final end = min(job.end, job.offset + bytesPerTick);
        await job.send(job.offset, end);
        job.offset = end;
      } catch (error) {
        job.cancelled = true;
        if (error is! SocketException && error is! HttpException) rethrow;
      }
      if (job.cancelled || job.offset == job.end) {
        job.finish();
      } else {
        jobs.add(job);
      }
    } finally {
      busy = false;
    }
  }

  Future<void> close() async {
    timer.cancel();
    while (busy) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    for (final job in jobs) {
      job.cancelled = true;
      job.finish();
    }
    jobs.clear();
  }
}

class _Job {
  _Job(this.offset, this.end, this.send, {this.onDone});
  int offset;
  final int end;
  final Future<void> Function(int, int) send;
  final void Function()? onDone;
  final done = Completer<void>();
  bool cancelled = false;
  void finish() {
    if (done.isCompleted) return;
    onDone?.call();
    done.complete();
  }
}

class _HttpOrigin extends LoopbackPayload {
  _HttpOrigin(super.bytes, this.pump);
  final _Pump pump;
  late HttpServer server;
  final handlers = <Future<void>>{};
  final ownedJobs = <_Job>[];
  final ownedSockets = <Socket>{};
  @override
  Uri get uri => Uri.parse('http://127.0.0.1:${server.port}/payload');
  @override
  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      late final Future<void> handler;
      handler = serve(request).whenComplete(() => handlers.remove(handler));
      handlers.add(handler);
    });
  }

  Future<void> serve(HttpRequest request) async {
    active++;
    peakActive = max(active, peakActive);
    _Job? job;
    PayloadExchange? exchange;
    Socket? socket;
    StreamSubscription<Uint8List>? incoming;
    var peerClosed = false;
    try {
      final match = RegExp(
        r'^bytes=(\d+)-(\d*)$',
      ).firstMatch(request.headers.value('range') ?? '');
      final start = match == null ? 0 : int.parse(match[1]!);
      final end = match == null || match[2]!.isEmpty
          ? bytes.length - 1
          : int.parse(match[2]!);
      if (start > end || end >= bytes.length) throw StateError('Invalid range');
      exchange = PayloadExchange(
        Uri.parse(request.uri.queryParameters['source']!),
        '',
        start,
        end,
        const {},
      );
      exchanges.add(exchange);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // HttpResponse.add/flush can keep accepting discarded writes after the
      // client socket has closed. Observe raw peer EOF so a dead bootstrap
      // cannot keep consuming the shared byte-grant queue.
      final wire = await request.response.detachSocket(writeHeaders: false);
      socket = wire;
      ownedSockets.add(wire);
      void disconnected() {
        peerClosed = true;
        exchange?.disconnected = true;
        job?.cancelled = true;
        wire.destroy();
      }

      incoming = wire.listen(
        (_) {},
        onDone: disconnected,
        onError: (Object _) => disconnected(),
        cancelOnError: true,
      );
      final headers =
          StringBuffer(
              match == null
                  ? 'HTTP/1.1 200 OK\r\n'
                  : 'HTTP/1.1 206 Partial Content\r\n',
            )
            ..write('Content-Length: ${end - start + 1}\r\n')
            ..write('ETag: "benchmark-release"\r\n')
            ..write('X-Download-Session-Id: 0123456789abcdef\r\n')
            ..write('Connection: close\r\n');
      if (match != null) {
        headers.write('Content-Range: bytes $start-$end/${bytes.length}\r\n');
      }
      wire.add(utf8.encode('$headers\r\n'));
      await wire.flush();
      final current = exchange;
      job = _Job(start, end + 1, (start, end) async {
        if (peerClosed) throw const SocketException('fixture_peer_closed');
        wire.add(Uint8List.sublistView(bytes, start, end));
        current.offeredBytes += end - start;
        await wire.flush();
      });
      final pending = job;
      pending.cancelled = peerClosed;
      ownedJobs.add(pending);
      pump.jobs.add(pending);
      await pending.done.future;
    } on SocketException {
      exchange?.disconnected = true;
    } on HttpException {
      exchange?.disconnected = true;
    } catch (error) {
      errors.add(error.toString());
    } finally {
      job?.cancelled = true;
      try {
        if (socket == null) {
          await request.response.close();
        } else if (!peerClosed) {
          await socket.close();
        }
      } catch (_) {}
      socket?.destroy();
      await incoming?.cancel();
      ownedSockets.remove(socket);
      exchange?.finished = true;
      active--;
    }
  }

  @override
  Future<void> close() async {
    for (final job in ownedJobs) {
      job.cancelled = true;
    }
    for (final socket in ownedSockets.toList()) {
      socket.destroy();
    }
    await server.close(force: true);
    await Future.wait(handlers.toList());
  }
}

class _Fixture {
  _Fixture(this.payload, this.rtcPump, this.dropSeed) {
    digest = sha256.convert(payload).toString();
    hashes = [
      for (var i = 0; i < payload.length; i += _chunk)
        sha256
            .convert(
              Uint8List.sublistView(
                payload,
                i,
                min(i + _chunk, payload.length),
              ),
            )
            .toString(),
    ];
    signal.interceptors.add(InterceptorsWrapper(onRequest: control));
  }
  final Uint8List payload;
  final _Pump rtcPump;
  final bool dropSeed;
  final signal = Dio(), telemetry = Dio();
  final events = StreamController<dynamic>.broadcast();
  final peers = <_Peer>[];
  final diagnostics = <AppUpgradeP2PDiagnostic>[];
  late final String digest;
  late final List<String> hashes;
  int rtcBodyBytes = 0, rtcFrameBytes = 0, requests = 0;
  AppUpgradeInfo get info => AppUpgradeInfo(
    releaseId: 'benchmark',
    versionName: 'benchmark',
    versionCode: 1,
    releaseNotes: '',
    forceUpdate: false,
    downloadUrl: _url,
    fileSize: payload.length,
    sha256: digest,
    downloadProtocol: 'APK_SERVICE_V40',
    downloadSlug: 'lifering',
    downloadEtag: '"benchmark-release"',
  );
  Future<void> control(
    RequestOptions request,
    RequestInterceptorHandler handler,
  ) async {
    requests++;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final endpoint = request.uri.pathSegments.last;
    Object data = {'ok': true};
    switch (endpoint) {
      case 'manifest':
        data = {
          'status': 'ok',
          'auto_start': true,
          'protocol_version': 1,
          'app_slug': 'lifering',
          'version': 'benchmark',
          'file_size': payload.length,
          'sha256': digest,
          'chunk_size': _chunk,
          'piece_hashes': hashes,
          'stun_urls': ['stun:example.test:3479'],
          'peer_api_base': '/api/app/lifering/p2p',
          'server_seed_url':
              'https://download1.csnas.asia/api/app/lifering/p2p/server-offer',
          'fallback_url': _url,
          'trickle_ice_supported': true,
          'trickle_ice_protocol_version': 1,
          'p2p_connect_timeout_ms': 8000,
          'p2p_ice_gather_timeout_ms': 6000,
          'p8p': {
            'version': 1,
            'max_window': 4,
            'features': ['adaptive_window_v1', 'capacity_advice_v1'],
            'transfer': _capability,
          },
        };
      case 'session':
        data = {
          'session_id': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          'token': 'benchmark-fixture-token',
          'heartbeat_interval': 20,
          'share_enabled': false,
        };
      case 'peers':
        data = {'peers': []};
      case 'signals':
        data = {'signals': [], 'candidates': []};
      case 'server-offer':
        data = {
          'type': 'answer',
          'sdp': 'v=0',
          'data_channel': 'lifering-apk-p2p-v1',
          'max_batch_pieces': 4,
        };
    }
    handler.resolve(
      Response(requestOptions: request, statusCode: 200, data: data),
    );
  }
}

class _Peer extends RTCPeerConnection {
  _Peer(_Fixture fixture) : channel = _Channel(fixture);
  final _Channel channel;
  bool closed = false;
  @override
  Future<RTCDataChannel> createDataChannel(
    String label,
    RTCDataChannelInit init,
  ) async {
    channel.channelLabel = label;
    return channel;
  }

  @override
  Future<RTCSessionDescription> createOffer([
    Map<String, dynamic>? constraints,
  ]) async => RTCSessionDescription('v=0', 'offer');
  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {
    onIceGatheringState?.call(
      RTCIceGatheringState.RTCIceGatheringStateComplete,
    );
  }

  @override
  Future<RTCSessionDescription?> getLocalDescription() async =>
      RTCSessionDescription('v=0', 'offer');
  @override
  Future<RTCIceGatheringState?> getIceGatheringState() async =>
      RTCIceGatheringState.RTCIceGatheringStateComplete;
  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    onIceConnectionState?.call(
      RTCIceConnectionState.RTCIceConnectionStateConnected,
    );
    channel.open();
  }

  @override
  Future<void> close() async {
    closed = true;
    await channel.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Channel extends RTCDataChannel {
  _Channel(this.fixture) {
    stateChangeStream = states.stream;
  }
  final _Fixture fixture;
  final states = StreamController<RTCDataChannelState>.broadcast();
  final pending = Queue<Map>();
  final canceled = <int>{};
  _Job? active;
  Future<void>? closing;
  Map? activeRequest;
  String channelLabel = 'lifering-apk-p2p-v1';
  RTCDataChannelState stateValue = RTCDataChannelState.RTCDataChannelConnecting;
  bool get leased => channelLabel == 'p8p-file-v1';
  @override
  RTCDataChannelState get state => stateValue;
  @override
  String get label => channelLabel;
  @override
  int get id => 1;
  @override
  int get bufferedAmount => 0;
  void open() {
    stateValue = RTCDataChannelState.RTCDataChannelOpen;
    states.add(stateValue);
  }

  void text(Map value) =>
      onMessage?.call(RTCDataChannelMessage(jsonEncode(value)));
  Map marker(Map request, String type) => leased
      ? {
          'type': type,
          'version': 1,
          'generation': request['generation'],
          'request_id': request['request_id'],
          'index': request['index'],
        }
      : {'type': type, 'index': request['index']};
  @override
  Future<void> send(RTCDataChannelMessage message) async {
    if (message.isBinary) throw StateError('Unexpected binary request');
    final value = jsonDecode(message.text) as Map;
    if (value['type'] == 'hello') {
      text({
        'type': 'hello',
        'version': 1,
        'generation': value['generation'],
        'sha256': fixture.digest,
        'max_inflight': 4,
      });
    } else if (value['type'] == 'cancel') {
      final id = value['request_id'] as int;
      canceled.add(id);
      if (activeRequest?['request_id'] == id) active?.cancelled = true;
      final queued = pending.where((r) => r['request_id'] == id).toList();
      for (final request in queued) {
        pending.remove(request);
        text(marker(request, 'cancelled'));
      }
    } else if (value['type'] == 'get' || value['type'] == 'get-piece') {
      pending.add(value);
      pump();
    } else if (value['type'] == 'get-pieces') {
      for (final index in value['indices'] as List) {
        pending.add({...value, 'index': index});
      }
      pump();
    }
  }

  void pump() {
    if (active != null ||
        pending.isEmpty ||
        stateValue != RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }
    final request = pending.removeFirst();
    activeRequest = request;
    final index = request['index'] as int,
        start = (request['index'] as int) * _chunk;
    final end = min(start + _chunk, fixture.payload.length);
    text({
      ...marker(request, 'piece-start'),
      'size': end - start,
      if (!leased && request['pipeline_window'] == 4) 'pipeline_window': 4,
    });
    late final _Job job;
    job = _Job(
      start,
      end,
      (offset, end) async {
        if (fixture.dropSeed && fixture.rtcBodyBytes >= 3 * _chunk) {
          job.cancelled = true;
          scheduleMicrotask(() => unawaited(close()));
          return;
        }
        if (stateValue != RTCDataChannelState.RTCDataChannelOpen) {
          job.cancelled = true;
          return;
        }
        final body = Uint8List.sublistView(fixture.payload, offset, end);
        final frame = leased
            ? profile.encodeBenchmarkFrame(
                request['generation'] as int,
                request['request_id'] as int,
                offset - start,
                body,
              )
            : body;
        fixture.rtcBodyBytes += body.length;
        fixture.rtcFrameBytes += frame.length;
        onMessage?.call(RTCDataChannelMessage.fromBinary(frame));
      },
      onDone: () {
        if (stateValue == RTCDataChannelState.RTCDataChannelOpen) {
          text(marker(request, job.cancelled ? 'cancelled' : 'piece-end'));
        }
        active = null;
        activeRequest = null;
        scheduleMicrotask(pump);
      },
    );
    // The sender has one physical stream per connection for both protocols.
    if (leased && canceled.contains(request['request_id'])) {
      job.cancelled = true;
    }
    active = job;
    fixture.rtcPump.jobs.add(job);
    if (index < 0) throw StateError('Invalid piece');
  }

  @override
  Future<void> close() => closing ??= Future<void>.microtask(_close);
  Future<void> _close() async {
    stateValue = RTCDataChannelState.RTCDataChannelClosed;
    pending.clear();
    active?.cancelled = true;
    onDataChannelState?.call(stateValue);
    await active?.done.future;
    await states.close();
  }
}

/// Current process CPU, including this fixture and simulated sender. Never
/// presented as Android-only client CPU. Allocation is freed on every sample.
double? _cpuMs() {
  if (!Platform.isWindows) return null;
  final library = ffi.DynamicLibrary.open('kernel32.dll');
  final alloc = library
      .lookupFunction<
        ffi.Pointer<ffi.Void> Function(ffi.Uint32, ffi.IntPtr),
        ffi.Pointer<ffi.Void> Function(int, int)
      >('LocalAlloc');
  final free = library
      .lookupFunction<
        ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>),
        ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>)
      >('LocalFree');
  final process = library
      .lookupFunction<
        ffi.Pointer<ffi.Void> Function(),
        ffi.Pointer<ffi.Void> Function()
      >('GetCurrentProcess');
  final times = library
      .lookupFunction<
        ffi.Int32 Function(
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Uint32>,
          ffi.Pointer<ffi.Uint32>,
          ffi.Pointer<ffi.Uint32>,
          ffi.Pointer<ffi.Uint32>,
        ),
        int Function(
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Uint32>,
          ffi.Pointer<ffi.Uint32>,
          ffi.Pointer<ffi.Uint32>,
          ffi.Pointer<ffi.Uint32>,
        )
      >('GetProcessTimes');
  final memory = alloc(0, 32);
  if (memory == ffi.nullptr) throw StateError('Cannot sample CPU');
  try {
    final p = memory.cast<ffi.Uint32>();
    if (times(process(), p, p + 2, p + 4, p + 6) == 0) {
      throw StateError('Cannot read CPU');
    }
    return (((p + 5).value << 32) +
            (p + 4).value +
            ((p + 7).value << 32) +
            (p + 6).value) /
        10000;
  } finally {
    free(memory);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('HTTP origin stops granting bytes after peer disconnect', () async {
    final pump = _Pump(bytesPerTick: 16384)..start();
    final origin = _HttpOrigin(Uint8List(12 * _chunk + 137), pump);
    Socket? peer;
    StreamSubscription<Uint8List>? reader;
    final received = Completer<void>();
    try {
      await origin.start();
      final connection = await Socket.connect(
        InternetAddress.loopbackIPv4,
        origin.uri.port,
      );
      peer = connection;
      var count = 0;
      reader = connection.listen((bytes) {
        count += bytes.length;
        if (count >= 65536 && !received.isCompleted) received.complete();
      }, onError: received.completeError);
      connection.write(
        'GET /payload?source=${Uri.encodeQueryComponent(_url)} HTTP/1.1\r\n'
        'Host: 127.0.0.1\r\nConnection: close\r\n\r\n',
      );
      await connection.flush();
      await received.future.timeout(const Duration(seconds: 2));
      connection.destroy();
      await reader.cancel();
      await origin.waitIdle();
      final exchange = origin.exchanges.single;
      expect(exchange.disconnected, true);
      expect(exchange.finished, true);
      expect(exchange.offeredBytes, lessThan(origin.bytes.length));
      final offered = exchange.offeredBytes;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(exchange.offeredBytes, offered);
      expect(pump.jobs, isEmpty);
      expect(origin.active, 0);
      expect(origin.errors, isEmpty);
    } finally {
      peer?.destroy();
      await reader?.cancel();
      await origin.close();
      await pump.close();
    }
  });

  test('full engine controlled version benchmark', () async {
    // This manual Flutter test lives outside test/ to avoid making the normal
    // regression suite execute all performance experiments.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final scenario =
        Platform.environment['P8P_BENCH_SCENARIO'] ?? 'independent';
    final output = Platform.environment['P8P_BENCH_OUTPUT'] ?? '';
    if (![
      'independent',
      'receiver-bottleneck',
      'seed-drop',
      'asymmetric',
    ].contains(scenario)) {
      throw ArgumentError('Unknown benchmark scenario');
    }
    final payload = Uint8List(12 * _chunk + 137);
    for (var i = 0; i < payload.length; i++) {
      payload[i] = i % 251;
    }
    final httpPump = _Pump(
      bytesPerTick: scenario == 'asymmetric' ? 16384 : 32768,
    )..start();
    final rtcPump = scenario == 'receiver-bottleneck'
        ? httpPump
        : (_Pump()..start());
    final fixture = _Fixture(payload, rtcPump, scenario == 'seed-drop');
    final origin = _HttpOrigin(payload, httpPump);
    await origin.start();
    fixture.telemetry.interceptors.add(
      InterceptorsWrapper(
        onRequest: (r, h) =>
            h.resolve(Response(requestOptions: r, statusCode: 201)),
      ),
    );
    final directory = await Directory.systemTemp.createTemp(
      'p8p-full-engine-benchmark-',
    );
    final http = Dio()..httpClientAdapter = LoopbackPayloadAdapter(origin);
    final watch = Stopwatch();
    int? firstProgress, firstVerifiedPiece;
    final client = profile.createBenchmarkClient({
      #dio: fixture.signal,
      #isAndroid: true,
      #allowSharing: false,
      #hybridStartup: true,
      #fastSignaling: true,
      #preferredSeedBatchPieces: 4,
      #preferredPeerBatchPieces: 4,
      #sharingDuration: Duration.zero,
      #networkReader: () async => AppUpgradeP2PNetwork.wifiUnmetered,
      #networkEvents: fixture.events.stream,
      #diagnostic: (AppUpgradeP2PDiagnostic event) {
        fixture.diagnostics.add(event);
        if (event.code == 'piece_verified') {
          firstVerifiedPiece ??= watch.elapsedMilliseconds;
        }
      },
      #peerFactory: (Map<String, dynamic> configuration) async {
        final peer = _Peer(fixture);
        fixture.peers.add(peer);
        return peer;
      },
    });
    final downloader = AppUpgradeV40DownloadClient(
      dio: http,
      p2pClient: client,
      httpsHeadStart: true,
      supportDirectoryLoader: () async => directory,
      serviceEvents: AppUpgradeServiceEvents(dio: fixture.telemetry),
    );
    final cancel = CancelToken();
    final startRss = ProcessInfo.currentRss;
    var peakRss = startRss;
    final sample = Timer.periodic(const Duration(milliseconds: 20), (_) {
      peakRss = max(peakRss, ProcessInfo.currentRss);
    });
    final cpuStart = _cpuMs();
    try {
      watch.start();
      final file = await downloader
          .download(
            info: fixture.info,
            url: _url,
            backupUrl: null,
            refreshRelease: () async => fixture.info,
            cancelToken: cancel,
            onProgress: (bytes, total) {
              if (bytes > 0) firstProgress ??= watch.elapsedMilliseconds;
            },
          )
          .timeout(const Duration(seconds: 45));
      watch.stop();
      sample.cancel();
      final cpuEnd = _cpuMs();
      final checksum = sha256.convert(await file.readAsBytes()).toString();
      expect(checksum, fixture.digest);
      final bootstrap = origin.exchanges.first;
      final bootstrapFinishedAtCompletion = bootstrap.finished;
      final bootstrapOfferedAtCompletion = bootstrap.offeredBytes;
      await origin.waitIdle();
      expect(bootstrap.finished, true);
      expect(bootstrap.offeredBytes, lessThan(payload.length));
      expect(origin.errors, isEmpty);
      expect(fixture.peers.every((peer) => peer.closed), true);
      final multi = fixture.diagnostics.any(
        (event) => event.code == 'multisource_started',
      );
      if (profile.profileName == 'p8p') expect(multi, true);
      final profiles = fixture.diagnostics
          .where((event) => event.code == 'multisource_profile')
          .toList();
      final httpBytes = downloader.lastHttpsBodyBytes;
      final totalBody = httpBytes + fixture.rtcBodyBytes;
      expect(totalBody, greaterThanOrEqualTo(payload.length));
      final result = {
        'profile': profile.profileName,
        'scenario': scenario,
        'file_bytes': payload.length,
        'sha256': checksum,
        'verified': true,
        'complete_ms': watch.elapsedMilliseconds,
        'first_progress_ms': firstProgress,
        'first_verified_rtc_piece_ms': firstVerifiedPiece,
        'http_received_body_bytes': httpBytes,
        'http_origin_offered_body_bytes': origin.exchanges.fold<int>(
          0,
          (sum, exchange) => sum + exchange.offeredBytes,
        ),
        'bootstrap_origin_finished_at_completion':
            bootstrapFinishedAtCompletion,
        'bootstrap_origin_offered_at_completion': bootstrapOfferedAtCompletion,
        'bootstrap_origin_offered_body_bytes': bootstrap.offeredBytes,
        'rtc_delivered_body_bytes': fixture.rtcBodyBytes,
        'rtc_delivered_frame_bytes': fixture.rtcFrameBytes,
        'redundant_received_body_bytes': totalBody - payload.length,
        'http_requests': origin.exchanges.length,
        'http_peak_active_responses': origin.peakActive,
        'control_requests': fixture.requests,
        'start_process_rss_bytes': startRss,
        'sampled_peak_process_rss_bytes': peakRss,
        'process_cpu_ms': cpuStart == null || cpuEnd == null
            ? null
            : cpuEnd - cpuStart,
        'multisource_started': multi,
        'queue_metrics': profiles.isEmpty ? null : profiles.last.metrics,
        'rtc_channel_labels': fixture.peers
            .map((peer) => peer.channel.label)
            .toSet()
            .toList(),
        'http_shaper_ticks': httpPump.ticks,
        'rtc_shaper_ticks': rtcPump.ticks,
        'http_bytes_per_tick': httpPump.bytesPerTick,
        'rtc_bytes_per_tick': rtcPump.bytesPerTick,
        'active_payload_handlers_after': origin.active,
        'all_rtc_peers_closed': fixture.peers.every((peer) => peer.closed),
      };
      if (output.isNotEmpty) {
        await File(output).writeAsString(jsonEncode(result));
      }
      // Captured once by the version runner; stdout remains usable without it.
      // ignore: avoid_print
      print('P8P_FULL_ENGINE_RESULT ${jsonEncode(result)}');
    } finally {
      sample.cancel();
      cancel.cancel('fixture_done');
      await client.stopSharing();
      http.close(force: true);
      fixture.signal.close(force: true);
      fixture.telemetry.close(force: true);
      await origin.close();
      await fixture.events.close();
      await httpPump.close();
      if (!identical(httpPump, rtcPump)) await rtcPump.close();
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
