import 'dart:math';

class _Sample {
  const _Sample(this.bytes, this.busyMicros);
  final int bytes, busyMicros;
}

/// Verified bytes divided by the union of physical-request ownership time.
/// Shared queue time is counted once per origin, not once per queued piece.
/// Idle time without an owner is excluded; cancelled/unverified bytes earn
/// no sample. Four recent completions bound memory and adaptation history.
class P8PSourceGoodput {
  static const sampleTtlMicros = 10000000;
  final _window = <_Sample>[];
  int _owners = 0, _busyMicros = 0, _sampledBusyMicros = 0;
  int _windowBytes = 0, _windowMicros = 0;
  int? _accountedAt;
  int? lastSampleMicros;
  int get samples => _window.length;
  double? get bytesPerMicrosecond =>
      _window.isEmpty ? null : _windowBytes / max(1, _windowMicros);

  void _account(int now) {
    if (_owners > 0 && _accountedAt != null) {
      _busyMicros += max(0, now - _accountedAt!);
    }
    _accountedAt = now;
  }

  void started(int now) {
    _account(now);
    if (_owners == 0 &&
        lastSampleMicros != null &&
        now - lastSampleMicros! > sampleTtlMicros) {
      _window.clear();
      _windowBytes = _windowMicros = 0;
      _busyMicros = _sampledBusyMicros = 0;
      lastSampleMicros = null;
    }
    _owners++;
  }

  void stopped(int now) {
    if (_owners == 0) throw StateError('p8p_unowned_goodput_stop');
    _account(now);
    _owners--;
  }

  void verified(int bytes, int now) {
    if (bytes <= 0) throw ArgumentError.value(bytes, 'bytes');
    _account(now);
    final sample = _Sample(bytes, _busyMicros - _sampledBusyMicros);
    _sampledBusyMicros = _busyMicros;
    _window.add(sample);
    _windowBytes += sample.bytes;
    _windowMicros += sample.busyMicros;
    if (_window.length > 4) {
      final oldest = _window.removeAt(0);
      _windowBytes -= oldest.bytes;
      _windowMicros -= oldest.busyMicros;
    }
    lastSampleMicros = now;
  }
}
