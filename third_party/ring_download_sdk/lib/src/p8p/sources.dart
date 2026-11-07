import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'leases.dart';
import 'ordered_writer.dart';
import 'transfer_receiver.dart';

typedef P8PRangeReader =
    Future<Uint8List> Function(int index, CancelToken token);
typedef P8PProgressRangeReader =
    Future<Uint8List> Function(
      int index,
      CancelToken token,
      void Function(int) receivedBytes,
    );

/// A validated admission rejection produced no piece body. Release the piece
/// after physical stop, and keep this source unavailable until Retry-After.
/// This carries no permission to retry quotas, foreign sessions or bad data.
class P8PSourceDeferred implements Exception {
  P8PSourceDeferred(this.retryAfter) {
    if (retryAfter <= Duration.zero ||
        retryAfter > const Duration(seconds: 5)) {
      throw ArgumentError.value(retryAfter, 'retryAfter');
    }
  }
  final Duration retryAfter;
}

class P8PSourceRequest {
  const P8PSourceRequest(
    this.lease,
    this.verified,
    this.stopped,
    this.cancel, {
    int Function()? receivedBytes,
  }) : _receivedBytes = receivedBytes;
  final P8PLease lease;
  final Future<void> verified, stopped;
  final void Function() cancel;
  final int Function()? _receivedBytes;

  /// Contiguous received bytes are liveness only, never verified goodput or
  /// authorization to persist. The lease deadline remains the hard bound.
  int get receivedBytes => _receivedBytes?.call() ?? 0;
}

abstract interface class P8PPieceSource {
  String get id;
  int get capacity;
  bool get closed;
  bool canServe(int index);
  P8PSourceRequest start(P8PLease lease);
  Future<void> close();
}

class P8PRtcPieceSource implements P8PPieceSource {
  P8PRtcPieceSource(this.receiver, {Set<int>? pieces}) : _pieces = pieces;
  final P8PTransferReceiver receiver;
  final Set<int>? _pieces;
  @override
  String get id => receiver.source;
  @override
  int get capacity => receiver.sourceCapacity;
  @override
  bool get closed => receiver.closed;
  @override
  bool canServe(int index) =>
      !closed && (_pieces == null || _pieces.contains(index));
  @override
  P8PSourceRequest start(P8PLease lease) {
    final ticket = receiver.request(lease);
    return P8PSourceRequest(
      lease,
      ticket.verified,
      ticket.stopped,
      () => receiver.cancel(ticket),
      receivedBytes: () => ticket.receivedBytes,
    );
  }

  @override
  Future<void> close() => receiver.close();
}

/// The HTTP owner supplies the existing redirect/header/range policy. This
/// adapter owns only one bounded piece per reservation, its cancellation and
/// verified handoff. External direct downloads never instantiate it.
class P8PHttpPieceSource implements P8PPieceSource {
  P8PHttpPieceSource(
    this.writer,
    this.read, {
    this.id = 'https',
    this.readWithProgress,
  });
  final P8POrderedWriter writer;
  final P8PRangeReader read;
  final P8PProgressRangeReader? readWithProgress;
  @override
  final String id;
  final _active = <int, P8PSourceRequest>{};
  bool _closed = false;
  Future<void>? _closing;
  @override
  int get capacity => 2;
  @override
  bool get closed => _closed;
  @override
  bool canServe(int index) => !_closed && writer.book.sizeOf(index) > 0;

  @override
  P8PSourceRequest start(P8PLease lease) {
    if (_closed ||
        lease.source != id ||
        !writer.book.accepts(lease) ||
        _active.length >= capacity) {
      throw StateError('p8p_invalid_http_request');
    }
    final token = CancelToken();
    var received = 0;
    final verified = Completer<void>(), stopped = Completer<void>();
    unawaited(verified.future.then<void>((_) {}, onError: (Object _) {}));
    final job = P8PSourceRequest(lease, verified.future, stopped.future, () {
      writer.book.cancel(lease);
      token.cancel('p8p_request_cancelled');
    }, receivedBytes: () => received);
    _active[lease.id] = job;
    unawaited(() async {
      try {
        final progressReader = readWithProgress;
        final bytes = progressReader == null
            ? await read(lease.index, token)
            : await progressReader(lease.index, token, (count) {
                if (count > received && count <= lease.bytes) {
                  received = count;
                }
              });
        if (token.isCancelled || _closed || !writer.submit(lease, bytes)) {
          throw P8PLeaseCancelled();
        }
        verified.complete();
      } catch (error, stack) {
        if (error is P8PSourceDeferred) {
          if (received != 0 || !writer.book.rejectAdmission(lease)) {
            writer.book.cancel(lease);
            verified.completeError(
              StateError('p8p_invalid_admission_rejection'),
              stack,
            );
          } else {
            verified.completeError(error, stack);
          }
        } else {
          writer.book.cancel(lease);
          verified.completeError(error, stack);
        }
      } finally {
        token.cancel('p8p_http_finished');
        writer.book.acknowledgeStopped(lease);
        _active.remove(lease.id);
        stopped.complete();
      }
    }());
    return job;
  }

  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    final jobs = _active.values.toList();
    for (final job in jobs) {
      job.cancel();
    }
    await Future.wait(jobs.map((job) => job.stopped));
  }
}
