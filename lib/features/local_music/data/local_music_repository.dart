import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../../../core/performance/background_json.dart';
import '../domain/local_music.dart';

LocalMusicLibrary _parseLocalMusicSnapshot(Map<Object?, Object?> snapshot) =>
    LocalMusicLibrary.fromMap(snapshot);

/// Native scanning already has its own worker. Its detached channel snapshot
/// must also leave the UI isolate before Dart validation, sorting and grouping.
/// Only codec-safe map values cross the boundary, never the channel or grants.
Future<LocalMusicLibrary> decodeLocalMusicLibrarySnapshot(
  Map<Object?, Object?> snapshot,
) => largeJsonValue(snapshot)
    ? compute(
        _parseLocalMusicSnapshot,
        snapshot,
        debugLabel: 'local-music-index',
      )
    : Future.value(_parseLocalMusicSnapshot(snapshot));

class LocalMusicException implements Exception {
  const LocalMusicException(this.message, {this.code = ''});
  final String message, code;
  @override
  String toString() => message;
}

/// The bridge owns MediaStore/SAF grants and its atomic, device-local index.
/// Flutter never receives broad storage paths or copies this library to cloud.
abstract class LocalMusicRepository {
  Future<LocalMusicLibrary> load();
  Future<LocalMusicLibrary> scan();
  Future<LocalMusicLibrary> importFiles();
  Future<LocalMusicLibrary> importDirectory();
  Future<LocalMusicLibrary> refresh();
  Future<LocalMusicLibrary> remove(String id);
  Future<LocalMusicEntry> prepare(LocalMusicEntry entry);
  Future<String> artwork(String id);
  Future<void> openSettings();
}

class AndroidLocalMusicRepository implements LocalMusicRepository {
  const AndroidLocalMusicRepository({
    MethodChannel channel = const MethodChannel(
      'com.mesting.music/local_music',
    ),
  }) : _channel = channel;
  final MethodChannel _channel;

  Future<T?> _invoke<T>(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      throw const LocalMusicException('本地音乐需要 Android 设备支持');
    } on PlatformException catch (error) {
      throw LocalMusicException(
        error.message ?? '本地音乐操作未完成，请重试',
        code: error.code,
      );
    }
  }

  Future<LocalMusicLibrary> _library(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    final data = await _invoke<Map<Object?, Object?>>(method, arguments);
    if (data == null) {
      throw const LocalMusicException('本地音乐索引暂时无法读取，请重试');
    }
    return decodeLocalMusicLibrarySnapshot(data);
  }

  @override
  Future<LocalMusicLibrary> load() => _library('load');
  @override
  Future<LocalMusicLibrary> scan() => _library('scan');
  @override
  Future<LocalMusicLibrary> importFiles() => _library('importFiles');
  @override
  Future<LocalMusicLibrary> importDirectory() => _library('importDirectory');
  @override
  Future<LocalMusicLibrary> refresh() => _library('refresh');
  @override
  Future<LocalMusicLibrary> remove(String id) => _library('remove', {'id': id});
  @override
  Future<LocalMusicEntry> prepare(LocalMusicEntry entry) async {
    final data = await _invoke<Map<Object?, Object?>>('prepare', {
      'id': entry.id,
    });
    if (data == null) {
      throw const LocalMusicException('这个文件已不可用，请重新导入');
    }
    return LocalMusicEntry.fromMap(data);
  }

  @override
  Future<String> artwork(String id) async =>
      await _invoke<String>('artwork', {'id': id}) ?? '';
  @override
  Future<void> openSettings() async => _invoke<void>('openSettings');
}
