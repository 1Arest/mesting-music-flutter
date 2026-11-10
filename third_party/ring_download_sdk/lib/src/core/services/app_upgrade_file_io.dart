import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'app_upgrade_native_hash.dart';

/// Always scans the current file. Android app-private files may use the native
/// worker; unsupported paths/platforms retain the original isolated Dart scan.
/// Callers retain their independent size/digest and installation-time checks.
Future<String> appUpgradeFileSha256(
  String filePath, {
  Future<Object?>? cancelSignal,
}) async {
  var cancelled = false;
  cancelSignal?.then<void>((_) {
    cancelled = true;
  }, onError: (Object _) {});
  if (cancelSignal != null) await Future<void>.value();
  if (cancelled) throw const FileSystemException('file_hash_cancelled');
  if (Platform.isAndroid) {
    final native = await const AppUpgradeNativeFileHash().tryHash(
      filePath,
      expectedBytes: await File(filePath).length(),
      cancelSignal: cancelSignal,
    );
    if (cancelled) throw const FileSystemException('file_hash_cancelled');
    if (native != null) return native;
  }
  if (cancelled) throw const FileSystemException('file_hash_cancelled');
  final digest = await _dartFileSha256(filePath);
  if (cancelled) throw const FileSystemException('file_hash_cancelled');
  return digest;
}

// Keep this closure independent of channel/cancellation state in its caller.
Future<String> _dartFileSha256(String filePath) => Isolate.run(
  () async => (await sha256.bind(File(filePath).openRead()).first).toString(),
  debugName: 'app-upgrade-sha256',
);

/// Transfers a task-owned HTTPS file after both download writers have stopped.
/// A rename preserves the exact file that was hashed. If a filesystem rejects
/// rename, preserve the existing copy fallback, but require a new destination
/// hash: copying never transfers a verification result.
Future<bool> promoteAppUpgradeHttpsFile(File source, File destination) async {
  try {
    await source.rename(destination.path);
    return true;
  } on FileSystemException {
    await source.copy(destination.path);
    return false;
  }
}
