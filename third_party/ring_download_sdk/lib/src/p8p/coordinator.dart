import 'dart:async';
import 'dart:math';

import 'diagnostics.dart';
import 'leases.dart';
import 'lifecycle_trace.dart';
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
  int prefixRecoveries = 0;
  int? recoveryPrefix, recoveryProbe;
  bool get recovering => recoveryPrefix != null;
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
  int? prefixSinceMicros;
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
    this.onLifecycle,
  });
  final P8POrderedWriter writer;
  final int Function() clockMicros;
  final Duration requestTimeout, hedgeAfter, stopGrace;
  final P8PDiagnosticObserver? onDiagnostic;
  final P8PLifecycleObserver? onLifecycle;
  int _snapshotSequence = 0;
  P8PLeaseBook get book => writer.book;
  final _sources = <String, _SourceState>{};
  final _retiredSources = <String, _SourceState>{};
  final _jobs = <int, _Job>{};
  final _cleanup = <Future<void>>[];
  Completer<void>? _wake;
  bool _closed = false;
  Future<void>? _closing;
  final _metrics = <String, int>{};
  // Only six fixed local aliases are exported; opaque source/session IDs
  // never become metric keys. Reading this snapshot cannot change scheduling,
  // goodput samples, ownership, clocks or source availability.
  Map<String, int> get metrics => Map.unmodifiable({
    ..._metrics,
    for (final state in [..._retiredSources.values, ..._sources.values])
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

  /// A live source has delivered a SHA-verified piece, rather than just hello.
  bool hasVerifiedSource(String id) {
    final state = _sources[id];
    return state != null && !state.failed && state.samples > 0;
  }

  /// A failed startup probe can be a normally acknowledged lease timeout.
  /// Retire that unproven source without treating cancellation as a wire fault;
  /// its physical requests and native owner still have to stop before reuse.
  void rejectUnprovenSource(String id) {
    final state = _sources[id];
    if (_closed || state == null || state.samples > 0) return;
    _closeSource(state, P8PDiagnosticCode.sourceStopped);
  }

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
        _retiredSources.containsKey(source.id) ||
        _sources.length >= 4 ||
        _sources.length + _retiredSources.length >= 6) {
      return false;
    }
    final alias =
        const {
              'peer1',
              'peer2',
              'peer3',
              'peer4',
              'seed',
              'https',
            }.contains(diagnosticAlias) &&
            ![
              ..._retiredSources.values,
              ..._sources.values,
            ].any((state) => state.diagnosticAlias == diagnosticAlias)
        ? diagnosticAlias
        : null;
    _sources[source.id] = _SourceState(source, alias);
    _notify();
    return true;
  }

  /// A failed source frees admission only after its real close and all request
  /// owners stop. Keep its metrics and identity consumed for this task. Four
  /// live sources and six lifetime records cover HTTPS, seed and four peers.
  Future<bool> retireFailedSource(String id) async {
    final state = _sources[id];
    if (_closed || state == null || !(state.failed || state.source.closed)) {
      return false;
    }
    try {
      _closeSource(state, P8PDiagnosticCode.sourceStopped);
      await state.source.close();
      await Future.wait(state.jobs.values.map((job) => job.request.stopped));
    } catch (_) {
      // Failed or pending physical disposal never grants replacement capacity.
      return false;
    }
    if (_closed || state.jobs.isNotEmpty || !identical(_sources[id], state)) {
      return false;
    }
    _sources.remove(id);
    _retiredSources[id] = state;
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

  int _tailRecoveryMicros(_Job job, _SourceState replacement, double estimate) {
    final unit = job.request.progressUnitBytes;
    final remaining = job.request.lease.bytes - job.receivedBytes;
    if (unit <= 0 ||
        unit > 64 * 1024 ||
        job.receivedBytes <= 0 ||
        remaining <= 0 ||
        remaining > min(unit, job.request.lease.bytes ~/ 4) ||
        clockMicros() - replacement.lastSample >
            P8PSourceGoodput.sampleTtlMicros) {
      return 0;
    }
    // A nearly complete RTC message may be waiting for one recovery round.
    // Price that wait using the alternative's verified whole-piece cost,
    // capped at one existing rescue interval. Never change the hard lease,
    // request slots, verification rules or source's measured goodput.
    return min(hedgeAfter.inMicroseconds, estimate.ceil());
  }

  _SourceState? _choose(int index, {String? excluding}) {
    var candidates = _sources.values
        .where(
          (state) =>
              !state.failed &&
              (!state.recovering ||
                  (excluding == null &&
                      book.persistedPieces > state.recoveryPrefix! &&
                      state.jobs.isEmpty)) &&
              clockMicros() >= state.availableAfterMicros &&
              state.source.id != excluding &&
              state.source.canServe(index),
        )
        .toList();
    if (index == book.persistedPieces && excluding == null) {
      final now = clockMicros();
      final proven = candidates
          .where(
            (state) =>
                !state.recovering &&
                state.samples > 0 &&
                now - state.lastSample <= P8PSourceGoodput.sampleTtlMicros,
          )
          .toList();
      // Give a new source one lookahead probe while a recently verified
      // origin owns the writable prefix. If all proven owners are busy,
      // wait for capacity instead of putting a cold probe on that prefix.
      // Without a proven provider, cold origins can still make first proof.
      if (proven.isNotEmpty) candidates = proven;
    }
    double estimate(_SourceState state) {
      if (state.recovering ||
          state.samples == 0 ||
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
    final capacity = best.recovering || best.samples == 0
        ? 1
        : best.source.capacity;
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
      if (onLifecycle != null && state.diagnosticRequests == 0) {
        observeP8PLifecycle(
          onLifecycle,
          P8PLifecycleEvent(
            P8PLifecycleCode.requestAllocated,
            alias: state.diagnosticAlias,
            metrics: {
              'request_timeout_us': lease.deadlineMicros - lease.startedMicros,
              'reserved_slots': book.reservations,
            },
          ),
        );
      }
      final request = state.source.start(lease);
      if (state.recovering) state.recoveryProbe = lease.id;
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
            if (state.recoveryProbe == lease.id) {
              state.recoveryPrefix = state.recoveryProbe = null;
              _count('source_rejoins');
            }
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

  void _rescuePrefix(_Job job, {bool hedged = false}) {
    final state = job.source;
    // A proven RTC owner supports request-scoped cancel acknowledgement.
    // One prefix stall need not destroy its siblings or the whole transport.
    // Quarantine new work until that prefix is persisted and all existing
    // physical owners stop, then admit one lookahead proof. A second rescue
    // is terminal for this task; cancellation still has the normal stop grace.
    if (state.source is P8PRtcPieceSource &&
        state.samples > 0 &&
        state.prefixRecoveries == 0) {
      _traceRescueSlots();
      state.prefixRecoveries++;
      state.recoveryPrefix = job.request.lease.index;
      _observe(state, P8PDiagnosticCode.prefixRescued, job);
      book.cancel(job.request.lease);
      job.cancelled = true;
      job.cancelAt = clockMicros();
      state.diagnosticCancelled++;
      job.request.cancel();
      _count('source_recoveries');
    } else if (hedged) {
      state.failed = true;
    } else {
      _closeSource(state, P8PDiagnosticCode.prefixRescued, job);
    }
  }

  void _closeSource(
    _SourceState state,
    P8PDiagnosticCode reason, [
    _Job? cause,
  ]) {
    if (state.closingRequested) return;
    if (reason == P8PDiagnosticCode.prefixRescued) _traceRescueSlots();
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

  void _traceRescueSlots() {
    if (onLifecycle == null) return;
    final now = clockMicros();
    final sequence = ++_snapshotSequence;
    final leases = book.diagnosticReservations;
    for (var position = 0; position < leases.length; position++) {
      final reservation = leases[position];
      final lease = reservation.lease;
      final phase = reservation.phase;
      final ready =
          phase == P8PReservationPhase.ready ||
          phase == P8PReservationPhase.writing;
      final state = _sources[lease.source] ?? _retiredSources[lease.source];
      observeP8PLifecycle(
        onLifecycle,
        P8PLifecycleEvent(
          P8PLifecycleCode.rescueSlot,
          alias: state?.diagnosticAlias,
          metrics: {
            'snapshot_sequence': sequence, 'slot_position': position + 1,
            'reserved_slots': leases.length,
            'slot_phase': phase.index + 1,
            'piece_ahead': lease.index - book.persistedPieces,
            // The latest ordinary poll owns progress observation; tracing never
            // invokes an adapter getter or discounts unverified ownership.
            'body_bytes': ready
                ? lease.bytes
                : (_jobs[lease.id]?.receivedBytes ?? 0),
            'body_expected_bytes': lease.bytes,
            'request_age_us': max(0, now - lease.startedMicros),
            'request_remaining_us': max(0, lease.deadlineMicros - now),
          },
        ),
      );
    }
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
          if (source == null) {
            // A missing prefix still needs its own reservation before any
            // lookahead. Once that owner exists, a busy gap need not prevent
            // other sources from filling the remaining bounded window.
            if (index == book.persistedPieces) break;
            continue;
          }
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
            final prefixOwner = owners.single;
            prefixOwner.prefixSinceMicros ??= clockMicros();
            final source = _choose(
              book.persistedPieces,
              excluding: owners.single.source.source.id,
            );
            if (source != null &&
                !source.recovering &&
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
              // Ahead-of-prefix work did not block ordered writes. Start the
              // idle rescue clock when this request becomes the prefix, or
              // at its latest progress, whichever is later. Its original
              // hard lease deadline and physical slot remain unchanged.
              final idle =
                  clockMicros() -
                  max(
                    prefixOwner.lastProgressMicros,
                    prefixOwner.prefixSinceMicros!,
                  );
              final rescueIdle =
                  hedgeAfter.inMicroseconds +
                  _tailRecoveryMicros(prefixOwner, source, estimate);
              if (idle >= rescueIdle &&
                  age >=
                      max(hedgeAfter.inMicroseconds, (estimate * 2).ceil())) {
                if (book.reservations < 4) {
                  if (_start(book.persistedPieces, source, hedge: true) !=
                      null) {
                    _rescuePrefix(prefixOwner, hedged: true);
                    _count('prefix_rescues');
                  }
                } else {
                  _rescuePrefix(prefixOwner);
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
