/// A second allowlist at the platform-channel boundary. Never copy raw Android
/// tombstone maps into a report, even when a future/native implementation adds
/// more fields. This contains no command lines, logs, registers or full paths.
class NativeCrashSummary {
  NativeCrashSummary._(this._data);
  final Map<String, Object> _data;
  Map<String, Object> toJson() => Map.of(_data);

  static const _statuses = {
    'available',
    'unavailable',
    'unsupported',
    'not_requested',
    'thread_unavailable',
    'limit_exceeded',
    'invalid_or_unavailable',
  };
  static final _library = RegExp(r'^[A-Za-z0-9_.-]{1,128}\.so(?:\.[0-9]+)*$');
  static final _symbol = RegExp(
    r'^[A-Za-z_~][A-Za-z0-9_$:<>() ,.*+~&\[\]=!-]{0,159}$',
  );
  static final _hex = RegExp(r'^[a-fA-F0-9]{1,128}$');
  static final _address = RegExp(r'^0x[a-fA-F0-9]{1,16}$');
  static const _signalNames = {
    'SIGSEGV',
    'SIGABRT',
    'SIGBUS',
    'SIGILL',
    'SIGFPE',
    'SIGTRAP',
    'SIGSYS',
    'SIGPIPE',
  };

  static NativeCrashSummary? parse(Object? value) {
    if (value is! Map || !_statuses.contains(value['status'])) return null;
    final data = <String, Object>{'status': value['status'] as String};
    if (value['status'] != 'available') {
      return NativeCrashSummary._(Map.unmodifiable(data));
    }
    final signal = value['signal'];
    final cleanSignal = <String, Object>{};
    if (signal is Map) {
      for (final key in ['number', 'code']) {
        final number = signal[key];
        if (number is int && number >= -2147483648 && number <= 2147483647) {
          cleanSignal[key] = number;
        }
      }
      if (_signalNames.contains(signal['name'])) {
        cleanSignal['name'] = signal['name'] as String;
      }
      _text(cleanSignal, signal, 'codeName', RegExp(r'^[A-Z0-9_]{1,48}$'));
      _text(cleanSignal, signal, 'faultAddress', _address);
    }
    final thread = value['thread'];
    final frames = <Map<String, Object>>[];
    var name = 'other';
    if (thread is Map) {
      final candidate = thread['name'];
      if (candidate is String &&
          (candidate == 'main' ||
              RegExp(
                    r'^(?:io\.flutter\.)?[0-9]+\.(?:raster|ui|io|platform)$',
                  ).stringMatch(candidate) ==
                  candidate)) {
        name = candidate;
      }
      final rawFrames = thread['frames'];
      if (rawFrames is List) {
        for (final frame in rawFrames.take(24)) {
          if (frame is! Map) continue;
          final clean = <String, Object>{};
          _text(clean, frame, 'library', _library);
          _text(clean, frame, 'function', _symbol);
          _text(clean, frame, 'buildId', _hex);
          _text(clean, frame, 'relativePc', _address);
          if (clean.isNotEmpty) frames.add(Map.unmodifiable(clean));
        }
      }
    }
    data['signal'] = Map<String, Object>.unmodifiable(cleanSignal);
    data['thread'] = Map<String, Object>.unmodifiable({
      'name': name,
      'frames': List.unmodifiable(frames),
    });
    return NativeCrashSummary._(Map.unmodifiable(data));
  }

  static void _text(
    Map<String, Object> target,
    Map source,
    String key,
    RegExp allowed,
  ) {
    final value = source[key];
    // Check length before the regexp, bounding input from a malformed channel.
    if (value is String &&
        value.length <= 164 &&
        allowed.stringMatch(value) == value) {
      target[key] = value;
    }
  }
}
