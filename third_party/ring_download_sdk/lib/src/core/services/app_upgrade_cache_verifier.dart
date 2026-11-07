import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'app_upgrade_p2p_protocol.dart';

/// One receipt per SDK owner. Only an unchanged file and exactly the same full
/// and piece identities may reuse it; each outgoing piece is still rehashed.
class AppUpgradeCacheVerifier {
  String? _receipt;
  Future<void>? _flight;
  int scans = 0, reused = 0;

  Future<void> verify(File file, AppUpgradeP2PManifest manifest) {
    final previous = _flight;
    late final Future<void> flight;
    flight =
        () async {
          try {
            await previous;
          } catch (_) {}
          await _verify(file, manifest);
        }().whenComplete(() {
          if (identical(_flight, flight)) _flight = null;
        });
    _flight = flight;
    return flight;
  }

  Future<void> _verify(File file, AppUpgradeP2PManifest manifest) async {
    final filePath = file.absolute.path;
    final identity =
        '${manifest.sha256}|${manifest.fileSize}|'
        '${manifest.pieceHashes.join(',')}';
    final before = await _stamp(filePath);
    if (before == null) {
      throw const AppUpgradeP2PFailure('file_checksum_mismatch');
    }
    final receipt = '$filePath|$identity|$before';
    if (_receipt == receipt) {
      reused++;
      return;
    }
    _receipt = null;
    scans++;
    final hashes = manifest.pieceHashes.toList(growable: false);
    final size = manifest.fileSize;
    final sha = manifest.sha256;
    // Capture plain values, never an RTC/HTTP/session owner, across isolates.
    final result = await _runVerification(filePath, size, sha, hashes);
    if (result != 'ok') throw AppUpgradeP2PFailure(result);
    if (await _stamp(filePath) != before) {
      throw const AppUpgradeP2PFailure('file_checksum_mismatch');
    }
    _receipt = receipt;
  }

  static Future<String?> _stamp(String path) async {
    final stat = await File(path).stat();
    if (stat.type != FileSystemEntityType.file) return null;
    return '${stat.size}|${stat.modified.microsecondsSinceEpoch}|'
        '${stat.changed.microsecondsSinceEpoch}|${stat.mode}';
  }
}

Future<String> _runVerification(
  String path,
  int size,
  String sha,
  List<String> hashes,
) => Isolate.run(() => _verifyFile(path, size, sha, hashes));

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

Future<String> _verifyFile(
  String path,
  int size,
  String sha,
  List<String> hashes,
) async {
  final file = File(path);
  if (await file.length() != size) return 'file_checksum_mismatch';
  final fullDigest = _DigestSink();
  final full = sha256.startChunkedConversion(fullDigest);
  final handle = await file.open();
  var piecesMatch = true, total = 0;
  try {
    for (var index = 0; index < hashes.length; index++) {
      final length = (size - total).clamp(0, AppUpgradeP2PManifest.chunkSize);
      final bytes = await handle.read(length);
      total += bytes.length;
      full.add(bytes);
      if (bytes.length != length ||
          sha256.convert(bytes).toString() != hashes[index]) {
        piecesMatch = false;
      }
    }
    full.close();
    if (total != size || fullDigest.value.toString() != sha) {
      return 'file_checksum_mismatch';
    }
    return piecesMatch ? 'ok' : 'piece_checksum_mismatch';
  } finally {
    await handle.close();
  }
}
