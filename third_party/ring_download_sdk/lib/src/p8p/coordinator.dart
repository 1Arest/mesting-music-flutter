import 'dart:async';
import 'dart:math';

import 'diagnostics.dart';
import 'leases.dart';
import 'ordered_writer.dart';
import 'source_goodput.dart';
import 'sources.dart';

class _SourceState {
  _SourceState(this.source, this.diagnosticAlias);
  final P8PPieceSource source;
  final String? diagnosticAlias;
  int diagnosticRequests = 0, diagnosticVerifiedBytes = 0;
  int diagnosticCancelled = 0, diagnosticFailures = 0, diagnosticBusyMicros = 0;
  int? diagnosticBusySince;
  final goodput = P8PSourceGoodput();
  double? get bytesPerMicrosecond => goodput.bytesPerMicrosecond;
  int get lastSample => goodput.lastSampleMicros ?? 0;
  int get samples => goodput.samples;
  bool failed = false;
  bool closingRequested = false;
  int availableAfterMicros = 0;
  final jobs = <int, _Job>{};
  final diagnosticEvents = <P8PDiagnosticCode>{};
}

class _Job {
  _Job(this.request, this.source)
    : lastProgressMicros = request.lease.startedMicros;
  final P8PSourceRequest request;
  final _SourceState source;
  bool cancelled = false, verified = false;
  int? cancelAt;
  int receivedBytes = 0, lastProgressMicros;
}

/// Fine scheduling runs locally. At most four reservations include verified
/// ready buffers and requests still cancelling. Lookahead never skips the
/// current prefix's reservation, so out-of-order arrivals cannot starve it.
class P8PCoordinator {
  P8PCoordinator(
    this.writer, {
    required this.clockMicros,
    this.requestTimeout = const Duration(seconds: 8),
    this.hedgeAfter = const Duration(seconds: 1),
    this.stopGrace = const Duration(seconds: 1),
    this.onDiagnostic,
  });
  final P8POrderedWriter writer;
  final int Function() clockMicros;
  final Duration requestTimeout, hedgeAfter, stopGrace;
  final P8PDiagnosticObserver? onDiagnostic;
  P8PLeaseBook get book => writer.book;
  final _sources = <String, _SourceState>{};
  final _jobs = <int, _Job>{};
  final _cleanup = <Future<void>>[];
  Completer<void>? _wake;
  bool _closed = false;
  Future<void>? _closing;
  final _metrics = <String, int>{};
  // Only four fixed local aliases are exported; opaque source/session IDs
  // never become metric keys. Reading this snapshot cannot change scheduling,
  // goodput samples, ownership, clocks or source availability.
  Map<String, int> get metrics => Map.unmodifiable({
    ..._metrics,
    for (final state in _sources.values)
      if (state.diagnosticAlias case final String alias) ...{
        'source_${alias}_requests': state.diagnosticRequests,
        'source_${alias}_verified_bytes': state.diagnosticVerifiedBytes,
        'source_${alias}_busy_us': state.diagnosticBusyMicros,
        'source_${alias}_cancelled': state.diagnosticCancelled,
        'source_${alias}_failures': state.diagnosticFailures,
      },
  });
  void _count(String key, [int value = 1]) =>
      _metrics.update(key, (old) => old + value, ifAbsent: () => value);
  void _notify() {
    if (_wake?.isCompleted == false) _wake!.complete();
  }

  void _observe(_SourceState state, P8PDiagnosticCode reason, [_Job? job]) {
    // At most one of each fixed event per source for this coordinator.
    if (!state.diagnosticEvents.add(reason)) return;
    observeP8P(
      onDiagnostic,
      P8PSourceDiagnostic(
        reason,
        alias: state.diagnosticAlias,
        actualBytes: job?.request.receivedBytes,
        expectedBytes: job?.request.lease.bytes,
      ),
    );
  }

  P8PDiagnosticCode _cancelReason(_Job job) =>
      clockMicros() >= job.request.lease.deadlineMicros
      ? P8PDiagnosticCode.requestDeadlineExceeded
      : P8PDiagnosticCode.requestCancelled;

  bool add(P8PPieceSource source, {String? diagnosticAlias}) {
    if (_closed ||
        source.closed ||
        _sources.containsKey(source.id) ||
        _sources.length >= 4) {
      return false;
    }
    final alias =
        const {'peer1', 'peer2', 'seed', 'https'}.contains(diagnosticAlias) &&
            !_sources.values.any(
              (state) => state.diagnosticAlias == diagnosticAlias,
            )
        ? diagnosticAlias
        : null;
    _sources[source.id] = _SourceState(source, alias);
    _notify();
    return true;
  }

  int _queuedBytes(_SourceState state) => state.jobs.values.fold(0, (sum, job) {
    // Progress discounts pending transfer work, not slot ownership or the
    // verified-goodput sample. A cancelling owner stays conservatively full
    // until it physically stops; invalid progress never reaches this counter.
    final remaining = job.cancelled
        ? job.request.lease.bytes
        : job.verified
        ? 0
        : job.request.lease.bytes - job.receivedBytes;
    return sum + remaining;
  });

  _SourceState? _choose(int index, {String? excluding}) {
    final candidates = _sources.values
        .where(
          (state) =>
              !state.failed &&
              clockMicros() >= state.availableAfterMicros &&
              state.source.id != excluding &&
              state.source.canServe(index),
        )
        .toList();
    double estimate(_SourceState state) {
      if (state.samples == 0 ||
          clockMicros() - state.lastSample > P8PSourceGoodput.sampleTtlMicros) {
        return state.jobs.isEmpty ? -1 : double.infinity;
      }
      final queued = _queuedBytes(state);
      return (queued + book.sizeOf(index)) / state.bytesPerMicrosecond!;
    }

    candidates.sort((a, b) => estimate(a).compareTo(estimate(b)));
    if (candidates.isEmpty) return null;
    final best = candidates.first;
    // Wait for a proven fast source rather than filling every free slot with
    // a slower source. Cold origins get one finite probe, not a full queue.
    final capacity = best.samples == 0 ? 1 : best.source.capacity;
    return best.jobs.length >= capacity ? null : best;
  }

  /// Startup probes share the same ownership, deadlines and physical-stop
  /// accounting as steady requests. A caller must poll while awaiting proof.
  P8PSourceRequest? probe(int index, String source) {
    final state = _sources[source];
    if (_closed ||
        state == null ||
        state.failed ||
        clockMicros() < state.availableAfterMicros ||
        state.samples > 0 ||
        state.jobs.isNotEmpty ||
        !state.source.canServe(index) ||
        index < book.persistedPieces ||
        index >= book.persistedPieces + 4 ||
        book.phase(index) != P8PPiecePhase.missing) {
      return null;
    }
    return _start(index, state);
  }

  P8PSourceRequest? _start(
    int index,
    _SourceState state, {
    bool hedge = false,
  }) {
    final lease = book.request(
      index,
      state.source.id,
      timeout: requestTimeout,
      hedge: hedge,
      hedgeAfter: hedgeAfter,
    );
    if (lease == null) return null;
    try {
      final request = state.source.start(lease);
      state.goodput.started(lease.startedMicros);
      if (state.jobs.isEmpty) state.diagnosticBusySince = lease.startedMicros;
      state.diagnosticRequests++;
      final job = _Job(request, state);
      _jobs[lease.id] = job;
      state.jobs[lease.id] = job;
      _count('requests');
      if (hedge) _count('hedges');
      unawaited(
        request.verified.then<void>(
          (_) {
            job.verified = true;
            state.goodput.verified(lease.bytes, clockMicros());
            state.diagnosticVerifiedBytes += lease.bytes;
            _count('verified_bytes', lease.bytes);
            _notify();
          },
          onError: (Object error) {
            if (!job.cancelled && !_closed) {
              if (error is P8PLeaseCancelled) {
                // An adapter can observe ledger expiry and receive its cancel
                // acknowledgement between polls. Preserve that provenance;
                // an ordinary error with the same text is still a fault.
                // The adapter's stopped future retains physical ownership.
                state.diagnosticCancelled++;
                job.cancelled = true;
                job.cancelAt = clockMicros();
                _observe(state, _cancelReason(job), job);
              } else if (error is P8PSourceDeferred) {
                state.availableAfterMicros = max(
                  state.availableAfterMicros,
                  clockMicros() + error.retryAfter.inMicroseconds,
                );
                _count('source_deferred');
              } else {
                _count('source_failures');
                state.diagnosticFailures++;
                state.failed = true;
                _closeSource(state, P8PDiagnosticCode.sourceFailed, job);
              }
            }
            _notify();
          },
        ),
      );
      unawaited(
        request.stopped.then<void>(
          (_) {
            final stoppedAt = clockMicros();
            state.goodput.stopped(stoppedAt);
            _jobs.remove(lease.id);
            state.jobs.remove(lease.id);
            if (state.jobs.isEmpty && state.diagnosticBusySince != null) {
              state.diagnosticBusyMicros += max(
                0,
                stoppedAt - state.diagnosticBusySince!,
              );
              state.diagnosticBusySince = null;
            }
            _notify();
          },
          onError: (Object error) {
            state.diagnosticFailures++;
            state.failed = true;
            _count('cleanup_failures');
            _observe(state, P8PDiagnosticCode.cleanupFailed, job);
            _notify();
          },
        ),
      );
      return request;
    } catch (_) {
      _observe(state, P8PDiagnosticCode.sourceFailed);
      state.diagnosticFailures++;
      state.failed = true;
      book.cancel(lease);
      // The source may have started a native operation before throwing. Its
      // close must finish before that reservation is acknowledged stopped.
      final stopped = state.source.close().then((_) {
        book.acknowledgeStopped(lease);
      });
      _cleanup.add(stopped);
      unawaited(stopped.catchError((Object _) {}));
      return null;
    }
  }

  void _closeSource(
    _SourceState state,
    P8PDiagnosticCode reason, [
    _Job? cause,
  ]) {
    if (state.closingRequested) return;
    state.closingRequested = true;
    state.failed = true;
    _observe(state, reason, cause);
    for (final job in state.jobs.values) {
      if (!job.cancelled && !job.verified) state.diagnosticCancelled++;
      job.cancelled = true;
      job.request.cancel();
    }
    final closing = state.source.close();
    _cleanup.add(closing);
    unawaited(closing.catchError((Object _) {}));
  }

  /// Also used while the writer is paused and independent HTTPS owns startup.
  void poll() {
    if (_closed) return;
    book.expire();
    final now = clockMicros();
    for (final job in _jobs.values) {
      if (job.cancelled || job.verified) continue;
      final received = job.request.receivedBytes;
      if (received > job.receivedBytes && received <= job.request.lease.bytes) {
        job.receivedBytes = received;
        job.lastProgressMicros = now;
      }
    }
    for (final lease in book.cancellations) {
      final job = _jobs[lease.id];
      if (job == null) continue;
      if (!job.cancelled) {
        job.source.diagnosticCancelled++;
        job.cancelled = true;
        job.cancelAt = clockMicros();
        _observe(job.source, _cancelReason(job), job);
        job.request.cancel();
      } else if (job.cancelAt != null &&
          clockMicros() - job.cancelAt! >= stopGrace.inMicroseconds &&
          !job.source.closingRequested) {
        _closeSource(job.source, P8PDiagnosticCode.stopGraceExceeded, job);
      }
    }
  }

  Future<bool> run({required bool Function() active}) async {
    try {
      _metrics['peak_reservations'] = book.peakReservations;
      _metrics['peak_reserved_bytes'] = book.peakReservedBytes;
      writer.resume();
      while (!_closed && active() && !book.closed && !book.complete) {
        poll();
        // The writer owns ready/writing reservations until each actual commit.
        // Keep polling and fill only the remaining bounded lookahead while it
        // drains; awaiting its whole queue here stalls prefetch and expiry.
        // The final idle await below still observes disk errors and ownership.
        if (book.closed || book.complete) break;
        for (
          var index = book.persistedPieces;
          index < min(book.pieceCount, book.persistedPieces + 4) &&
              book.reservations < 4;
          index++
        ) {
          if (book.phase(index) != P8PPiecePhase.missing) continue;
          final source = _choose(index);
          if (source == null) break;
          _start(index, source);
        }
        if (!book.complete) {
          final owners = _jobs.values
              .where(
                (job) =>
                    job.request.lease.index == book.persistedPieces &&
                    !job.cancelled &&
                    !job.verified,
              )
              .toList();
          if (owners.length == 1) {
            final source = _choose(
              book.persistedPieces,
              excluding: owners.single.source.source.id,
            );
            if (source != null &&
                source.samples > 0 &&
                source.bytesPerMicrosecond != null) {
              final queued = _queuedBytes(source);
              final estimate =
                  (queued + book.sizeOf(book.persistedPieces)) /
                  source.bytesPerMicrosecond!;
              final age =
                  clockMicros() - owners.single.request.lease.startedMicros;
              // A whole-piece age includes transfer/queue time. Do not hedge
              // a body that is still advancing. This never extends expiry,
              // and unverified bytes earn no rate sample or write receipt.
              final idle = clockMicros() - owners.single.lastProgressMicros;
              if (idle >= hedgeAfter.inMicroseconds &&
                  age >=
                      max(hedgeAfter.inMicroseconds, (estimate * 2).ceil())) {
                if (book.reservations < 4) {
                  if (_start(book.persistedPieces, source, hedge: true) !=
                      null) {
                    owners.single.source.failed = true;
                    _count('prefix_rescues');
                  }
                } else {
                  _closeSource(
                    owners.single.source,
                    P8PDiagnosticCode.prefixRescued,
                    owners.single,
                  );
                  _count('prefix_rescues');
                }
              }
            }
          }
        }
        _metrics['peak_reservations'] = max(
          _metrics['peak_reservations'] ?? 0,
          book.peakReservations,
        );
        _metrics['peak_reserved_bytes'] = max(
          _metrics['peak_reserved_bytes'] ?? 0,
          book.peakReservedBytes,
        );
        _metrics['repeat_reserved_bytes'] = book.repeatReservedBytes;
        if (_jobs.isEmpty &&
            !book.complete &&
            book.phase(book.persistedPieces) == P8PPiecePhase.missing) {
          // Includes exhausted retry/byte budgets and no eligible sources.
          final waiting = _sources.values.any(
            (state) =>
                !state.failed &&
                state.availableAfterMicros > clockMicros() &&
                state.source.canServe(book.persistedPieces),
          );
          if (!waiting) return false;
        }
        _wake = Completer<void>();
        await Future.any([
          _wake!.future,
          Future<void>.delayed(const Duration(milliseconds: 25)),
        ]);
      }
      await writer.idle;
      return book.complete;
    } finally {
      await close();
    }
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    for (final state in _sources.values) {
      if (!state.closingRequested) {
        _observe(
          state,
          book.complete
              ? P8PDiagnosticCode.sourceCompleted
              : P8PDiagnosticCode.sourceStopped,
        );
      }
    }
    book.close();
    _notify();
    for (final job in _jobs.values) {
      if (!job.cancelled && !job.verified) job.source.diagnosticCancelled++;
      job.cancelled = true;
      job.request.cancel();
    }
    try {
      await Future.wait([
        ..._sources.values.map((state) => state.source.close()),
        ..._cleanup,
      ]);
    } finally {
      await writer.close();
    }
  }
}
