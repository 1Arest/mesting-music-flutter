import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/security/avatar_image_validator.dart';
import '../../core/diagnostics/local_music_diagnostics.dart';
import '../utils/media_uri.dart';

typedef PersistentNetworkImageDirectoryProvider = Future<Directory> Function();

/// Keeps validated remote images in the app-private storage directory.
///
/// [cacheKey] identifies the logical image owner (for example a social user),
/// while the URL path distinguishes avatar replacements. Volatile URL query
/// parameters, such as download signatures, deliberately do not create a
/// second cache entry for the same image.
class PersistentNetworkImageCache {
  PersistentNetworkImageCache({
    http.Client? client,
    PersistentNetworkImageDirectoryProvider? directoryProvider,
    Duration requestTimeout = const Duration(seconds: 18),
    this.maxBytes = 256 * 1024 * 1024,
    this.maxFiles = 4000,
  }) : _client = client ?? http.Client(),
       _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _requestTimeout = requestTimeout;

  static const _directoryName = 'mesting_network_image_cache';

  final http.Client _client;
  final PersistentNetworkImageDirectoryProvider _directoryProvider;
  final Duration _requestTimeout;
  final int maxBytes, maxFiles;
  Future<void>? _initializing;
  Directory? _root;
  final _validated = <String>{};
  final _disk = <String, ({int bytes, DateTime used})>{};
  final _contentFiles = <String, String>{};
  bool _contentIndexDirty = false;
  Future<void> _maintenance = Future.value();
  final Map<String, File> _memoryFiles = <String, File>{};
  final Map<String, Future<File?>> _pendingLoads = <String, Future<File?>>{};
  bool get initialized => _root != null;

  /// Warm the filename index alongside native startup, before cached page
  /// data mounts its covers. Decoding remains sized to each visible widget.
  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    try {
      final base = await _directoryProvider();
      final root = Directory(
        '${base.path}${Platform.pathSeparator}$_directoryName',
      );
      await root.create(recursive: true);
      _root = root;
      final index = File('${root.path}/content-index-v1.json');
      try {
        if (await index.exists() && await index.length() <= 1024 * 1024) {
          final saved = jsonDecode(await index.readAsString()) as Map;
          for (final item in saved.entries.take(maxFiles)) {
            if (RegExp(r'^[a-f0-9]{64}$').hasMatch('${item.key}') &&
                RegExp(r'^[a-f0-9]{64}$').hasMatch('${item.value}')) {
              _contentFiles['${item.key}'] = '${item.value}';
            }
          }
        }
      } on Object {
        /* A corrupt optional index cannot invalidate images. */
      }
      await for (final entry in root.list(followLinks: false)) {
        if (entry is! File) continue;
        final name = entry.uri.pathSegments.last;
        if (name == 'content-index-v1.json.tmp') {
          await entry.delete();
          continue;
        }
        if (RegExp(r'^[a-f0-9]{64}\.avatar\.[0-9]+\.tmp$').hasMatch(name)) {
          await entry.delete();
          continue;
        }
        if (!RegExp(r'^[a-f0-9]{64}\.avatar$').hasMatch(name)) continue;
        final stat = await entry.stat();
        final key = name.substring(0, 64);
        if (stat.size > 0 &&
            stat.size <= maxAvatarBytes &&
            stat.size <= maxBytes) {
          _memoryFiles[key] = entry;
          _disk[key] = (bytes: stat.size, used: stat.modified);
        } else {
          await entry.delete();
        }
      }
      await _prune();
    } on Object {
      _root = null;
    }
  }

  Future<void> _prune() async {
    var bytes = _disk.values.fold<int>(0, (sum, item) => sum + item.bytes);
    final keys = _disk.keys.toList()
      ..sort((a, b) => _disk[a]!.used.compareTo(_disk[b]!.used));
    for (final key in keys) {
      if (bytes <= maxBytes && _disk.length <= maxFiles) break;
      bytes -= _disk.remove(key)!.bytes;
      _validated.remove(key);
      final file = _memoryFiles.remove(key);
      if (file != null) {
        try {
          await file.delete();
        } on Object {
          /* Disposable image. */
        }
      }
    }
  }

  /// Returns an already-resolved file without waiting for disk I/O.
  File? peek({required String cacheKey, required String url}) {
    final key = _cacheFileKey(cacheKey: cacheKey, url: url);
    if (key == null) return null;
    final file = _memoryFiles[key];
    if (file == null) return null;
    if (file.existsSync()) {
      _noteContent(cacheKey, url, key);
      final metadata = _disk[key];
      if (metadata != null) {
        _disk[key] = (bytes: metadata.bytes, used: DateTime.now());
      }
      return file;
    }
    _memoryFiles.remove(key);
    return null;
  }

  /// Restore a previously viewed thumbnail when the caller knows only the
  /// original cover URL. The index contains hashes only, never URL/token data.
  File? peekContent({required String cacheKey, required String url}) {
    final exact = peek(cacheKey: cacheKey, url: url);
    if (exact != null) return exact;
    final content = sha256
        .convert(utf8.encode('$cacheKey\n${artworkContentIdentity(url)}'))
        .toString();
    final key = _contentFiles[content];
    final indexed = _memoryFiles[key];
    if (indexed != null && indexed.existsSync()) return indexed;
    // Migration for 1.0.26/27: old filenames do not retain their source URL.
    // Resolve established square thumbnail sizes from the in-memory index.
    for (final size in [
      192,
      216,
      240,
      288,
      324,
      360,
      384,
      480,
      540,
      600,
      720,
      768,
      960,
      1024,
    ]) {
      final found = peek(
        cacheKey: cacheKey,
        url: sizedArtworkUri(url, width: size, height: size),
      );
      if (found != null) return found;
    }
    return null;
  }

  void _noteContent(String owner, String url, String fileKey) {
    final key = sha256
        .convert(utf8.encode('$owner\n${artworkContentIdentity(url)}'))
        .toString();
    if (_contentFiles[key] == fileKey) return;
    _contentFiles.remove(key);
    _contentFiles[key] = fileKey;
    while (_contentFiles.length > maxFiles) {
      _contentFiles.remove(_contentFiles.keys.first);
    }
    _contentIndexDirty = true;
  }

  /// Display-time peek stays synchronous and never starts filesystem writes.
  /// Successful resolves and presentation preparation explicitly flush the
  /// optional index, avoiding outstanding writers after a consumer is disposed.
  Future<void> flush() {
    if (!_contentIndexDirty) return _maintenance;
    _contentIndexDirty = false;
    final encoded = jsonEncode(_contentFiles);
    final write = _maintenance.then((_) async {
      final root = _root;
      if (root == null) return;
      final target = File('${root.path}/content-index-v1.json');
      final temp = File('${target.path}.tmp');
      try {
        await temp.writeAsString(encoded, flush: true);
        await temp.rename(target.path);
      } on Object {
        _contentIndexDirty = true;
        /* An optional acceleration index can be rebuilt. */
      }
    });
    _maintenance = write.then<void>((_) {}, onError: (Object _) {});
    return _maintenance;
  }

  /// Reads a cached image first, downloading and validating it only on a miss.
  Future<File?> resolve({required String cacheKey, required String url}) {
    final key = _cacheFileKey(cacheKey: cacheKey, url: url);
    if (key == null) return Future<File?>.value();
    final memoryFile = peek(cacheKey: cacheKey, url: url);
    if (memoryFile != null && _validated.contains(key)) {
      return flush().then((_) => memoryFile);
    }

    final pending = _pendingLoads[key];
    if (pending != null) return pending;

    final load = _load(cacheKey: key, url: url).then((file) async {
      if (file != null) {
        _noteContent(cacheKey, url, key);
        await flush();
      }
      return file;
    });
    _pendingLoads[key] = load;
    unawaited(load.whenComplete(() => _pendingLoads.remove(key)));
    return load;
  }

  /// Removes a broken cache entry so a later retry can fetch a clean image.
  Future<void> invalidate({
    required String cacheKey,
    required String url,
  }) async {
    final key = _cacheFileKey(cacheKey: cacheKey, url: url);
    if (key == null) return;
    _memoryFiles.remove(key);
    _validated.remove(key);
    _disk.remove(key);
    try {
      final file = await _cacheFile(key);
      if (await file.exists()) await file.delete();
    } on Object {
      // A cache cleanup failure must never prevent an avatar retry.
    }
  }

  Future<File?> _load({required String cacheKey, required String url}) async {
    File? temporary;
    try {
      final target = await _cacheFile(cacheKey);
      if (await target.exists()) {
        if (await target.length() > 0) {
          try {
            await validateAvatarImage(target.path);
            _memoryFiles[cacheKey] = target;
            _validated.add(cacheKey);
            LocalMusicDiagnostics.record(
              'artwork.disk_hit',
              LocalMusicDiagnostics.artwork(url),
            );
            return target;
          } on AvatarValidationException {
            // Older caches only checked nonzero length. A cached HTML/error
            // response must be replaced, rather than passed back forever.
          }
        }
        await target.delete();
      }

      final uri = Uri.tryParse(url.trim());
      if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
        return null;
      }
      final response = await _client
          .get(uri, headers: artworkRequestHeaders(url))
          .timeout(_requestTimeout);
      LocalMusicDiagnostics.record('artwork.http', {
        ...LocalMusicDiagnostics.artwork(url),
        'status': response.statusCode,
        'bytes': response.bodyBytes.length,
      });
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          response.bodyBytes.isEmpty ||
          response.bodyBytes.length > maxAvatarBytes ||
          response.bodyBytes.length > maxBytes) {
        return null;
      }

      temporary = File(
        '${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      await temporary.writeAsBytes(response.bodyBytes, flush: true);
      await validateAvatarImage(temporary.path);
      await temporary.rename(target.path);
      temporary = null;
      _memoryFiles[cacheKey] = target;
      _validated.add(cacheKey);
      _disk[cacheKey] = (
        bytes: response.bodyBytes.length,
        used: DateTime.now(),
      );
      final maintenance = _maintenance.then((_) => _prune());
      _maintenance = maintenance.then<void>((_) {}, onError: (Object _) {});
      await maintenance;
      return target;
    } on Object catch (error) {
      LocalMusicDiagnostics.record('artwork.cache_failed', {
        ...LocalMusicDiagnostics.artwork(url),
        'type': error.runtimeType.toString(),
      });
      return null;
    } finally {
      if (temporary != null) {
        try {
          if (await temporary.exists()) await temporary.delete();
        } on Object {
          // A failed temporary-cache cleanup is harmless and remains private.
        }
      }
    }
  }

  Future<File> _cacheFile(String key) async {
    await initialize();
    final root = _root;
    if (root == null) {
      throw const FileSystemException('Image cache unavailable');
    }
    return File('${root.path}${Platform.pathSeparator}$key.avatar');
  }

  String? _cacheFileKey({required String cacheKey, required String url}) {
    final owner = cacheKey.trim();
    final stableUrl = _stableUrl(url);
    if (owner.isEmpty || stableUrl == null) return null;
    return sha256.convert(utf8.encode('$owner\n$stableUrl')).toString();
  }

  String? _stableUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    // Preserve semantic identity and thumbnail size. Only known expiring
    // signatures are disposable; ?id=... and ?version=... remain distinct.
    final parameters = <String, String>{
      for (final entry in uri.queryParameters.entries)
        if (!{
              'token',
              'sign',
              'signature',
              'expires',
              'expire',
              'auth_key',
            }.contains(entry.key.toLowerCase()) &&
            !entry.key.toLowerCase().startsWith('x-amz-'))
          entry.key: entry.value,
    };
    final keys = parameters.keys.toList()..sort();
    return uri
        .replace(
          query: keys.isEmpty
              ? ''
              : Uri(
                  queryParameters: {
                    for (final key in keys) key: parameters[key]!,
                  },
                ).query,
          fragment: '',
        )
        .toString();
  }
}

final persistentNetworkImageCache = PersistentNetworkImageCache();
