import 'dart:async';
import 'dart:typed_data';

import '../core/services/app_upgrade_p2p_protocol.dart';
import 'diagnostics.dart';
import 'leases.dart';
import 'ordered_writer.dart';
import 'transfer_protocol.dart';

class P8PTransferTicket {
  P8PTransferTicket._(this.lease) {
    unawaited(_verified.future.then<void>((_) {}, onError: (Object _) {}));
    unawaited(_stopped.future.then<void>((_) {}, onError: (Object _) {}));
  }
  final P8PLease lease;
  final _verified = Completer<void>();
  final _stopped = Completer<void>();
  Future<void> get verified => _verified.future;
  Future<void> get stopped => _stopped.future;
  Uint8List? _buffer;
  int _received = 0;
  int get receivedBytes => _received;
  bool _cancelled = false;
}

/// B-stage source adapter core; the RTC owner supplies ordered sends and an
/// awaited transport shutdown. The existing v1 download path does not use it.
class P8PTransferReceiver {
  P8PTransferReceiver({
    required this.source,
    required this.writer,
    required this.send,
    required this.closeTransport,
    this.onDiagnostic,
  }) {
    if (!P8PTransferProtocol.wireId(book.generation)) {
      throw ArgumentError('P8P generation outside wire bounds');
    }
    unawaited(_ready.future.then<void>((_) {}, onError: (Object _) {}));
  }
  final String source;
  final P8POrderedWriter writer;
  final Future<void> Function(Map<String, Object?>) send;
  final Future<void> Function() closeTransport;
  final P8PDiagnosticObserver? onDiagnostic;
  bool _failureObserved = false;
  P8PLeaseBook get book => writer.book;
  final _pending = <int, P8PTransferTicket>{};
  final _ready = Completer<void>();
  Future<void>? _connecting, _closing;
  bool _closed = false;
  int _lastIssued = 0;
  int _sourceCapacity = 2;
  int get sourceCapacity => _sourceCapacity;
  int get pending => _pending.length;
  int get bufferedBytes => _pending.values.fold(
    0,
    (sum, ticket) => sum + (ticket._buffer?.length ?? 0),
  );
  bool get closed => _closed;

  Map<String, Object?> _control(
    String type, [
    Map<String, Object?> fields = const {},
  ]) => {'type': type, 'version': 1, 'generation': book.generation, ...fields};

  Future<void> connect(Duration timeout) => _connecting ??= _connect(timeout);

  Future<void> _connect(Duration timeout) async {
    if (_closed) throw StateError('p8p_source_closed');
    try {
      await send(
        _control('hello', {
          'sha256': book.fileSha256,
          'source_capacity_supported': true,
        }),
      );
      await _ready.future.timeout(timeout);
    } catch (error) {
      await close(error);
      rethrow;
    }
  }

  P8PTransferTicket request(P8PLease lease) {
    if (_closed ||
        !_ready.isCompleted ||
        !book.accepts(lease) ||
        lease.source != source ||
        !P8PTransferProtocol.wireId(lease.id) ||
        lease.id <= _lastIssued ||
        _pending.length >= P8PTransferProtocol.maxInflight) {
      throw StateError('p8p_invalid_source_request');
    }
    final ticket = P8PTransferTicket._(lease);
    _pending[lease.id] = ticket;
    _lastIssued = lease.id;
    _send(_control('get', {'request_id': lease.id, 'index': lease.index}));
    return ticket;
  }

  void cancel(P8PTransferTicket ticket) {
    if (_closed ||
        !identical(_pending[ticket.lease.id], ticket) ||
        ticket._cancelled) {
      return;
    }
    book.cancel(ticket.lease);
    ticket._cancelled = true;
    ticket._buffer = null;
    _send(_control('cancel', {'request_id': ticket.lease.id}));
  }

  void acceptControl(String raw) {
    if (_closed) return;
    P8PTransferTicket? activeTicket;
    try {
      final value = P8PTransferProtocol.control(raw);
      if (value['generation'] != book.generation) return;
      if (value['type'] == 'hello') {
        if (value['sha256'] != book.fileSha256 ||
            value['max_inflight'] is! int ||
            value['max_inflight'] != 4) {
          throw const FormatException('p8p_identity_mismatch');
        }
        final advised = value['source_capacity'];
        if (advised != null) {
          if (advised is! int || advised < 1 || advised > 2) {
            throw const FormatException('p8p_invalid_source_capacity');
          }
          _sourceCapacity = advised;
        }
        if (!_ready.isCompleted) _ready.complete();
        return;
      }
      if (!_ready.isCompleted ||
          !P8PTransferProtocol.wireId(value['request_id'])) {
        throw const FormatException('p8p_invalid_control');
      }
      final identity = value['request_id'] as int;
      final ticket = _pending[identity];
      activeTicket = ticket;
      if (ticket == null) {
        if (identity > _lastIssued) {
          throw const FormatException('p8p_unknown_request');
        }
        return;
      }
      if (value['type'] == 'cancelled') {
        if (!ticket._cancelled) {
          throw const FormatException('p8p_unrequested_cancel');
        }
        _terminal(ticket, P8PLeaseCancelled());
        return;
      }
      if (value['type'] == 'error') {
        _terminal(
          ticket,
          StateError(
            value['code'] == 'busy' ? 'p8p_source_busy' : 'p8p_source_failed',
          ),
        );
        return;
      }
      if (ticket._cancelled) return;
      if (!book.accepts(ticket.lease)) {
        cancel(ticket);
        return;
      }
      if (value['index'] is! int || value['index'] != ticket.lease.index) {
        throw const FormatException('p8p_piece_identity_mismatch');
      }
      if (value['type'] == 'piece-start') {
        if (ticket._buffer != null ||
            value['size'] is! int ||
            value['size'] != ticket.lease.bytes) {
          throw const FormatException('p8p_invalid_piece_size');
        }
        ticket._buffer = Uint8List(ticket.lease.bytes);
      } else if (value['type'] == 'piece-end') {
        if (ticket._buffer == null || ticket._received != ticket.lease.bytes) {
          throw const FormatException('p8p_piece_length_mismatch');
        }
        if (!writer.submit(ticket.lease, ticket._buffer!)) {
          cancel(ticket);
          return;
        }
        ticket._buffer = null;
        _pending.remove(identity);
        ticket._verified.complete();
        ticket._stopped.complete();
      } else {
        throw const FormatException('p8p_invalid_control');
      }
    } catch (error) {
      _fail(error, activeTicket);
    }
  }

  void acceptBinary(Uint8List raw) {
    if (_closed) return;
    P8PTransferTicket? activeTicket;
    try {
      final frame = P8PTransferProtocol.frame(raw);
      if (frame.generation != book.generation) return;
      final ticket = _pending[frame.identity];
      activeTicket = ticket;
      if (ticket == null) {
        if (frame.identity > _lastIssued) {
          throw const FormatException('p8p_unknown_request');
        }
        return;
      }
      if (ticket._cancelled) return;
      if (!book.accepts(ticket.lease)) {
        cancel(ticket);
        return;
      }
      if (ticket._buffer == null ||
          frame.offset != ticket._received ||
          ticket._received + frame.body.length > ticket.lease.bytes) {
        throw const FormatException('p8p_invalid_piece_frame');
      }
      ticket._buffer!.setRange(
        ticket._received,
        ticket._received + frame.body.length,
        frame.body,
      );
      ticket._received += frame.body.length;
    } catch (error) {
      _fail(error, activeTicket);
    }
  }

  void _terminal(P8PTransferTicket ticket, Object error) {
    if (error is! P8PLeaseCancelled) _observeFailure(error, ticket);
    _pending.remove(ticket.lease.id);
    ticket._buffer = null;
    book.cancel(ticket.lease);
    book.acknowledgeStopped(ticket.lease);
    if (!ticket._verified.isCompleted) ticket._verified.completeError(error);
    ticket._stopped.complete();
  }

  void _send(Map<String, Object?> value) {
    unawaited(
      Future<void>.sync(() => send(value)).catchError((Object error) {
        _fail(error, _pending[value['request_id']]);
      }),
    );
  }

  void _fail(Object error, [P8PTransferTicket? ticket]) =>
      unawaited(close(error, ticket).catchError((Object _) {}));

  Future<void> close([Object? error, P8PTransferTicket? ticket]) {
    if (_closing != null) return _closing!;
    final done = Completer<void>();
    _closing = done.future;
    _closed = true;
    if (error != null) _observeFailure(error, ticket);
    unawaited(
      _close(
        error ?? StateError('p8p_source_closed'),
      ).then(done.complete, onError: done.completeError),
    );
    return done.future;
  }

  void _observeFailure(Object error, P8PTransferTicket? ticket) {
    if (_failureObserved) return;
    _failureObserved = true;
    final reason = switch (error) {
      AppUpgradeP2PFailure(code: 'piece_checksum_mismatch') =>
        P8PDiagnosticCode.checksumMismatch,
      TimeoutException() => P8PDiagnosticCode.sourceTimeout,
      FormatException(message: 'p8p_piece_length_mismatch') =>
        P8PDiagnosticCode.lengthMismatch,
      FormatException(message: 'p8p_invalid_piece_frame') =>
        P8PDiagnosticCode.invalidFrame,
      FormatException(message: 'p8p_invalid_piece_size') =>
        P8PDiagnosticCode.invalidSize,
      FormatException(message: 'p8p_piece_identity_mismatch') =>
        P8PDiagnosticCode.identityMismatch,
      StateError(message: 'p8p_source_busy') => P8PDiagnosticCode.sourceBusy,
      StateError(message: 'p8p_source_failed') =>
        P8PDiagnosticCode.sourceFailed,
      _ => P8PDiagnosticCode.protocolError,
    };
    observeP8P(
      onDiagnostic,
      P8PSourceDiagnostic(
        reason,
        actualBytes: ticket?.receivedBytes,
        expectedBytes: ticket?.lease.bytes,
      ),
    );
  }

  Future<void> _close(Object error) async {
    if (!_ready.isCompleted) _ready.completeError(error);
    final pending = _pending.values.toList();
    for (final ticket in pending) {
      book.cancel(ticket.lease);
      ticket._buffer = null;
      if (!ticket._verified.isCompleted) ticket._verified.completeError(error);
    }
    try {
      await closeTransport();
    } catch (failure, stack) {
      observeP8P(
        onDiagnostic,
        P8PSourceDiagnostic(P8PDiagnosticCode.cleanupFailed),
      );
      // Failed physical cleanup does not grant capacity to another request.
      for (final ticket in pending) {
        ticket._stopped.completeError(failure, stack);
      }
      rethrow;
    }
    for (final ticket in pending) {
      book.acknowledgeStopped(ticket.lease);
      ticket._stopped.complete();
    }
    _pending.clear();
  }
}
