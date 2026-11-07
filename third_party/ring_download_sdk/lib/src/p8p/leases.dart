/// Internal, transport-independent ledger for the next P8P capability.
/// A reservation remains occupied while cancelling or waiting for the writer.
/// Nothing here changes the legacy channel or enables multi-source downloads.
enum P8PPiecePhase { missing, leased, ready, writing, persisted }

enum P8PLeasePhase { active, cancelling }

/// A trusted adapter observed its own cancellation, rather than a transport
/// fault. This error alone never acknowledges physical stop or frees a lease.
class P8PLeaseCancelled extends StateError {
  P8PLeaseCancelled() : super('p8p_request_cancelled');
}

class P8PLease {
  P8PLease._(
    this.id,
    this.generation,
    this.index,
    this.source,
    this.bytes,
    this.startedMicros,
    this.deadlineMicros,
    this._repeatCharged,
  );

  final int id, generation, index, bytes, startedMicros, deadlineMicros;
  final String source;
  final bool _repeatCharged;
}

class P8PWrite {
  P8PWrite._(this.lease);
  final P8PLease lease;
  int get index => lease.index;
}

class P8PLeaseBook {
  P8PLeaseBook({
    required this.contentKey,
    required this.fileSha256,
    required this.generation,
    required this.fileBytes,
    required this.pieceBytes,
    required int Function() clockMicros,
    this.maxReservations = 4,
    this.maxAttempts = 3,
    this.repeatBudgetBytes = 0,
    this.taskBudget = const Duration(minutes: 5),
    int persistedPieces = 0,
  }) : _clock = clockMicros,
       _persisted = persistedPieces {
    if (contentKey.isEmpty ||
        contentKey.length > 1024 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(fileSha256) ||
        generation < 1 ||
        fileBytes < 1 ||
        pieceBytes < 1 ||
        pieceBytes > 1024 * 1024 ||
        maxReservations < 1 ||
        maxReservations > 4 ||
        maxAttempts < 1 ||
        maxAttempts > 8 ||
        repeatBudgetBytes < 0 ||
        taskBudget.inMicroseconds <= 0 ||
        persistedPieces < 0 ||
        persistedPieces > pieceCount) {
      throw ArgumentError('invalid P8P task bounds');
    }
    _taskDeadline = _now() + taskBudget.inMicroseconds;
  }

  /// Must include trusted namespace/release/size/hash, never just a URL.
  final String contentKey, fileSha256;
  final int generation, fileBytes, pieceBytes;
  final int maxReservations, maxAttempts, repeatBudgetBytes;
  final Duration taskBudget;
  final int Function() _clock;
  final _leases = <int, P8PLease>{};
  final _cancelling = <int>{};
  final _admissionRejected = <int>{};
  final _ready = <int, P8PLease>{};
  final _attempts = <int, int>{};
  late final int _taskDeadline;
  int _lastNow = 0, _nextId = 0, _repeatReserved = 0, _persisted;
  P8PWrite? _writing;
  bool _closed = false;
  int _peakReservations = 0, _peakReservedBytes = 0;
  int _admissionRejections = 0;

  int get pieceCount => (fileBytes + pieceBytes - 1) ~/ pieceBytes;
  int get persistedPieces => _persisted;
  int get persistedBytes => (_persisted * pieceBytes).clamp(0, fileBytes);
  int get repeatReservedBytes => _repeatReserved;
  bool get closed => _closed;
  bool get complete => _persisted == pieceCount;
  int get reservations => _leases.length + _ready.length;
  int get peakReservations => _peakReservations;
  int get peakReservedBytes => _peakReservedBytes;
  int get reservedBytes =>
      _leases.values.fold(0, (sum, lease) => sum + lease.bytes) +
      _ready.values.fold(0, (sum, lease) => sum + lease.bytes);
  List<P8PLease> get cancellations => List.unmodifiable(
    _leases.values.where((lease) => _cancelling.contains(lease.id)),
  );

  int sizeOf(int index) => index < 0 || index >= pieceCount
      ? 0
      : (fileBytes - index * pieceBytes).clamp(0, pieceBytes);

  P8PPiecePhase phase(int index) {
    if (sizeOf(index) == 0) throw RangeError.index(index, this, 'index');
    if (index < _persisted) return P8PPiecePhase.persisted;
    if (_writing?.index == index) return P8PPiecePhase.writing;
    if (_ready.containsKey(index)) return P8PPiecePhase.ready;
    return _leases.values.any((lease) => lease.index == index)
        ? P8PPiecePhase.leased
        : P8PPiecePhase.missing;
  }

  /// Repeated body attempts, including hedges, reserve their entire possible
  /// body. Cancelling never refunds it. A validated bodyless HTTP admission
  /// rejection is separately released only after physical stop.
  P8PLease? request(
    int index,
    String source, {
    required Duration timeout,
    bool hedge = false,
    Duration hedgeAfter = const Duration(seconds: 1),
  }) {
    final now = _now();
    expire();
    if (_closed ||
        complete ||
        now >= _taskDeadline ||
        reservations >= maxReservations ||
        sizeOf(index) == 0 ||
        index < _persisted ||
        _ready.containsKey(index) ||
        source.isEmpty ||
        source.length > 128 ||
        timeout.inMicroseconds <= 0 ||
        hedgeAfter.inMicroseconds < 0) {
      return null;
    }
    final owners = _leases.values.where((lease) => lease.index == index);
    if (owners.isNotEmpty &&
        (!hedge ||
            owners.length != 1 ||
            _cancelling.contains(owners.single.id) ||
            owners.single.source == source ||
            now - owners.single.startedMicros < hedgeAfter.inMicroseconds)) {
      return null;
    }
    final attempt = _attempts[index] ?? 0;
    final bytes = sizeOf(index);
    if (attempt >= maxAttempts ||
        (attempt > 0 && _repeatReserved + bytes > repeatBudgetBytes)) {
      return null;
    }
    if (attempt > 0) _repeatReserved += bytes;
    _attempts[index] = attempt + 1;
    final lease = P8PLease._(
      ++_nextId,
      generation,
      index,
      source,
      bytes,
      now,
      (now + timeout.inMicroseconds).clamp(0, _taskDeadline),
      attempt > 0,
    );
    _leases[lease.id] = lease;
    if (reservations > _peakReservations) _peakReservations = reservations;
    if (reservedBytes > _peakReservedBytes) _peakReservedBytes = reservedBytes;
    return lease;
  }

  bool accepts(P8PLease lease) =>
      !_closed &&
      identical(_leases[lease.id], lease) &&
      !_cancelling.contains(lease.id) &&
      _now() < lease.deadlineMicros;

  P8PLeasePhase? leasePhase(P8PLease lease) {
    if (!identical(_leases[lease.id], lease)) return null;
    return _cancelling.contains(lease.id)
        ? P8PLeasePhase.cancelling
        : P8PLeasePhase.active;
  }

  /// Caller must validate the complete piece before this transition. The
  /// accepted request has finished; other owners must actually stop separately.
  bool verified(P8PLease lease) {
    if (!accepts(lease)) return false;
    _leases.remove(lease.id);
    _ready[lease.index] = lease;
    for (final other in _leases.values) {
      if (other.index == lease.index) _cancelling.add(other.id);
    }
    return true;
  }

  bool cancel(P8PLease lease) {
    if (!identical(_leases[lease.id], lease)) return false;
    return _cancelling.add(lease.id);
  }

  /// Only the trusted HTTPS adapter can report a validated bodyless admission
  /// rejection. Capacity and accounting remain owned until physical stop.
  /// Ordinary cancellation, corruption or partial bodies never use this path.
  bool rejectAdmission(P8PLease lease) {
    if (lease.source != 'https' ||
        _admissionRejections >= 2 ||
        !accepts(lease)) {
      return false;
    }
    _admissionRejections++;
    _admissionRejected.add(lease.id);
    _cancelling.add(lease.id);
    return true;
  }

  /// Only call after the source adapter has stopped producing callbacks and
  /// released its receive buffer. Sending a cancel frame alone is insufficient.
  bool acknowledgeStopped(P8PLease lease) {
    if (!identical(_leases[lease.id], lease) || !_cancelling.remove(lease.id)) {
      return false;
    }
    _leases.remove(lease.id);
    if (_admissionRejected.remove(lease.id)) {
      final attempts = _attempts[lease.index]! - 1;
      if (attempts == 0) {
        _attempts.remove(lease.index);
      } else {
        _attempts[lease.index] = attempts;
      }
      if (lease._repeatCharged) _repeatReserved -= lease.bytes;
    }
    return true;
  }

  void expire() {
    final now = _now();
    if (now >= _taskDeadline) {
      close();
      return;
    }
    for (final lease in _leases.values) {
      if (now >= lease.deadlineMicros) _cancelling.add(lease.id);
    }
  }

  /// Ready/writing payloads still occupy their reservation until the single
  /// contiguous writer commits them. Never use sparse file length as progress.
  P8PWrite? beginWrite() {
    expire();
    if (_closed || _writing != null) return null;
    final ready = _ready[_persisted];
    return ready == null ? null : (_writing = P8PWrite._(ready));
  }

  void persisted(P8PWrite write) {
    if (!identical(_writing, write) || write.index != _persisted) {
      throw StateError('P8P writer ownership changed');
    }
    _ready.remove(write.index);
    _attempts.remove(write.index);
    _persisted++;
    _writing = null;
  }

  void writeFailed(P8PWrite write) {
    if (!identical(_writing, write)) {
      throw StateError('P8P writer ownership changed');
    }
    _ready.remove(write.index);
    _writing = null;
    close();
  }

  /// An already running write may finish. Its owner must await it before
  /// returning file ownership to HTTPS or starting a new task generation.
  void close() {
    _closed = true;
    _cancelling.addAll(_leases.keys);
    _ready.removeWhere((index, _) => _writing?.index != index);
  }

  int _now() {
    final now = _clock();
    if (now < _lastNow) throw StateError('P8P clock must be monotonic');
    _lastNow = now;
    return now;
  }
}
