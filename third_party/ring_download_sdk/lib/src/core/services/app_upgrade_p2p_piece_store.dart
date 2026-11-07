import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'app_upgrade_p2p_protocol.dart';

/// A single writer owns the contiguous download prefix. HTTPS can continue at
/// its exact length; only whole, SHA-verified pieces are advertised to peers.
class AppUpgradeP2PPieceStore {
  AppUpgradeP2PPieceStore(
    this.file,
    this.manifest, {
    this.bufferedWrites = false,
  });
  final File file;
  final AppUpgradeP2PManifest manifest;
  // The receive task exclusively owns this writer. Readers/sharing stores keep
  // the original short-lived handles; no wire-protocol or window change.
  final bool bufferedWrites;
  final Set<int> verifiedPieces = {};
  RandomAccessFile? _writer;
  int _unflushedBytes = 0;
  final Stopwatch _sinceFlush = Stopwatch();
  final _metrics = <String, int>{};
  // Only this store can issue receipts, for private copies which are exposed
  // through read-only typed-data views. Weak keys do not retain old payloads.
  final _verifiedPayloads = Expando<_VerifiedPayload>();
  Map<String, int> get metrics => Map.unmodifiable(_metrics);

  void _add(String key, int value) =>
      _metrics.update(key, (old) => old + value, ifAbsent: () => value);

  bool validPiece(int index, Uint8List bytes) {
    final size = manifest.pieceSize(index);
    final receipt = _verifiedPayloads[bytes];
    if (size > 0 &&
        receipt != null &&
        receipt.index == index &&
        receipt.length == size &&
        receipt.sha256 == manifest.pieceHashes[index]) {
      _add('piece_verify_reused', 1);
      return true;
    }
    final watch = Stopwatch()..start();
    final valid =
        manifest.pieceSize(index) > 0 &&
        bytes.length == manifest.pieceSize(index) &&
        sha256.convert(bytes).toString() == manifest.pieceHashes[index];
    _add('piece_verify_us', watch.elapsedMicroseconds);
    _add('piece_verify_calls', 1);
    return valid;
  }

  /// Transfer ownership after one SHA check. The caller's original bytes may
  /// still change; neither that alias nor a view's buffer can mutate this copy.
  Uint8List verifyOwnedPiece(int index, Uint8List bytes) {
    if (manifest.pieceSize(index) <= 0 ||
        bytes.length != manifest.pieceSize(index)) {
      throw const AppUpgradeP2PFailure('piece_checksum_mismatch');
    }
    final owned = Uint8List.fromList(bytes);
    if (!validPiece(index, owned)) {
      throw const AppUpgradeP2PFailure('piece_checksum_mismatch');
    }
    final frozen = owned.asUnmodifiableView();
    _verifiedPayloads[frozen] = _VerifiedPayload(
      index,
      manifest.pieceHashes[index],
      owned.length,
    );
    return frozen;
  }

  /// Receiving may repair a prefix; sharing must inspect without altering it.
  Future<int> verifyPrefix({bool repairInvalid = true}) async {
    await close();
    verifiedPieces.clear();
    if (!file.existsSync()) return 0;
    var length = await file.length();
    if (length > manifest.fileSize) {
      if (repairInvalid) await _truncate(0);
      return 0;
    }
    for (var index = 0; index < manifest.pieceHashes.length; index++) {
      final start = index * AppUpgradeP2PManifest.chunkSize;
      final end = start + manifest.pieceSize(index);
      if (end > length) break; // Keep partial HTTPS tail, but never share it.
      final digest = await sha256.bind(file.openRead(start, end)).first;
      if (digest.toString() != manifest.pieceHashes[index]) {
        if (repairInvalid) await _truncate(start);
        length = start;
        break;
      }
      verifiedPieces.add(index);
    }
    return length;
  }

  Future<void> append(int offset, int index, Uint8List bytes) async {
    if (_verifiedPayloads[bytes] == null) {
      bytes = verifyOwnedPiece(index, bytes);
    }
    if (!validPiece(index, bytes)) {
      throw const AppUpgradeP2PFailure('piece_checksum_mismatch');
    }
    final length = file.existsSync() ? await file.length() : 0;
    if (length != offset || offset != index * AppUpgradeP2PManifest.chunkSize) {
      throw const AppUpgradeP2PFailure('prefix_changed');
    }
    final handle = _writer ?? await file.open(mode: FileMode.append);
    if (_writer == null) {
      _add('piece_open_count', 1);
      if (bufferedWrites) {
        _writer = handle;
        _sinceFlush
          ..reset()
          ..start();
      }
    }
    try {
      final watch = Stopwatch()..start();
      await handle.writeFrom(bytes);
      _add('piece_write_us', watch.elapsedMicroseconds);
      _add('piece_write_calls', 1);
      _add('persisted_bytes', bytes.length);
      _unflushedBytes += bytes.length;
      // Checkpoints bound explicit flush work to 4 MiB or the first piece
      // boundary after one second. Cancellation/fallback/final SHA always close.
      if (!bufferedWrites ||
          _unflushedBytes >= 4 * 1024 * 1024 ||
          _sinceFlush.elapsedMilliseconds >= 1000) {
        await _flush(handle);
      }
      verifiedPieces.add(index);
    } finally {
      if (!bufferedWrites) await handle.close();
    }
  }

  Future<void> _flush(RandomAccessFile handle) async {
    if (_unflushedBytes == 0) return;
    final watch = Stopwatch()..start();
    await handle.flush();
    _add('piece_flush_us', watch.elapsedMicroseconds);
    _add('piece_flush_calls', 1);
    _unflushedBytes = 0;
    _sinceFlush
      ..reset()
      ..start();
  }

  /// Await before returning file ownership to HTTPS, renaming, or hashing.
  /// Recovery still rehashes the actual prefix after an abrupt process death.
  Future<void> close() async {
    final handle = _writer;
    _writer = null;
    if (handle == null) return;
    try {
      await _flush(handle);
    } finally {
      _sinceFlush.stop();
      await handle.close();
    }
  }

  Future<Uint8List> readVerified(int index) async {
    if (!verifiedPieces.contains(index)) {
      throw const AppUpgradeP2PFailure('piece_unavailable');
    }
    final start = index * AppUpgradeP2PManifest.chunkSize;
    final buffer = BytesBuilder(copy: false);
    await for (final frame in file.openRead(
      start,
      start + manifest.pieceSize(index),
    )) {
      buffer.add(frame);
    }
    final bytes = buffer.takeBytes();
    if (!validPiece(index, bytes)) {
      verifiedPieces.remove(index);
      throw const AppUpgradeP2PFailure('piece_checksum_mismatch');
    }
    return bytes;
  }

  Future<bool> completeAndVerified() async {
    await close();
    if (!file.existsSync() || await file.length() != manifest.fileSize) {
      return false;
    }
    final watch = Stopwatch()..start();
    final digest = await sha256.bind(file.openRead()).first;
    _add('full_sha_us', watch.elapsedMicroseconds);
    _add('full_sha_scans', 1);
    return digest.toString() == manifest.sha256;
  }

  Future<void> _truncate(int length) async {
    await close();
    final handle = await file.open(mode: FileMode.append);
    try {
      await handle.truncate(length);
      await handle.flush();
    } finally {
      await handle.close();
    }
  }
}

class _VerifiedPayload {
  const _VerifiedPayload(this.index, this.sha256, this.length);
  final int index, length;
  final String sha256;
}
