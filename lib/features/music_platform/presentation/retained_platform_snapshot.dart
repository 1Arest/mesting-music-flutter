import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/media/artwork_refresh_coordinator.dart';
import '../music_platform_providers.dart';
import '../domain/platform_session.dart';

/// A discovery section keeps its last usable, same-account data during a
/// refresh. This is a presentation fallback when disposable disk caching is
/// unavailable too; credentials, mutations and pagination stay with providers.
///
/// New covers are prepared through the existing shared coordinator before the
/// typed snapshot changes. Neither an image failure nor a failed request may
/// turn an already visible section into a loading/empty surface.
class RetainedPlatformSnapshot<T> extends ConsumerStatefulWidget {
  const RetainedPlatformSnapshot({
    required this.value,
    required this.loading,
    required this.error,
    required this.data,
    this.artwork,
    super.key,
  });

  final AsyncValue<T> value;
  final Widget Function() loading;
  final Widget Function(Object error, StackTrace stack) error;
  final Widget Function(T value) data;
  final Iterable<String> Function(T value)? artwork;

  @override
  ConsumerState<RetainedPlatformSnapshot<T>> createState() =>
      _RetainedPlatformSnapshotState<T>();
}

class _RetainedPlatformSnapshotState<T>
    extends ConsumerState<RetainedPlatformSnapshot<T>> {
  Object? _owner;
  AsyncData<T>? _shown;
  T? _candidate;
  int _generation = 0;

  Object _identity(AsyncValue<PlatformSession?> account) {
    final session = account.value;
    return (session?.ownerId, session?.token, account.isLoading);
  }

  Future<void> _prepare(
    T previous,
    T incoming,
    Object owner,
    int generation,
  ) async {
    final artwork = widget.artwork!;
    bool ready;
    try {
      ready = await artworkRefreshCoordinator.prepareRefresh(
        {'covers': artwork(previous).toList()},
        {'covers': artwork(incoming).toList()},
      );
    } on Object {
      ready = false;
    }
    if (!mounted ||
        generation != _generation ||
        _owner != owner ||
        _identity(ref.read(platformAccountProvider)) != owner) {
      return;
    }
    if (ready) setState(() => _shown = AsyncData(incoming));
    // Keep the failed candidate's identity until a fresh provider response or
    // explicit retry arrives; rebuilding the parent must not loop downloads.
  }

  @override
  Widget build(BuildContext context) {
    final owner = _identity(ref.watch(platformAccountProvider));
    if (_owner != owner) {
      _owner = owner;
      _shown = null;
      _candidate = null;
      _generation++;
    }
    final value = widget.value;
    if (value.isLoading || value.hasError) {
      if (_candidate != null) {
        _candidate = null;
        _generation++;
      }
    } else if (value.hasValue) {
      final incoming = value.requireValue;
      if (_shown == null || widget.artwork == null) {
        _shown = AsyncData(incoming);
      } else if (!identical(_shown!.value, incoming) &&
          !identical(_candidate, incoming)) {
        _candidate = incoming;
        unawaited(_prepare(_shown!.value, incoming, owner, ++_generation));
      }
    }
    if (_shown != null) return widget.data(_shown!.value);
    // Strip Riverpod's previous value on an identity reload. A former account
    // must never reappear through AsyncLoading/AsyncError.copyWithPrevious.
    if (value.isLoading) return widget.loading();
    if (value.hasError) return widget.error(value.error!, value.stackTrace!);
    return widget.loading();
  }
}
