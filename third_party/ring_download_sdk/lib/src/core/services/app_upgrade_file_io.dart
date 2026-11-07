import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

/// Always reads the current file. Only its path crosses the isolate boundary;
/// neither APK bytes nor caller state (Dio, channels, open handles) are sent.
/// Callers retain their size checks, failure policy and installation-time scan.
Future<String> appUpgradeFileSha256(String filePath) => Isolate.run(
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
