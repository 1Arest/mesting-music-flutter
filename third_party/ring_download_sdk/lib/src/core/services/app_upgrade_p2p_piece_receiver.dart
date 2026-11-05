import 'dart:async';
import '../../p8p/window.dart';
import 'dart:typed_data';

import 'app_upgrade_p2p_piece_store.dart';
import 'app_upgrade_p2p_protocol.dart';

/// One outstanding piece per channel. No bytes become visible until framing,
/// exact length and the manifest's per-piece SHA-256 all agree.
class AppUpgradeP2PPieceReceiver {
  AppUpgradeP2PPieceReceiver(this.store, this.index);
  final AppUpgradeP2PPieceStore store;
  final int index;
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  bool _started = false;
  bool _ended = false;
  int _received = 0;

  void start(Map<String, dynamic> message) {
    if (_started ||
        _ended ||
        message['index'] != index ||
        message['size'] != store.manifest.pieceSize(index)) {
      throw const AppUpgradeP2PFailure('invalid_piece_header');
    }
    _started = true;
  }

  void add(Uint8List frame) {
    if (!_started ||
        _ended ||
        frame.isEmpty ||
        frame.length > AppUpgradeP2PManifest.maxFrameBytes ||
        _received + frame.length > store.manifest.pieceSize(index)) {
      throw const AppUpgradeP2PFailure('invalid_piece_frame');
    }
    _received += frame.length;
    _buffer.add(frame);
  }

  Uint8List end(Map<String, dynamic> message) {
    if (!_started ||
        _ended ||
        message['index'] != index ||
        _received != store.manifest.pieceSize(index)) {
      throw const AppUpgradeP2PFailure('piece_length_mismatch');
    }
    _ended = true;
    return store.verifyOwnedPiece(index, _buffer.takeBytes());
  }
}

/// The existing wire protocol sends batch pieces in order. Bound retained
/// payloads to four pieces and apply the same framing and SHA checks to each.
class AppUpgradeP2PBatchReceiver {
  AppUpgradeP2PBatchReceiver(
    this.store,
    List<int> indices, {
    this.onPieceVerified,
    int maxPieces = 4,
  }) : indices = List<int>.unmodifiable(indices) {
    if (indices.isEmpty ||
        maxPieces < 1 ||
        maxPieces > 6 ||
        indices.length > maxPieces ||
        indices.toSet().length != indices.length ||
        indices.any((index) => store.manifest.pieceSize(index) <= 0)) {
      throw const AppUpgradeP2PFailure('invalid_request');
    }
    _receiver = AppUpgradeP2PPieceReceiver(store, indices.first);
  }
  final AppUpgradeP2PPieceStore store;
  final List<int> indices;
  final void Function()? onPieceVerified;
  final completed = Completer<List<Uint8List>>();
  final _pieces = <Uint8List>[];
  late AppUpgradeP2PPieceReceiver _receiver;

  void start(Map<String, dynamic> message) {
    _checkPending();
    _receiver.start(message);
  }

  void add(Uint8List bytes) {
    _checkPending();
    _receiver.add(bytes);
  }

  void end(Map<String, dynamic> message) {
    _checkPending();
    _pieces.add(_receiver.end(message));
    onPieceVerified?.call();
    if (_pieces.length == indices.length) {
      completed.complete(List<Uint8List>.unmodifiable(_pieces));
    } else {
      _receiver = AppUpgradeP2PPieceReceiver(store, indices[_pieces.length]);
    }
  }

  void fail(Object error) {
    if (!completed.isCompleted) completed.completeError(error);
  }

  void _checkPending() {
    if (completed.isCompleted) {
      throw const AppUpgradeP2PFailure('unexpected_control');
    }
  }
}

/// A negotiated four-piece sliding window. Ready payloads count towards the
/// limit too. The consumer replenishes only after persisting the previous piece.
class AppUpgradeP2PWindowReceiver {
  AppUpgradeP2PWindowReceiver(
    this.store,
    this.indices,
    this.request, {
    this.controller,
    this.onWindowChanged,
  });
  final P8PWindowController? controller;
  final void Function(int)? onWindowChanged;
  final _consumerWatch = Stopwatch();
  int _lastWaitMicros = 0;
  final AppUpgradeP2PPieceStore store;
  final List<int> indices;
  final Future<void> Function(List<int>) request;
  final _pending = <int, Completer<Uint8List>>{};
  final _wire = <int>[];
  AppUpgradeP2PPieceReceiver? _receiver;
  int _requested = 0, _consumed = 0;
  Object? _failure;

  Future<Uint8List> take(int index, Duration timeout) async {
    if (_failure != null) throw _failure!;
    if (_consumed >= indices.length || indices[_consumed] != index) {
      throw const AppUpgradeP2PFailure('invalid_piece');
    }
    final policy = controller;
    if (policy != null && _consumerWatch.isRunning) {
      final before = policy.window;
      policy.observe(
        waitMicros: _lastWaitMicros,
        consumeMicros: _consumerWatch.elapsedMicroseconds,
        readyPieces: _pending.values.where((piece) => piece.isCompleted).length,
      );
      if (before != policy.window) {
        try {
          onWindowChanged?.call(policy.window);
        } catch (_) {}
      }
    }
    final wait = Stopwatch()..start();
    final added = <int>[];
    while (_pending.length < (policy?.window ?? 4) &&
        _requested < indices.length) {
      final next = indices[_requested++];
      final done = Completer<Uint8List>();
      // A channel error can fail later pieces before the consumer asks for them.
      unawaited(done.future.then<void>((_) {}, onError: (Object _) {}));
      _pending[next] = done;
      _wire.add(next);
      added.add(next);
    }
    try {
      if (added.isNotEmpty) await request(added);
      final bytes = await _pending[index]!.future.timeout(
        timeout,
        onTimeout: () =>
            throw const AppUpgradeP2PFailure('peer_transfer_timeout'),
      );
      if (_failure != null) throw _failure!;
      _pending.remove(index);
      _consumed++;
      _lastWaitMicros = wait.elapsedMicroseconds;
      _consumerWatch
        ..reset()
        ..start();
      return bytes;
    } catch (error) {
      fail(error);
      rethrow;
    }
  }

  void start(Map<String, dynamic> message) {
    if (_failure != null) throw _failure!;
    if (_wire.isEmpty || _receiver != null) {
      throw const AppUpgradeP2PFailure('unexpected_control');
    }
    _receiver = AppUpgradeP2PPieceReceiver(store, _wire.first)..start(message);
  }

  void add(Uint8List bytes) {
    if (_receiver == null) {
      throw const AppUpgradeP2PFailure('unexpected_binary');
    }
    _receiver!.add(bytes);
  }

  void end(Map<String, dynamic> message) {
    if (_receiver == null || _wire.isEmpty) {
      throw const AppUpgradeP2PFailure('unexpected_control');
    }
    final bytes = _receiver!.end(message);
    _receiver = null;
    _pending[_wire.removeAt(0)]!.complete(bytes);
  }

  void fail(Object error) {
    _failure ??= error;
    for (final done in _pending.values) {
      if (!done.isCompleted) done.completeError(error);
    }
  }
}
