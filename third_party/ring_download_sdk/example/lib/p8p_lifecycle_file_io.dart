// Private lifecycle fixture. Every byte and handle uses the actual filesystem.
// The controlled hold occurs AFTER native IO, with its real handle still open;
// it models an unfinished caller operation, not a blocked kernel syscall.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

final class NativeFileIoGate extends IOOverrides {
  NativeFileIoGate() {
    _entered.future.ignore();
    _released.future.ignore();
  }

  static const holdDuration = Duration(seconds: 3);
  final _watch = Stopwatch()..start();
  final _entered = Completer<void>(), _released = Completer<void>();
  final _handles = <RandomAccessFile, String>{};
  final _pending = <RandomAccessFile, int>{};
  final _events = <Map<String, Object?>>[];
  String? _path, _phase;
  bool _claimed = false, _retired = false, _invalid = false;
  int _lateReads = 0, _lateWrites = 0, _earlyCloses = 0;
  int _nativeBytes = 0;

  Future<void> get entered => _entered.future;
  Future<void> get released => _released.future;

  void armRead(String path) => _arm('read', path);
  void armWrite(String path) => _arm('write', path);

  void _arm(String phase, String path) {
    if (_phase != null || _retired || !super.createFile(path).isAbsolute) {
      throw StateError('File IO gate requires one explicit absolute target');
    }
    _phase = phase;
    _path = path;
    _event('armed');
  }

  void retire() {
    if (_retired) return;
    _retired = true;
    _event('retired');
  }

  void _event(String name) {
    // Observability overflow must invalidate acceptance without preventing a
    // finally block from closing an actual native file handle.
    if (_events.length >= 32) {
      _invalid = true;
      return;
    }
    _events.add({
      'event': name,
      'at_us': _watch.elapsedMicroseconds,
      'target_handles': _handles.values.where((p) => p == _path).length,
      'pending_operations': _pending.values.fold<int>(0, (a, b) => a + b),
    });
  }

  void _failure(Object error) {
    _invalid = true;
    _event('io_error');
    if (_phase != null && !_entered.isCompleted) _entered.completeError(error);
  }

  bool _claim(String phase, String path, {bool pieceRead = false}) {
    if (_phase != phase || _path != path || (phase == 'read' && !pieceRead)) {
      return false;
    }
    if (_retired) {
      if (phase == 'read') {
        _lateReads++;
      } else {
        _lateWrites++;
      }
      _event('new_transfer_io_after_retire');
      return false;
    }
    if (_claimed) return false;
    _claimed = true;
    return true;
  }

  Future<void> _opened(RandomAccessFile handle, String path) async {
    if (_handles.length >= 32 || _handles.containsKey(handle)) {
      _invalid = true;
      await handle.close();
      throw StateError('Private file handle bound exceeded');
    }
    _handles[handle] = path;
    if (path == _path) _event('opened');
  }

  void _closing(RandomAccessFile handle) {
    if ((_pending[handle] ?? 0) > 0) {
      _earlyCloses++;
      _event('close_while_operation_pending');
    }
  }

  void _closed(RandomAccessFile handle) {
    final target = _handles.remove(handle) == _path;
    if (target) _event('closed');
  }

  Future<void> _hold(RandomAccessFile handle, File file, int bytes) async {
    _pending[handle] = (_pending[handle] ?? 0) + 1;
    try {
      if (!_handles.containsKey(handle) ||
          bytes <= 0 ||
          file.statSync().type != FileSystemEntityType.file) {
        throw StateError('Controlled IO lacks a real regular-file owner');
      }
      _nativeBytes += bytes;
      _event('native_io_completed_with_handle_open');
      if (!_entered.isCompleted) _entered.complete();
      await Future<void>.delayed(holdDuration);
      if (!_handles.containsKey(handle)) {
        throw StateError('Native file handle closed before operation returned');
      }
      _event('hold_ended_with_handle_open');
    } catch (error) {
      _failure(error);
      rethrow;
    } finally {
      final count = (_pending[handle] ?? 1) - 1;
      if (count == 0) {
        _pending.remove(handle);
      } else {
        _pending[handle] = count;
      }
      if (!_released.isCompleted) _released.complete();
    }
  }

  Map<String, Object?> snapshot() => {
    'phase': _phase,
    'retired': _retired,
    'claimed': _claimed,
    'invalid': _invalid,
    'native_bytes': _nativeBytes,
    'valid':
        !_invalid && _lateReads == 0 && _lateWrites == 0 && _earlyCloses == 0,
    'target_handles': _handles.values.where((p) => p == _path).length,
    'all_wrapped_handles': _handles.length,
    'pending_operations': _pending.values.fold<int>(0, (a, b) => a + b),
    'new_read_streams_after_retire': _lateReads,
    'new_writes_after_retire': _lateWrites,
    'premature_close_calls': _earlyCloses,
    'hold_duration_ms': holdDuration.inMilliseconds,
    'hold_is_after_native_io': true,
    'events': [for (final row in _events) Map<String, Object?>.from(row)],
  };

  @override
  File createFile(String path) => _wrap(super.createFile(path));
  File _wrap(File file) => file is _IoFile && identical(file.gate, this)
      ? file
      : _IoFile(file, this);
}

class _IoFile implements File {
  _IoFile(this.real, this.gate);
  final File real;
  final NativeFileIoGate gate;

  @override
  String get path => real.path;
  @override
  Uri get uri => real.uri;
  @override
  bool get isAbsolute => real.isAbsolute;
  @override
  File get absolute => gate._wrap(real.absolute);
  @override
  Directory get parent => real.parent;
  @override
  Future<bool> exists() => real.exists();
  @override
  bool existsSync() => real.existsSync();
  @override
  Future<int> length() => real.length();
  @override
  int lengthSync() => real.lengthSync();
  @override
  Future<FileStat> stat() => real.stat();
  @override
  FileStat statSync() => real.statSync();
  @override
  Future<String> resolveSymbolicLinks() => real.resolveSymbolicLinks();
  @override
  String resolveSymbolicLinksSync() => real.resolveSymbolicLinksSync();
  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) async =>
      gate._wrap(await real.create(recursive: recursive, exclusive: exclusive));
  @override
  void createSync({bool recursive = false, bool exclusive = false}) =>
      real.createSync(recursive: recursive, exclusive: exclusive);
  @override
  Future<File> copy(String newPath) async =>
      gate._wrap(await real.copy(newPath));
  @override
  File copySync(String newPath) => gate._wrap(real.copySync(newPath));
  @override
  Future<File> rename(String newPath) async =>
      gate._wrap(await real.rename(newPath));
  @override
  File renameSync(String newPath) => gate._wrap(real.renameSync(newPath));
  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      real.delete(recursive: recursive);
  @override
  void deleteSync({bool recursive = false}) =>
      real.deleteSync(recursive: recursive);

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async {
    final handle = await real.open(mode: mode);
    await gate._opened(handle, path);
    return _IoHandle(handle, real, gate);
  }

  @override
  Stream<List<int>> openRead([int? start, int? end]) {
    final hold = gate._claim(
      'read',
      path,
      pieceRead: end != null && end > (start ?? 0),
    );
    return hold ? _controlledRead(start ?? 0, end!) : real.openRead(start, end);
  }

  Stream<List<int>> _controlledRead(int start, int end) async* {
    RandomAccessFile? handle;
    var registered = false;
    try {
      handle = await real.open();
      await gate._opened(handle, path);
      registered = true;
      await handle.setPosition(start);
      var remaining = end - start;
      var first = true;
      while (remaining > 0) {
        final data = await handle.read(remaining > 65536 ? 65536 : remaining);
        if (data.isEmpty) break;
        if (first) {
          first = false;
          await gate._hold(handle, real, data.length);
        }
        remaining -= data.length;
        yield data;
      }
      if (first) {
        throw StateError('Controlled regular-file read produced no bytes');
      }
    } catch (error) {
      gate._failure(error);
      rethrow;
    } finally {
      if (handle != null && registered) {
        gate._closing(handle);
        try {
          await handle.close();
          gate._closed(handle);
        } catch (error) {
          gate._failure(error);
          rethrow;
        }
      }
    }
  }

  @override
  Future<Uint8List> readAsBytes() => real.readAsBytes();
  @override
  Uint8List readAsBytesSync() => real.readAsBytesSync();
  @override
  Future<String> readAsString({Encoding encoding = utf8}) =>
      real.readAsString(encoding: encoding);
  @override
  String readAsStringSync({Encoding encoding = utf8}) =>
      real.readAsStringSync(encoding: encoding);
  @override
  Future<List<String>> readAsLines({Encoding encoding = utf8}) =>
      real.readAsLines(encoding: encoding);
  @override
  List<String> readAsLinesSync({Encoding encoding = utf8}) =>
      real.readAsLinesSync(encoding: encoding);
  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async =>
      gate._wrap(await real.writeAsBytes(bytes, mode: mode, flush: flush));
  @override
  void writeAsBytesSync(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) => real.writeAsBytesSync(bytes, mode: mode, flush: flush);
  @override
  Future<File> writeAsString(
    String value, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async => gate._wrap(
    await real.writeAsString(
      value,
      mode: mode,
      encoding: encoding,
      flush: flush,
    ),
  );
  @override
  void writeAsStringSync(
    String value, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) => real.writeAsStringSync(
    value,
    mode: mode,
    encoding: encoding,
    flush: flush,
  );
  @override
  Stream<FileSystemEvent> watch({
    int events = FileSystemEvent.all,
    bool recursive = false,
  }) => real.watch(events: events, recursive: recursive);

  // Unexpected operations fail the private fixture rather than inventing IO.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final error = UnsupportedError(
      'Unsupported lifecycle fixture File operation',
    );
    gate._failure(error);
    throw error;
  }
}

class _IoHandle implements RandomAccessFile {
  _IoHandle(this.real, this.file, this.gate);
  final RandomAccessFile real;
  final File file;
  final NativeFileIoGate gate;
  @override
  String get path => real.path;
  @override
  Future<void> close() async {
    gate._closing(real);
    try {
      await real.close();
      gate._closed(real);
    } catch (error) {
      gate._failure(error);
      rethrow;
    }
  }

  @override
  Future<RandomAccessFile> writeFrom(
    List<int> buffer, [
    int start = 0,
    int? end,
  ]) async {
    final hold = gate._claim('write', path);
    try {
      await real.writeFrom(buffer, start, end);
      if (hold) await gate._hold(real, file, (end ?? buffer.length) - start);
      return this;
    } catch (error) {
      gate._failure(error);
      rethrow;
    }
  }

  @override
  Future<Uint8List> read(int count) => real.read(count);
  @override
  Future<int> readInto(List<int> buffer, [int start = 0, int? end]) =>
      real.readInto(buffer, start, end);
  @override
  Future<int> readByte() => real.readByte();
  @override
  Future<int> length() => real.length();
  @override
  int lengthSync() => real.lengthSync();
  @override
  Future<int> position() => real.position();
  @override
  Future<RandomAccessFile> setPosition(int position) async {
    await real.setPosition(position);
    return this;
  }

  @override
  Future<RandomAccessFile> truncate(int length) async {
    await real.truncate(length);
    return this;
  }

  @override
  Future<RandomAccessFile> flush() async {
    await real.flush();
    return this;
  }

  @override
  Future<RandomAccessFile> lock([
    FileLock mode = FileLock.exclusive,
    int start = 0,
    int end = -1,
  ]) async {
    await real.lock(mode, start, end);
    return this;
  }

  @override
  Future<RandomAccessFile> unlock([int start = 0, int end = -1]) async {
    await real.unlock(start, end);
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final error = UnsupportedError(
      'Unsupported lifecycle fixture file-handle operation',
    );
    gate._failure(error);
    throw error;
  }
}
