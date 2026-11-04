import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

typedef BrowseJson = Map<String, dynamic>;
typedef BrowseDirectory = Future<Directory> Function();
const _observerZoneKey = #mestingBrowseCacheObserver;
const _liveZoneKey = #mestingBrowseCacheLive;

/// Disposable page data, independent of playback state and account credentials.
/// Each successful response is committed immediately: process termination does
/// not require an exit callback. Filenames contain only hashed scope/query IDs.
class BrowseResponseCache {
  static bool get observing =>
      Zone.current[_observerZoneKey] != null &&
      Zone.current[_liveZoneKey] != true;
  static Future<T> live<T>(Future<T> Function() load) =>
      runZoned(load, zoneValues: {_liveZoneKey: true});
  BrowseResponseCache({
    BrowseDirectory? directory,
    this.initializeOnRead = false,
    this.maxBytes = 32 * 1024 * 1024,
    this.maxEntryBytes = 8 * 1024 * 1024,
    this.maxEntries = 800,
    this.refreshInterval = const Duration(minutes: 1),
  }) : _directory = directory ?? getApplicationSupportDirectory;

  final BrowseDirectory _directory;
  final bool initializeOnRead;
  final int maxBytes, maxEntryBytes, maxEntries;
  final Duration refreshInterval;

  /// Optional presentation hooks, installed by the app after image storage is
  /// ready. Core persistence has no dependency on Flutter or image decoding.
  Future<bool> Function(BrowseJson previous, BrowseJson incoming)?
  prepareRefresh;
  Future<void> Function(BrowseJson cached)? prepareCached;
  Directory? _root;
  Future<void>? _initializing;
  Future<void> _writes = Future.value();
  final _files = <String, ({File file, int bytes, DateTime used})>{};
  final _memory = <String, BrowseJson>{};
  final _memorySizes = <String, int>{};
  final _waiting = Queue<Completer<void>>();
  int _active = 0;
  final _pending = <String, Future<BrowseJson>>{};
  final _checked = <String, DateTime>{};
  final _listeners = <String, Set<void Function()>>{};
  final _epochs = <String, int>{};

  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    try {
      final base = await _directory();
      final root = Directory('${base.path}/mesting_browse_cache_v1');
      await root.create(recursive: true);
      _root = root;
      await for (final entry in root.list(followLinks: false)) {
        // Process termination can leave an unfinished atomic-write staging
        // file. Recover only our exact filename pattern inside this directory.
        if (entry is File &&
            RegExp(
              r'^[a-f0-9]{64}_[a-f0-9]{64}\.json\.tmp$',
            ).hasMatch(entry.uri.pathSegments.last)) {
          await entry.delete();
          continue;
        }
        if (entry is! File ||
            !RegExp(r'[a-f0-9]{64}_[a-f0-9]{64}\.json$').hasMatch(entry.path)) {
          continue;
        }
        final stat = await entry.stat();
        if (stat.size <= maxEntryBytes) {
          final id = entry.uri.pathSegments.last.replaceFirst('.json', '');
          _files[id] = (file: entry, bytes: stat.size, used: stat.modified);
        } else {
          await entry.delete();
        }
      }
      await _prune();
    } on Object {
      // A storage error affects acceleration only, never the live request.
      _root = null;
    }
  }

  static String _hash(String value) =>
      sha256.convert(utf8.encode(value)).toString();
  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => '$key').toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  /// The UI explicitly opts into cached reads. Playback and writes keep their
  /// live transport. The API supplies the read-only route policy and the same
  /// credential-generation guard used by its network path.
  Future<BrowseJson> read({
    required String scope,
    required String route,
    required Map<String, Object?> query,
    required Future<BrowseJson> Function() load,
    required void Function() checkCurrent,
    String requestIdentity = '',
  }) async {
    checkCurrent();
    final scopeHash = _hash(scope);
    final id =
        '${scopeHash}_${_hash('$route\n${jsonEncode(_canonical(query))}')}';
    final epoch = _epochs[scopeHash] ?? 0;
    final transportIdentity = _hash(requestIdentity);
    final observer = Zone.current[_observerZoneKey] as BrowseCacheWatch?;
    if (observer == null || Zone.current[_liveZoneKey] == true) return load();
    // The application warms its cache alongside native startup. Other entry
    // points keep the original live path until explicitly initialized; a page
    // request must not unexpectedly block on platform storage/plugin startup.
    if (_root == null && !initializeOnRead) return load();
    await initialize();
    checkCurrent();
    if (_root == null) return load();
    if ((_epochs[scopeHash] ?? 0) != epoch) return load();
    final cached = await _restore(id);
    checkCurrent();
    if (cached != null) {
      observer._observe(this, id);
      await prepareCached?.call(cached);
      checkCurrent();
      final checked = _checked[id];
      if (observer.forceRefresh ||
          checked == null ||
          DateTime.now().difference(checked) >= refreshInterval) {
        unawaited(
          _refresh(
            id,
            scopeHash,
            epoch,
            transportIdentity,
            load,
            checkCurrent,
          ).then<void>((_) {}, onError: (Object _) {}),
        );
      }
      return _copy(cached);
    }
    final fresh = await _refresh(
      id,
      scopeHash,
      epoch,
      transportIdentity,
      load,
      checkCurrent,
    );
    checkCurrent();
    observer._observe(this, id);
    return _copy(fresh);
  }

  static BrowseJson _copy(BrowseJson value) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

  Future<BrowseJson?> _restore(String id) async {
    final memory = _memory.remove(id);
    if (memory != null) {
      _memory[id] = memory;
      return memory;
    }
    final record = _files[id];
    if (record == null) return null;
    try {
      final raw = await record.file.readAsString();
      final json = jsonDecode(raw) as Map;
      final body = Map<String, dynamic>.from(json['body'] as Map);
      if (json['version'] != 1 ||
          json['id'] != id ||
          json['hash'] != _hash(jsonEncode(body))) {
        throw const FormatException('Invalid disposable snapshot');
      }
      _files[id] = (
        file: record.file,
        bytes: record.bytes,
        used: DateTime.now(),
      );
      _remember(id, body);
      return body;
    } on Object {
      _files.remove(id);
      try {
        await record.file.delete();
      } on Object {
        /* Retry live. */
      }
      return null;
    }
  }

  void _remember(String id, BrowseJson body) {
    _memory.remove(id);
    _memorySizes.remove(id);
    final bytes = utf8.encode(jsonEncode(body)).length;
    final budget = maxBytes < 4 * 1024 * 1024 ? maxBytes : 4 * 1024 * 1024;
    if (bytes > budget || maxEntries == 0) return;
    _memory[id] = body;
    _memorySizes[id] = bytes;
    // Only a small working set is decoded in RAM; the remaining pages stay on disk.
    while (_memory.length > 24 ||
        _memorySizes.values.fold<int>(0, (a, b) => a + b) > budget) {
      final oldest = _memory.keys.first;
      _memory.remove(oldest);
      _memorySizes.remove(oldest);
    }
  }

  Future<void> _acquire() async {
    if (_active < 3) {
      _active++;
      return;
    }
    final wait = Completer<void>();
    _waiting.add(wait);
    await wait.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _active--;
    }
  }

  Future<BrowseJson> _refresh(
    String id,
    String scopeHash,
    int epoch,
    String transportIdentity,
    Future<BrowseJson> Function() load,
    void Function() checkCurrent,
  ) {
    final pendingKey = '$id:$epoch:$transportIdentity';
    final existing = _pending[pendingKey];
    if (existing != null) return existing;
    late final Future<BrowseJson> request;
    request = () async {
      await _acquire();
      try {
        checkCurrent();
        final body = await load();
        checkCurrent();
        if ((_epochs[scopeHash] ?? 0) != epoch) return body;
        _checked[id] = DateTime.now();
        // Business failures and partial authentication failures must not replace
        // a last successful snapshot, even when transport accepts their JSON.
        final code = int.tryParse('${body['code']}');
        final status = int.tryParse('${body['status']}');
        if ((code != null && code != 200 && code != 0) ||
            status == 0 ||
            body['error_code'] != null && '${body['error_code']}' != '0') {
          return body;
        }
        final encoded = jsonEncode(body);
        if (utf8.encode(encoded).length > maxEntryBytes) return body;
        final previous = await _restore(id);
        checkCurrent();
        if (previous != null && jsonEncode(previous) == encoded) return body;
        if (previous != null && prepareRefresh != null) {
          final ready = await prepareRefresh!(previous, body);
          checkCurrent();
          if ((_epochs[scopeHash] ?? 0) != epoch) return body;
          // A valid JSON response is not yet a renderable replacement. Leave
          // the old durable snapshot and subscribers untouched on image error.
          if (!ready) return _copy(previous);
        }
        final task = _writes.then((_) async {
          checkCurrent();
          if ((_epochs[scopeHash] ?? 0) != epoch) return;
          final root = _root;
          if (root != null) {
            final file = File('${root.path}/$id.json');
            final temporary = File('${file.path}.tmp');
            final bytes = utf8.encode(
              jsonEncode({
                'version': 1,
                'id': id,
                'hash': _hash(encoded),
                'body': body,
              }),
            );
            if (bytes.length <= maxEntryBytes) {
              try {
                await temporary.writeAsBytes(bytes, flush: true);
                checkCurrent();
                if ((_epochs[scopeHash] ?? 0) != epoch) {
                  await temporary.delete();
                  return;
                }
                await temporary.rename(file.path);
                _files[id] = (
                  file: file,
                  bytes: bytes.length,
                  used: DateTime.now(),
                );
                await _prune();
              } on Object {
                try {
                  if (await temporary.exists()) await temporary.delete();
                } on Object {
                  /* Best effort. */
                }
              }
            }
          }
          checkCurrent();
          if ((_epochs[scopeHash] ?? 0) != epoch) return;
          _remember(id, _copy(body));
          for (final listener in List<void Function()>.of(
            _listeners[id] ?? const {},
          )) {
            listener();
          }
        });
        _writes = task.then<void>((_) {}, onError: (Object _) {});
        await task;
        return body;
      } finally {
        _release();
      }
    }();
    _pending[pendingKey] = request;
    unawaited(
      request.then<void>(
        (_) {
          if (identical(_pending[pendingKey], request)) {
            _pending.remove(pendingKey);
          }
        },
        onError: (Object _) {
          if (identical(_pending[pendingKey], request)) {
            _pending.remove(pendingKey);
          }
        },
      ),
    );
    return request;
  }

  Future<void> _prune() async {
    var bytes = _files.values.fold<int>(0, (sum, item) => sum + item.bytes);
    final oldest = _files.keys.toList()
      ..sort((a, b) => _files[a]!.used.compareTo(_files[b]!.used));
    for (final id in oldest) {
      if (bytes <= maxBytes && _files.length <= maxEntries) break;
      final file = _files.remove(id)!;
      _memory.remove(id);
      _memorySizes.remove(id);
      _checked.remove(id);
      bytes -= file.bytes;
      try {
        await file.file.delete();
      } on Object {
        /* Disposable cache. */
      }
    }
  }

  /// Successful library/profile edits invalidate the owner's prior snapshots.
  /// Epochs prevent an earlier in-flight read from restoring those old bytes.
  Future<void> invalidateScope(String scope) async {
    final hash = _hash(scope);
    _epochs[hash] = (_epochs[hash] ?? 0) + 1;
    if (_root == null && !initializeOnRead) return;
    await initialize();
    for (final id in {
      ..._files.keys,
      ..._memory.keys,
    }.where((key) => key.startsWith('${hash}_')).toList()) {
      final file = _files.remove(id);
      _memory.remove(id);
      _memorySizes.remove(id);
      _checked.remove(id);
      if (file != null) {
        try {
          await file.file.delete();
        } on Object {
          /* Disposable cache. */
        }
      }
    }
  }

  /// A user pull-to-refresh keeps the visible snapshot, and makes its next
  /// read revalidate immediately rather than observing the automatic cooldown.
  void revalidateScope(String scope) {
    final prefix = '${_hash(scope)}_';
    _checked.removeWhere((key, _) => key.startsWith(prefix));
  }

  void Function() _listen(String id, void Function() listener) {
    (_listeners[id] ??= {}).add(listener);
    return () {
      _listeners[id]?.remove(listener);
      if (_listeners[id]?.isEmpty == true) _listeners.remove(id);
    };
  }
}

final browseResponseCache = BrowseResponseCache();

/// Tracks only keys used by this provider/page. Notifications wait for the
/// current load to finish, preserving an aggregate or paginated transaction.
class BrowseCacheWatch {
  BrowseCacheWatch(this.onChanged, {this.forceRefresh = false});
  final void Function() onChanged;
  final bool forceRefresh;
  final _subscriptions = <BrowseResponseCache, Map<String, void Function()>>{};
  int _loading = 0;
  bool _disposed = false, _dirty = false, _scheduled = false;

  Future<T> run<T>(Future<T> Function() load) async {
    _loading++;
    try {
      return await runZoned(load, zoneValues: {_observerZoneKey: this});
    } finally {
      _loading--;
      _schedule();
    }
  }

  void _observe(BrowseResponseCache cache, String id) {
    if (_disposed) return;
    final subscriptions = _subscriptions.putIfAbsent(cache, () => {});
    subscriptions.putIfAbsent(
      id,
      () => cache._listen(id, () {
        _dirty = true;
        _schedule();
      }),
    );
  }

  void _schedule() {
    if (_disposed || !_dirty || _loading > 0 || _scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (_disposed || _loading > 0 || !_dirty) return;
      _dirty = false;
      onChanged();
    });
  }

  void dispose() {
    _disposed = true;
    for (final map in _subscriptions.values) {
      for (final cancel in map.values) {
        cancel();
      }
    }
    _subscriptions.clear();
  }
}
