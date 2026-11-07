import 'dart:io';

const maxAvatarBytes = 5 * 1024 * 1024;

class ValidatedAvatarImage {
  const ValidatedAvatarImage({
    required this.file,
    required this.extension,
    required this.mimeType,
    required this.length,
  });

  final File file;
  final String extension;
  final String mimeType;
  final int length;
}

class AvatarValidationException implements Exception {
  const AvatarValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<ValidatedAvatarImage> validateAvatarImage(
  String path, {
  int maxBytes = maxAvatarBytes,
}) async {
  final file = File(path);
  if (!await file.exists()) {
    throw const AvatarValidationException('选择的头像文件已不存在，请重新选择');
  }
  final length = await file.length();
  if (length <= 0) {
    throw const AvatarValidationException('头像文件为空，请重新选择');
  }
  if (length > maxBytes) {
    throw const AvatarValidationException('头像不能超过 5 MB');
  }

  final input = await file.open();
  late final List<int> header;
  try {
    header = await input.read(12);
  } finally {
    await input.close();
  }

  if (_startsWith(header, const [0xFF, 0xD8, 0xFF])) {
    return ValidatedAvatarImage(
      file: file,
      extension: '.jpg',
      mimeType: 'image/jpeg',
      length: length,
    );
  }
  if (_startsWith(header, const [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ])) {
    return ValidatedAvatarImage(
      file: file,
      extension: '.png',
      mimeType: 'image/png',
      length: length,
    );
  }
  if (header.length >= 12 &&
      String.fromCharCodes(header.take(4)) == 'RIFF' &&
      String.fromCharCodes(header.skip(8).take(4)) == 'WEBP') {
    return ValidatedAvatarImage(
      file: file,
      extension: '.webp',
      mimeType: 'image/webp',
      length: length,
    );
  }
  throw const AvatarValidationException('仅支持真实的 JPG、PNG 或 WebP 图片');
}

bool _startsWith(List<int> value, List<int> prefix) {
  if (value.length < prefix.length) return false;
  for (var index = 0; index < prefix.length; index += 1) {
    if (value[index] != prefix[index]) return false;
  }
  return true;
}
