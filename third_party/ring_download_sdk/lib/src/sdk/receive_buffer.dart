import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../core/services/app_upgrade_receive_buffer.dart';
import 'models.dart';

/// One RTC receive owner. Signalling never awaits tuning. Closing fences new
/// calls and requests native closure before RTC teardown, with a fixed bound.
class RingRtcReceiveBufferOwner implements AppUpgradeReceiveBufferOwner {
  RingRtcReceiveBufferOwner({
    MethodChannel? channel,
    void Function(String)? onResult,
    void Function(RingDownloadDiagnostic)? onDiagnostic,
  }) : _channel = channel ?? const MethodChannel('ring_download_sdk/network'),
       _onResult = onResult,
       _onDiagnostic = onDiagnostic {
    _begin = _call<bool>('beginRtcReceiveBuffer', {'owner': _owner});
  }
  final MethodChannel _channel;
  final void Function(String)? _onResult;
  final void Function(RingDownloadDiagnostic)? _onDiagnostic;
  final _owner = const Uuid().v4().replaceAll('-', '');
  late final Future<bool?> _begin;
  final _seen = <String>{};
  final _pending = <Map<String, Object>>[];
  bool _closed = false, _busy = false;
  int _batches = 0;
  Timer? _scheduled;
  Future<void>? _closing;

  static Map<String, Object>? hostBinding(String? candidate) {
    if (candidate == null || candidate.length > 1024) return null;
    final parts = candidate.trim().split(RegExp(r'\s+'));
    if (parts.length < 8 ||
        parts.length > 32 ||
        !RegExp(r'^candidate:[a-zA-Z0-9+/]{1,32}$').hasMatch(parts[0]) ||
        parts[1] != '1' ||
        parts[2].toLowerCase() != 'udp' ||
        parts[6] != 'typ' ||
        parts[7] != 'host') {
      return null;
    }
    if (!RegExp(r'^[0-9]{1,10}$').hasMatch(parts[3]) ||
        int.parse(parts[3]) < 1 ||
        int.parse(parts[3]) > 0xffffffff ||
        !RegExp(r'^[0-9]{1,5}$').hasMatch(parts[5])) {
      return null;
    }
    final address = InternetAddress.tryParse(parts[4]);
    final port = int.tryParse(parts[5]);
    if (address == null ||
        address.isLoopback ||
        address.isLinkLocal ||
        address.isMulticast ||
        address.address == '0.0.0.0' ||
        address.address == '::' ||
        address.address.startsWith('::ffff:') ||
        parts[4].contains('%') ||
        port == null ||
        port < 1 ||
        port > 65535) {
      return null;
    }
    return {
      'address': address.address,
      'port': port,
      'family': address.type == InternetAddressType.IPv4 ? 4 : 6,
    };
  }

  Future<T?> _call<T>(String method, Map<String, Object> arguments) async {
    try {
      return await _channel
          .invokeMethod<T>(method, arguments)
          .timeout(const Duration(milliseconds: 250));
    } catch (_) {
      return null;
    }
  }

  @override
  void addCandidate(String? candidate) {
    if (_closed || _batches >= 2) return;
    final binding = hostBinding(candidate);
    if (binding == null) return;
    final key = '${binding['family']}:${binding['port']}';
    if (_seen.length >= 8 || !_seen.add(key)) return;
    _pending.add({'address': binding['address']!, 'port': binding['port']!});
    _schedule();
  }

  void _schedule() {
    _scheduled ??= Timer(Duration.zero, () {
      unawaited(_flush());
    });
  }

  Future<void> _flush() async {
    _scheduled = null;
    if (_closed || _busy || _pending.isEmpty || _batches >= 2) return;
    _busy = true;
    try {
      final available = await _begin;
      if (_closed || available != true) {
        _pending.clear();
        return;
      }
      final bindings = List<Map<String, Object>>.of(_pending);
      _pending.clear();
      _batches++;
      final result = await _call<Object?>('tuneRtcReceiveBuffer', {
        'owner': _owner,
        'bindings': bindings,
        'expiresAt': DateTime.now().millisecondsSinceEpoch + 250,
      });
      const codes = {
        'adjusted',
        'unchanged',
        'unavailable',
        'expired',
        'scan_limit',
        'ambiguous',
        'unmatched',
        'partial',
      };
      final observation = result is Map && codes.contains(result['code'])
          ? result
          : const <Object?, Object?>{};
      final code = observation['code'] as String? ?? 'unavailable';
      if (!_closed) {
        try {
          _onResult?.call('receive_buffer_$code');
        } catch (_) {}
        if (_closed) return;
        final matched = observation['matched'];
        final bytes = observation['minBufferBytes'];
        final matchedSockets = matched is int && matched >= 0 && matched <= 8
            ? matched
            : null;
        final minimumBytes =
            matchedSockets != null &&
                matchedSockets > 0 &&
                bytes is int &&
                bytes > 0 &&
                bytes <= 64 * 1024 * 1024
            ? bytes
            : null;
        try {
          _onDiagnostic?.call(
            RingDownloadDiagnostic(
              stage: 'rtc',
              code: 'receive_buffer_$code',
              matchedReceiveSockets: matchedSockets,
              minReceiveBufferBytes: minimumBytes,
            ),
          );
        } catch (_) {}
      }
    } finally {
      _busy = false;
      if (!_closed && _pending.isNotEmpty && _batches < 2) _schedule();
    }
  }

  @override
  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    _scheduled?.cancel();
    _scheduled = null;
    _pending.clear();
    return _closing = () async {
      // begin and close use one serial platform actor. Even a late begin reply
      // cannot reopen a retired owner; a queued tune after close finds no owner.
      await _call<bool>('closeRtcReceiveBuffer', {'owner': _owner});
    }();
  }
}
