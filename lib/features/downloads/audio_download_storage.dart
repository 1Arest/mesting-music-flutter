import 'dart:io';
import 'package:flutter/services.dart';
import '../../shared/models/track.dart';

/// The queue owns metadata; this adapter owns persisted Android directory
/// grants, export and navigation. Downloading never imports local music.
class AudioDownloadStorage {
  const AudioDownloadStorage();
  static const channel = MethodChannel('com.mesting.music/audio_download');
  Future<String?> directory({bool choose = false}) =>
      channel.invokeMethod<String>(choose ? 'chooseDirectory' : 'directory');
  Future<String?> ensureDirectory() async =>
      await directory() ?? await directory(choose: true);
  Future<String> publish(
    File file,
    Track track,
    String extension,
    String mime,
  ) async {
    final uri = await channel.invokeMethod<String>('publish', {
      'path': file.path,
      'name': '${track.title} - ${track.artist}.$extension',
      'mime': mime,
    });
    if (uri == null || uri.isEmpty) throw const FileSystemException('歌曲未保存');
    return uri;
  }

  Future<bool> readable(String uri) async =>
      await channel.invokeMethod<bool>('readable', {'uri': uri}) ?? false;
  Future<void> openDirectory({String? uri}) async {
    try {
      await channel.invokeMethod<void>('openDirectory', {'uri': uri});
    } on PlatformException catch (error) {
      // These are device file operations, independent of the music network.
      throw DownloadStorageException(error.message ?? '无法打开保存位置，请检查文件夹授权');
    }
  }

  Future<void> export(String uri, Track track) => channel.invokeMethod<void>(
    'export',
    {'uri': uri, 'name': '${track.title} - ${track.artist}'},
  );
}

class DownloadStorageException implements Exception {
  const DownloadStorageException(this.message);
  final String message;
}
