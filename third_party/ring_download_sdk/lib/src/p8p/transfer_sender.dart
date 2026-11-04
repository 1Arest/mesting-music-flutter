import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'transfer_protocol.dart';

/// The RTC owner supplies an ordered reliable channel and an awaited send which
/// rechecks [active] after any native-queue/rate wait, immediately before enqueue.
/// Only one piece is read at a time; queued leases retain identifiers, not bodies.
class P8PTransferSender {
  P8PTransferSender({
    required this.sha256,
    required this.fileBytes,
    required this.readPiece,
    required this.sendControl,
    required this.sendBinary,
    required this.allowed,
    required this.onFailure,
    this.onPayloadQueued,
    this.onPieceCompleted,
    this.sourceCapacity = 1,
    this.requireCapacitySupport = false,
    this.onCapacityRejected,
  }) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256) ||
        fileBytes <= 0 ||
        sourceCapacity < 1 ||
        sourceCapacity > 2) {
      throw ArgumentError('invalid_sender_identity');
    }
  }
  final String sha256;
  final int fileBytes, sourceCapacity;
  final bool requireCapacitySupport;
  final void Function()? onCapacityRejected;
  final Future<Uint8List> Function(int index) readPiece;
  final Future<void> Function(Map<String, Object?> value) sendControl;
  final Future<void> Function(Uint8List bytes, bool Function() active)
  sendBinary;
  final bool Function() allowed;
  final void Function() onFailure;
  final void Function(int bytes)? onPayloadQueued;
  final void Function()? onPieceCompleted;
  final _queue = Queue<_Upload>();
  final _pending = <int, _Upload>{};
  final _controlFlights = <Future<void>>{};
  _Upload? _current;
  Future<void>? _pump, _hello, _closing;
  int? _generation;
  int _lastIssued = 0;
  bool _closed = false;
  bool _rejecting = false;
  bool get closed => _closed;
  int get pending => _pending.length;
  bool get _open => !_closed && allowed();
  int get _pieceCount => (fileBytes + 1048575) ~/ 1048576;

  Map<String, Object?> _control(
    String type, [
    Map<String, Object?> fields = const {},
  ]) => {'type': type, 'version': 1, 'generation': _generation, ...fields};
  Future<void> _write(String type, [Map<String, Object?> fields = const {}]) {
    if (!_open) return Future.value();
    final settled = Completer<void>();
    final owned = settled.future;
    _controlFlights.add(owned);
    unawaited(() async {
      try {
        await sendControl(_control(type, fields));
        settled.complete();
      } catch (error, stack) {
        settled.completeError(error, stack);
      } finally {
        _controlFlights.remove(owned);
      }
    }());
    return owned;
  }

  void _writeLater(String type, Map<String, Object?> fields) {
    unawaited(
      _write(type, fields).catchError((Object _) {
        _abort();
      }),
    );
  }

  void acceptControl(String raw) {
    if (!_open || _rejecting) return;
    try {
      final value = P8PTransferProtocol.request(raw, _pieceCount);
      if (value['type'] == 'hello') {
        if (value['sha256'] != sha256 ||
            (_generation != null && _generation != value['generation'])) {
          throw const FormatException('sender_identity_mismatch');
        }
        _generation = value['generation'] as int;
        if (requireCapacitySupport &&
            value['source_capacity_supported'] != true) {
          // A paced phone cannot fit two queued MiB pieces plus overhead into
          // the established 8-second request deadline. Decline before any disk
          // read/body so old receivers can use their existing source fallback.
          _rejecting = true;
          onCapacityRejected?.call();
          _hello = _write('error', {
            'code': 'source_capacity_required',
          }).whenComplete(_abort);
          unawaited(_hello!.catchError((Object _) {}));
          return;
        }
        final previous = _hello ?? Future<void>.value();
        _hello = previous.then(
          (_) => _write('hello', {
            'sha256': sha256, 'max_inflight': P8PTransferProtocol.maxInflight,
            // Optional advice; wire admission remains the established bound4.
            'source_capacity': sourceCapacity,
          }),
        );
        unawaited(
          _hello!.catchError((Object _) {
            _abort();
          }),
        );
        return;
      }
      if (_generation == null || value['generation'] != _generation) {
        throw const FormatException('sender_generation_mismatch');
      }
      final identity = value['request_id'] as int;
      if (value['type'] == 'cancel') {
        final upload = _pending[identity];
        if (upload == null) {
          if (identity > _lastIssued) {
            throw const FormatException('sender_unknown_request');
          }
          _writeLater('cancelled', {'request_id': identity});
        } else if (!identical(upload, _current)) {
          _queue.remove(upload);
          _pending.remove(identity);
          _writeLater('cancelled', {'request_id': identity});
        } else {
          upload.cancelled = true;
        }
        return;
      }
      if (identity <= _lastIssued) {
        throw const FormatException('sender_reused_request');
      }
      _lastIssued = identity;
      final index = value['index'] as int;
      if (_pending.length >= P8PTransferProtocol.maxInflight ||
          _pending.values.any((u) => u.index == index)) {
        _writeLater('error', {'request_id': identity, 'code': 'busy'});
        return;
      }
      final upload = _Upload(identity, index);
      _pending[identity] = upload;
      _queue.add(upload);
      _startPump();
    } catch (_) {
      _abort();
    }
  }

  void _startPump() {
    if (_pump != null || !_open || _queue.isEmpty) return;
    final settled = Completer<void>();
    _pump = settled.future;
    unawaited(() async {
      try {
        await _run();
      } catch (_) {
        _abort();
      } finally {
        _pump = null;
        settled.complete();
        if (_open && _queue.isNotEmpty) _startPump();
      }
    }());
  }

  Future<void> _run() async {
    await _hello;
    while (_open && _queue.isNotEmpty) {
      final upload = _current = _queue.removeFirst();
      Uint8List? payload;
      try {
        if (!upload.cancelled) payload = await readPiece(upload.index);
        if (!_open) return;
        if (!upload.cancelled) {
          final expected = (fileBytes - upload.index * 1048576).clamp(
            0,
            1048576,
          );
          if (payload == null || payload.length != expected) {
            throw StateError('sender_piece_changed');
          }
          await _write('piece-start', {
            'request_id': upload.id,
            'index': upload.index,
            'size': expected,
          });
          const frameBody =
              P8PTransferProtocol.maxFrameBytes -
              P8PTransferProtocol.headerBytes;
          for (var offset = 0; offset < payload.length; offset += frameBody) {
            if (!_open || upload.cancelled) break;
            final end = (offset + frameBody).clamp(0, payload.length);
            final frame = P8PTransferProtocol.encode(
              _generation!,
              upload.id,
              offset,
              Uint8List.sublistView(payload, offset, end),
            );
            await sendBinary(frame, () => _open && !upload.cancelled);
            onPayloadQueued?.call(end - offset);
          }
          if (_open && !upload.cancelled) {
            await _write('piece-end', {
              'request_id': upload.id,
              'index': upload.index,
            });
            onPieceCompleted?.call();
          }
        }
      } catch (_) {
        // Cancellation of an owner-held pacing wait is not a protocol failure.
        if (!upload.cancelled && _open) rethrow;
      } finally {
        payload = null;
        _pending.remove(upload.id);
        _current = null;
        if (upload.cancelled) {
          await _write('cancelled', {'request_id': upload.id});
        }
      }
    }
  }

  void _abort() {
    if (_closed) return;
    unawaited(close());
    onFailure();
  }

  Future<void> close() => _closing ??= () async {
    _closed = true;
    _queue.clear();
    await _pump;
    try {
      await _hello;
    } catch (_) {}
    await Future.wait(
      _controlFlights.map((f) => f.catchError((Object _) {})).toList(),
    );
    _pending.clear();
  }();
}

class _Upload {
  _Upload(this.id, this.index);
  final int id, index;
  bool cancelled = false;
}
