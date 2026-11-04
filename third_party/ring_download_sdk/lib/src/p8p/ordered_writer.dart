import 'dart:async';
import 'dart:typed_data';

import '../core/services/app_upgrade_p2p_piece_store.dart';
import '../core/services/app_upgrade_p2p_protocol.dart';
import 'leases.dart';

/// Owns verified buffers and the existing contiguous prefix store.
class P8POrderedWriter {
  P8POrderedWriter._(this.book, this.store);

  /// Requires exclusive file ownership, after stopping any HTTPS writer.
  static Future<P8POrderedWriter> open(
    P8PLeaseBook book,
    AppUpgradeP2PPieceStore store, {
    bool paused = false,
    Future<void> Function(P8PLease)? beforeWrite,
    void Function(P8PLease)? onPersisted,
  }) async {
    if (book.fileBytes != store.manifest.fileSize ||
        book.fileSha256 != store.manifest.sha256 ||
        book.pieceBytes != AppUpgradeP2PManifest.chunkSize ||
        book.pieceCount != store.manifest.pieceHashes.length) {
      throw ArgumentError('P8P writer content dimensions differ');
    }
    final prefix = await store.verifyPrefix();
    if (book.closed || prefix != book.persistedBytes) {
      throw const AppUpgradeP2PFailure('prefix_changed');
    }
    return P8POrderedWriter._(book, store)
      .._paused = paused
      .._beforeWrite = beforeWrite
      .._onPersisted = onPersisted;
  }

  final P8PLeaseBook book;
  final AppUpgradeP2PPieceStore store;
  final _buffers = <int, Uint8List>{};
  Future<void> _idle = Future<void>.value();
  bool _draining = false;
  Future<void>? _closing;
  Object? _failure;
  StackTrace? _failureStack;
  bool _paused = false;
  Future<void> Function(P8PLease)? _beforeWrite;
  void Function(P8PLease)? _onPersisted;

  int get bufferedPieces => _buffers.length;

  /// Reject stale ownership before allocating or hashing. Copy+hash once into
  /// the store's immutable receipt; the writer can then reuse that receipt.
  bool submit(P8PLease lease, Uint8List bytes) {
    if (_closing != null || !book.accepts(lease)) return false;
    final owned = store.verifyOwnedPiece(lease.index, bytes);
    if (!book.verified(lease)) return false;
    _buffers[lease.index] = owned;
    _kick();
    return true;
  }

  void resume() {
    _paused = false;
    _kick();
  }

  void _kick() {
    if (!_paused && !_draining && _closing == null && !book.closed) {
      _draining = true;
      _idle = _drain();
      // An asynchronous disk error must remain observable without becoming an
      // unhandled error if the transport is still waiting for another piece.
      unawaited(_idle.then<void>((_) {}, onError: (Object _) {}));
    }
  }

  Future<void> get idle async {
    await _idle;
    if (_failure != null) {
      Error.throwWithStackTrace(_failure!, _failureStack!);
    }
  }

  Future<void> _drain() async {
    P8PWrite? activeWrite;
    try {
      while (_closing == null) {
        final write = book.beginWrite();
        if (write == null) {
          if (book.closed) {
            _buffers.clear();
            await store.close();
          }
          break;
        }
        activeWrite = write;
        final bytes = _buffers[write.index];
        if (bytes == null) throw StateError('P8P verified buffer missing');
        await _beforeWrite?.call(write.lease);
        await store.append(
          write.index * AppUpgradeP2PManifest.chunkSize,
          write.index,
          bytes,
        );
        book.persisted(write);
        activeWrite = null;
        _buffers.remove(write.index);
        _onPersisted?.call(write.lease);
      }
    } catch (error, stack) {
      _failure = error;
      _failureStack = stack;
      if (activeWrite != null) book.writeFailed(activeWrite);
      book.close();
      _buffers.clear();
      rethrow;
    } finally {
      _draining = false;
    }
  }

  /// Does not acknowledge network cancellations: adapters must quiesce their
  /// own requests. Await this before handing the same file to another writer.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    book.close();
    try {
      await idle;
    } finally {
      _buffers.clear();
      await store.close();
    }
  }
}
