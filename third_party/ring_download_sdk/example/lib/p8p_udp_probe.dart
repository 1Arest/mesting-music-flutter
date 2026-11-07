// Private observer qualification, not a download or SDK lifecycle verdict.
// No STUN, hosted API, APK, production configuration or external peer is used.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

const _native = MethodChannel('p8p/native_probe_config');
final _evidence = <Map<String, Object?>>[];

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _record(String marker, Map<String, Object?> value) {
  final packet = jsonEncode(value);
  _require(
    utf8.encode(packet).length < 800,
    'Native evidence record too large',
  );
  _require(_evidence.length < 66, 'Native evidence record count exceeded');
  // Keep an immutable copy for the final accessibility snapshot. Some OEMs
  // discard the entire final log burst; missing log lines cannot prove exit.
  _evidence.add({'marker': marker, 'value': jsonDecode(packet)});
  debugPrintSynchronously('$marker $packet');
}

String _visibleEvidence(String terminal, [Object? error]) {
  final detail = error?.toString();
  final payload = jsonEncode({
    'schema': 1,
    'terminal': terminal,
    'records': _evidence,
    if (detail != null)
      'error': detail.length <= 1600 ? detail : detail.substring(0, 1600),
  });
  _require(utf8.encode(payload).length <= 60000, 'Final evidence exceeded bound');
  return 'P8P_UDP_EVIDENCE $payload';
}

Future<int> _ownedDescriptorCount() async {
  final count = await _native.invokeMethod<int>('udpOwnedDescriptorCount');
  _require(
    count != null && count >= 0 && count <= 2048,
    'Invalid own datagram descriptor count',
  );
  return count!;
}

Future<List<Map<String, Object?>>> _nativeRows(
  String method, [
  Map<String, Object?>? arguments,
]) async {
  final value = await _native.invokeListMethod<Object?>(method, arguments);
  _require(
    value != null && value.isNotEmpty && value.length <= 32,
    'Missing or excessive native observations',
  );
  return value!.map((row) => Map<String, Object?>.from(row as Map)).toList();
}

Future<List<Map<String, Object?>>> _candidateBindings(
  List<RTCPeerConnection> peers,
) async {
  final result = <String, Map<String, Object?>>{};
  for (final peer in peers) {
    var observed = 0;
    for (final report in await peer.getStats()) {
      if (report.type != 'local-candidate') continue;
      final fields = report.values;
      if (fields['protocol'] != 'udp') continue;
      final address = fields['address'] ?? fields['ip'];
      final port = int.tryParse('${fields['port']}');
      _require(
        address is String &&
            InternetAddress.tryParse(address.split('%').first) != null &&
            port != null &&
            port > 0 &&
            port <= 65535,
        'RTC stats did not expose a numeric UDP binding',
      );
      _require(
        fields['candidateType'] == 'host',
        'Unexpected non-host candidate',
      );
      observed++;
      result['$address:$port'] = {
        'address': address,
        'port': port,
        'family': (address as String).contains(':') ? 6 : 4,
      };
      _require(result.length <= 32, 'Too many observed UDP bindings');
    }
    _require(
      observed > 0,
      'No actual local UDP candidate stats for a native peer',
    );
  }
  return result.values.toList();
}

String _key(Map<String, Object?> row) =>
    '${row['family']}/${row['address']}/${row['port']}';

Future<List<Map<String, Object?>>> _ownedBindings() async {
  final text = await _native.invokeMethod<String>('udpOwnedBindings');
  _require(text != null && text.length <= 8192, 'Invalid own-FD JSON output');
  final value = jsonDecode(text!);
  _require(value is List && value.length <= 32, 'Invalid own-FD inventory');
  final seen = <String>{};
  final rows = <Map<String, Object?>>[];
  for (final input in value as List) {
    final row = Map<String, Object?>.from(input as Map);
    final address = row['address'], port = row['port'], family = row['family'];
    _require(
      row.length == 3 &&
          address is String &&
          port is int &&
          port > 0 &&
          port <= 65535 &&
          (family == 4 || family == 6),
      'Invalid own-FD fields',
    );
    final parts = (address as String).split('%');
    final ip = InternetAddress.tryParse(parts.first);
    _require(
      parts.length <= 2 &&
          ip != null &&
          (parts.length == 1 ||
              (family == 6 && RegExp(r'^[0-9]{1,10}$').hasMatch(parts.last))) &&
          (ip.type == InternetAddressType.IPv4 ? family == 4 : family == 6) &&
          seen.add(_key(row)),
      'Invalid or duplicate numeric own-FD binding',
    );
    rows.add(row);
  }
  return rows;
}

Future<void> _gather(RTCPeerConnection peer) async {
  final watch = Stopwatch()..start();
  while (peer.iceGatheringState !=
      RTCIceGatheringState.RTCIceGatheringStateComplete) {
    _require(
      watch.elapsedMilliseconds < 8000,
      'Host gathering exceeded 8 seconds',
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<Map<String, Object?>> _run() async {
  final controls = await _nativeRows('udpBindSelfCheck');
  _require(
    controls.length == 2 &&
        controls.map((r) => r['family']).toSet().containsAll({4, 6}) &&
        controls.every(
          (r) =>
              r['heldBindRejected'] == true &&
              r['releasedBindSucceeded'] == true &&
              r['ownDescriptorObserved'] == true &&
              r['ownUnboundDescriptorObserved'] == true &&
              r['ownDescriptorsReturnedToBaseline'] == true,
        ),
    'Native UDP controls failed',
  );
  _record('P8P_UDP_CONTROLS', {'controls': controls});
  final peers = <RTCPeerConnection>[];
  final channels = <RTCDataChannel>[];
  final failures = <String>[];
  var addresses = <Map<String, Object?>>[];
  var held = <Map<String, Object?>>[];
  var released = <Map<String, Object?>>[];
  final baseline = (await _ownedBindings()).map(_key).toSet();
  final baselineDescriptors = await _ownedDescriptorCount();
  var positiveDescriptors = 0, finalDescriptors = -1;
  var finalOwned = <String>{};
  var candidateCount = 0;
  var retiring = false;
  var receivedBytes = 0, closeMs = 0, wholeCloseMs = 0;
  try {
    final initial = await _native.invokeMapMethod<String, int>('rtcOwners');
    _require(
      initial != null && initial.values.every((v) => v == 0),
      'Private engine already has native owners',
    );
    const configuration = <String, Object>{'iceServers': <Object>[]};
    final left = await createPeerConnection(configuration);
    peers.add(left);
    final right = await createPeerConnection(configuration);
    peers.add(right);
    final opened = Completer<void>(), received = Completer<void>();
    Uint8List? body;
    var messages = 0;
    right.onDataChannel = (channel) {
      // A late event still owns a tracked native channel. pc.dispose below
      // drains it; it cannot add application work to this retiring probe.
      if (retiring) return;
      channels.add(channel);
      channel.onMessage = (message) {
        messages++;
        if (message.isBinary && messages == 1) body = message.binary;
        if (!received.isCompleted) received.complete();
      };
    };
    final sending = await left.createDataChannel(
      'p8p-udp-observer-v1',
      RTCDataChannelInit(),
    );
    channels.add(sending);
    sending.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen &&
          !opened.isCompleted) {
        opened.complete();
      }
    };
    await left.setLocalDescription(await left.createOffer());
    await _gather(left);
    await right.setRemoteDescription((await left.getLocalDescription())!);
    await right.setLocalDescription(await right.createAnswer());
    await _gather(right);
    await left.setRemoteDescription((await right.getLocalDescription())!);
    if (sending.state == RTCDataChannelState.RTCDataChannelOpen &&
        !opened.isCompleted) {
      opened.complete();
    }
    await opened.future.timeout(const Duration(seconds: 8));
    final expected = Uint8List.fromList(
      List<int>.generate(4096, (i) => i % 251),
    );
    await sending.send(RTCDataChannelMessage.fromBinary(expected));
    await received.future.timeout(const Duration(seconds: 8));
    _require(
      messages == 1 && body != null && listEquals(body, expected),
      'Native RTC payload did not match',
    );
    receivedBytes = body!.length;
    final candidates = await _candidateBindings(peers);
    candidateCount = candidates.length;
    final current = await _ownedBindings();
    final fresh = current
        .where((row) => !baseline.contains(_key(row)))
        .toList();
    positiveDescriptors = await _ownedDescriptorCount();
    _require(
      positiveDescriptors >= baselineDescriptors + fresh.length,
      'Actual datagram descriptor count did not cover fresh bindings',
    );
    _require(
      fresh.isNotEmpty &&
          candidates.every(
            (candidate) => fresh.any(
              (row) =>
                  row['family'] == candidate['family'] &&
                  row['port'] == candidate['port'],
            ),
          ),
      'RTC candidate ports did not match actual own datagram descriptors',
    );
    addresses = [
      for (final row in fresh) {'address': row['address'], 'port': row['port']},
    ];
    held = await _nativeRows('udpBindProbe', {'bindings': addresses});
    _require(
      held.length == addresses.length &&
          held.every((row) => row['exclusiveBindSucceeded'] == false),
      'Actual own datagram bindings were not positively occupied',
    );
    for (var i = 0; i < held.length; i++) {
      _record('P8P_UDP_HELD', {'index': i, ...held[i]});
    }
  } catch (error) {
    failures.add('qualification:${error.runtimeType}:$error');
  } finally {
    final closing = Stopwatch()..start();
    retiring = true;
    for (final peer in peers) {
      peer.onDataChannel = null;
    }
    // Always drain the actual close operations. A late close is a failed
    // deadline, never a reason to abandon its owner or declare it released.
    for (final channel in List<RTCDataChannel>.of(channels)) {
      try {
        await channel.close();
      } catch (error) {
        failures.add('channel:${error.runtimeType}');
      }
    }
    for (final peer in peers) {
      try {
        await peer.close();
      } catch (error) {
        failures.add('close:${error.runtimeType}');
      }
      try {
        await peer.dispose();
      } catch (error) {
        failures.add('dispose:${error.runtimeType}');
      }
    }
    if (addresses.isNotEmpty) {
      do {
        released = await _nativeRows('udpBindProbe', {'bindings': addresses});
        finalOwned = (await _ownedBindings()).map(_key).toSet();
        finalDescriptors = await _ownedDescriptorCount();
        if (released.every((r) => r['exclusiveBindSucceeded'] == true) &&
            setEquals(finalOwned, baseline) &&
            finalDescriptors == baselineDescriptors) {
          break;
        }
        if (closing.elapsedMilliseconds >= 6000) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      } while (true);
    } else {
      finalOwned = (await _ownedBindings()).map(_key).toSet();
      finalDescriptors = await _ownedDescriptorCount();
    }
    closeMs = closing.elapsedMilliseconds;
    final owners = await _native.invokeMapMethod<String, int>('rtcOwners');
    if (owners == null || owners.values.any((v) => v != 0)) {
      failures.add('native_owners_remain');
    }
    wholeCloseMs = closing.elapsedMilliseconds;
    if (wholeCloseMs > 12000) failures.add('whole_close_exceeded_12_seconds');
    if (closeMs > 6000 ||
        !setEquals(finalOwned, baseline) ||
        finalDescriptors != baselineDescriptors ||
        released.length != held.length ||
        released.any((r) => r['exclusiveBindSucceeded'] != true)) {
      failures.add('physical_UDP_close_failed_or_late');
    }
    for (var i = 0; i < released.length; i++) {
      _record('P8P_UDP_RELEASED', {'index': i, ...released[i]});
    }
  }
  _require(
    failures.isEmpty && held.isNotEmpty,
    'UDP observer qualification failed: ${failures.join(';')}',
  );
  return {
    'passed': true,
    'RTC_payload_bytes': receivedBytes,
    'positive_UDP_bindings': held.length,
    'released_UDP_bindings': released.length,
    'RTC_candidate_bindings': candidateCount,
    'baseline_IP_datagrams': baseline.length,
    'final_IP_datagrams': finalOwned.length,
    'own_FD_inventory_returned_to_baseline': setEquals(finalOwned, baseline),
    'baseline_datagram_FDs': baselineDescriptors,
    'positive_datagram_FDs': positiveDescriptors,
    'final_datagram_FDs': finalDescriptors,
    'descriptor_count_returned_to_baseline':
        finalDescriptors == baselineDescriptors,
    'physical_close_ms': closeMs,
    'whole_close_ms': wholeCloseMs,
    'SDK_lifecycle_tested': false,
    'production_contacted': false,
  };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final status = ValueNotifier<String>('P8P UDP 观察器验证中');
  runApp(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: ValueListenableBuilder<String>(
          valueListenable: status,
          builder: (context, value, child) => SingleChildScrollView(
            child: Text(value),
          ),
        ),
      ),
    ),
  );
  try {
    final result = await _run();
    _record('P8P_UDP_PROBE_RESULT', result);
    status.value = _visibleEvidence('passed');
  } catch (error) {
    debugPrintSynchronously(
      'P8P_UDP_PROBE_FAILURE ${error.runtimeType}: $error',
    );
    status.value = _visibleEvidence('failed', error);
  }
}
