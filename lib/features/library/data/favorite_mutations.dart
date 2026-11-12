import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../shared/models/track.dart';

/// Account-scoped, latest-intent synchronization for every favorite surface.
/// Icons change synchronously; a quiet window folds repeated taps, and a single
/// account-wide lane spaces actual writes. Successful receipts stay visible
/// until the collection index catches up. No upstream retry or cloud-list
/// reordering happens here; disposing an account cancels all unsent intentions.
class FavoriteMutations extends ChangeNotifier {
  FavoriteMutations({
    required this.write,
    required this.confirmed,
    this.quietWindow = const Duration(milliseconds: 500),
    this.minimumWriteInterval = const Duration(seconds: 2),
  });
  final Future<void> Function(Track track, bool favorite) write;
  final Set<String> Function() confirmed;
  final Duration quietWindow, minimumWriteInterval;
  final Map<String, bool> _values = {};
  final Map<String, _FavoriteIntent> _intents = {};
  _FavoriteIntent? _active;
  Timer? _spacing;
  bool _closed = false;

  Set<String> apply(Set<String> ids) {
    final result = {...ids};
    for (final entry in _values.entries) {
      entry.value ? result.add(entry.key) : result.remove(entry.key);
    }
    return result;
  }

  /// Only the newest tap receives a completion notice. Superseded/cancelled
  /// taps complete with null, avoiding stale success HUDs over a newer choice.
  Future<bool?> toggle(Track track, {required bool wasFavorite}) {
    if (_closed) return Future.value(null);
    final current = _values[track.id] ?? wasFavorite;
    final intent = _intents.putIfAbsent(
      track.id,
      () => _FavoriteIntent(track, current),
    );
    intent.completion?.complete(null);
    final completion = intent.completion = Completer<bool?>();
    intent.desired = !current;
    _values[track.id] = intent.desired;
    intent.quiet?.cancel();
    intent.ready = false;
    intent.quiet = Timer(quietWindow, () {
      intent.quiet = null;
      intent.ready = true;
      _drain();
    });
    notifyListeners();
    return completion.future;
  }

  void _drain() {
    if (_closed || _active != null || _spacing != null) return;
    for (final intent in _intents.values.toList()) {
      if (!intent.ready) continue;
      if (intent.desired == intent.acknowledged) {
        // An even number of taps can cancel without any platform request.
        _settle(intent);
        continue;
      }
      _active = intent;
      intent.ready = false;
      if (minimumWriteInterval > Duration.zero) {
        _spacing = Timer(minimumWriteInterval, () {
          _spacing = null;
          _drain();
        });
      }
      unawaited(_commit(intent, intent.desired));
      return;
    }
  }

  Future<void> _commit(_FavoriteIntent intent, bool submitted) async {
    try {
      await write(intent.track, submitted);
      if (_closed) return;
      intent.acknowledged = submitted;
      intent.changedRemote = true;
      _active = null;
      if (intent.quiet == null) {
        if (intent.desired == submitted) {
          _settle(intent);
        } else {
          // A newer choice arrived during the request. Publish no stale HUD;
          // it follows through this same lane after its quiet/spacing gates.
          intent.ready = true;
        }
      }
      _drain();
    } catch (error, stack) {
      if (_closed) return;
      // A refusal/uncertain write ends this batch. Never automatically replay
      // either it or a queued operation into a possible platform restriction.
      final ids = confirmed();
      final cancelled = _intents.values.toList();
      _intents.clear();
      _active = null;
      for (final pending in cancelled) {
        pending.quiet?.cancel();
        if (ids.contains(pending.track.id) == pending.acknowledged) {
          _values.remove(pending.track.id);
        } else {
          _values[pending.track.id] = pending.acknowledged;
        }
        if (identical(pending, intent)) {
          pending.completion?.completeError(error, stack);
        } else {
          pending.completion?.complete(null);
        }
      }
      notifyListeners();
    }
  }

  void _settle(_FavoriteIntent intent) {
    _intents.remove(intent.track.id);
    _values[intent.track.id] = intent.acknowledged;
    intent.completion?.complete(
      intent.changedRemote ? intent.acknowledged : null,
    );
    reconcile(confirmed());
  }

  void reconcile(Set<String> ids) {
    if (_closed) return;
    final before = _values.length;
    _values.removeWhere(
      (id, next) => !_intents.containsKey(id) && ids.contains(id) == next,
    );
    if (before != _values.length) notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _spacing?.cancel();
    for (final intent in _intents.values) {
      intent.quiet?.cancel();
      intent.completion?.complete(null);
    }
    _intents.clear();
    super.dispose();
  }
}

class _FavoriteIntent {
  _FavoriteIntent(this.track, this.acknowledged) : desired = acknowledged;
  final Track track;
  bool acknowledged, desired;
  bool ready = false, changedRemote = false;
  Timer? quiet;
  Completer<bool?>? completion;
}
