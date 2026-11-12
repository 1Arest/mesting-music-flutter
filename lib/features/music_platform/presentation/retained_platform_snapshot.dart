import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../music_platform_providers.dart';
import '../domain/platform_session.dart';
import 'platform_display_snapshots.dart';
import '../../../shared/widgets/beta_entrance_readiness.dart';
import '../../../shared/widgets/beta_root_tab_viewport.dart';

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
    this.cacheKey,
    super.key,
  });

  final AsyncValue<T> value;
  final Widget Function() loading;
  final Widget Function(Object error, StackTrace stack) error;
  final Widget Function(T value) data;
  final Iterable<String> Function(T value)? artwork;

  /// Only stable, explicitly named page sections opt into cross-platform
  /// retention. Unnamed detail/search instances cannot overwrite one another.
  final String? cacheKey;

  @override
  ConsumerState<RetainedPlatformSnapshot<T>> createState() =>
      _RetainedPlatformSnapshotState<T>();
}

class _RetainedPlatformSnapshotState<T>
    extends ConsumerState<RetainedPlatformSnapshot<T>> {
  PlatformDisplayOwner? _owner;
  String? _slot;
  AsyncData<T>? _shown;
  T? _candidate;
  int _generation = 0;

  void _remember(T value) {
    final key = widget.cacheKey;
    if (key == null || value == null) return;
    ref
        .read(platformDisplaySnapshotsProvider)
        .remember(
          _owner!,
          key,
          value as Object,
          widget.artwork?.call(value) ?? const <String>[],
        );
  }

  PlatformDisplayOwner _identity(AsyncValue<PlatformSession?> account) {
    final session = account.value;
    // A refresh with the same retained credential is still the same owner.
    // Including isLoading discarded usable content during account revalidation
    // even though neither owner nor credential changed. Missing/new identities
    // still invalidate immediately, including logout and cross-platform users.
    return (session?.ownerId, session?.token);
  }

  Future<void> _prepare(
    T previous,
    T incoming,
    PlatformDisplayOwner owner,
    int generation,
  ) async {
    final artwork = widget.artwork!;
    bool ready;
    try {
      ready = await ref
          .read(platformDisplaySnapshotsProvider)
          .prepareReplacement(artwork(previous), artwork(incoming));
    } on Object {
      ready = false;
    }
    if (!mounted ||
        generation != _generation ||
        _owner != owner ||
        _identity(ref.read(platformAccountProvider)) != owner) {
      return;
    }
    if (ready) {
      _remember(incoming);
      setState(() => _shown = AsyncData(incoming));
    }
    // Keep the failed candidate's identity until a fresh provider response or
    // explicit retry arrives; rebuilding the parent must not loop downloads.
  }

  @override
  Widget build(BuildContext context) {
    final owner = _identity(ref.watch(platformAccountProvider));
    if (_owner != owner || _slot != widget.cacheKey) {
      _owner = owner;
      _slot = widget.cacheKey;
      final key = widget.cacheKey;
      final snapshots = ref.read(platformDisplaySnapshotsProvider);
      final restored = key == null ? null : snapshots.read<T>(owner, key);
      _shown = restored == null ? null : AsyncData(restored);
      if (key != null && restored != null) snapshots.seedArtwork(owner, key);
      _candidate = null;
      _generation++;
    }
    final value = widget.value;
    // A ready snapshot remains fully visible during root motion. Delay only
    // replacement decoding/uploads until its actual destination has settled;
    // hidden branches cannot compete with the foreground animation.
    final canPrepare =
        TickerMode.valuesOf(context).enabled &&
        BetaEntranceReadiness.of(context) &&
        BetaTabVisibility.settledOf(context);
    if (value.isLoading || value.hasError) {
      if (_candidate != null) {
        _candidate = null;
        _generation++;
      }
    } else if (value.hasValue) {
      final incoming = value.requireValue;
      if (_shown == null || widget.artwork == null) {
        _shown = AsyncData(incoming);
        _remember(incoming);
      } else if (!identical(_shown!.value, incoming) &&
          !identical(_candidate, incoming) &&
          canPrepare) {
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
