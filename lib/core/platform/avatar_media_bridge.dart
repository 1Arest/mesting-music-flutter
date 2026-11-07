import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const maxSavedAvatarBytes = 10 * 1024 * 1024;

class AvatarMediaException implements Exception {
  const AvatarMediaException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AvatarMediaData {
  const AvatarMediaData({
    required this.bytes,
    required this.mimeType,
    required this.extension,
  });

  final Uint8List bytes;
  final String mimeType;
  final String extension;
}

class AvatarMediaBridge {
  const AvatarMediaBridge._();

  static const channel = MethodChannel('com.mesting.music/media_library');

  static Future<AvatarMediaData> load(String source) async {
    final normalized = source.trim();
    if (normalized.isEmpty) {
      throw const AvatarMediaException('当前还没有可保存的头像');
    }

    late final Uint8List bytes;
    final uri = Uri.tryParse(normalized);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      late final http.Response response;
      try {
        response = await http.get(uri).timeout(const Duration(seconds: 20));
      } on Object {
        throw const AvatarMediaException('头像下载失败，请检查网络后重试');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const AvatarMediaException('头像下载失败，请稍后重试');
      }
      bytes = response.bodyBytes;
    } else {
      final file = uri?.scheme == 'file'
          ? File.fromUri(uri!)
          : File(normalized);
      if (!await file.exists()) {
        throw const AvatarMediaException('当前头像文件已失效，请重新更换头像');
      }
      bytes = await file.readAsBytes();
    }

    if (bytes.isEmpty) {
      throw const AvatarMediaException('当前头像文件为空，无法保存');
    }
    if (bytes.length > maxSavedAvatarBytes) {
      throw const AvatarMediaException('头像文件过大，暂时无法保存');
    }
    return _identifyAvatar(bytes);
  }

  static Future<String?> saveToGallery(AvatarMediaData image, {DateTime? now}) {
    final timestamp = (now ?? DateTime.now())
        .toLocal()
        .toIso8601String()
        .replaceAll(RegExp(r'[^0-9]'), '')
        .substring(0, 14);
    return channel.invokeMethod<String>('saveImage', {
      'bytes': image.bytes,
      'mimeType': image.mimeType,
      'fileName': 'mesting_avatar_$timestamp${image.extension}',
    });
  }
}

AvatarMediaData _identifyAvatar(Uint8List bytes) {
  if (_startsWith(bytes, const [0xFF, 0xD8, 0xFF])) {
    return AvatarMediaData(
      bytes: bytes,
      mimeType: 'image/jpeg',
      extension: '.jpg',
    );
  }
  if (_startsWith(bytes, const [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ])) {
    return AvatarMediaData(
      bytes: bytes,
      mimeType: 'image/png',
      extension: '.png',
    );
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
      String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP') {
    return AvatarMediaData(
      bytes: bytes,
      mimeType: 'image/webp',
      extension: '.webp',
    );
  }
  throw const AvatarMediaException('当前头像不是可保存的 JPG、PNG 或 WebP 图片');
}

bool _startsWith(List<int> value, List<int> prefix) {
  if (value.length < prefix.length) return false;
  for (var index = 0; index < prefix.length; index += 1) {
    if (value[index] != prefix[index]) return false;
  }
  return true;
}
