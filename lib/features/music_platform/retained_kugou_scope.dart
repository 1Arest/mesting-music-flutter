import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/music_http_client.dart';

import 'data/music_platform_api.dart';
import 'domain/platform_session.dart';
import 'music_platform_providers.dart';

/// Read the retained login independently of the selected music platform. Storage
/// failures remain visible to callers; they never erase the encrypted login.
final savedKugouSessionProvider = FutureProvider<PlatformSession?>(
  (ref) => ref
      .watch(platformSessionStoreProvider)
      .read()
      .timeout(const Duration(seconds: 5)),
  retry: (_, _) => null,
);

/// Durable store mutations publish to this cell before waiting for audio or
/// navigation transitions. It closes the gap where the selected account still
/// describes an old credential whose encrypted bytes were already replaced.
final retainedKugouMutationProvider =
    NotifierProvider<
      RetainedKugouMutation,
      ({bool known, PlatformSession? session})
    >(RetainedKugouMutation.new);

class RetainedKugouMutation
    extends Notifier<({bool known, PlatformSession? session})> {
  @override
  ({bool known, PlatformSession? session}) build() =>
      (known: false, session: null);
  void publish(PlatformSession? session) =>
      state = (known: true, session: session);
}

/// Independent of selection: future retained NetEase account operations can
/// revoke a background sign-in jar without ever changing the player owner.
final retainedNeteaseEpochProvider =
    NotifierProvider<RetainedNeteaseEpoch, int>(RetainedNeteaseEpoch.new);

class RetainedNeteaseEpoch extends Notifier<int> {
  @override
  int build() => 0;
  void advance() => state++;
}

/// The active login is immediately usable during restoration. Switching to
/// NetEase reuses the retained identity and never borrows its cookie/session.
final retainedKugouSessionProvider = Provider<PlatformSession?>((ref) {
  final mutation = ref.watch(retainedKugouMutationProvider);
  final active = ref.watch(platformAccountProvider).value;
  final saved = ref.watch(savedKugouSessionProvider);
  if (mutation.known) return mutation.session;
  if (active?.platform == MusicPlatform.kugou) return active;
  return saved.isLoading || saved.hasError ? null : saved.value;
});

final retainedKugouScopeProvider = Provider<RetainedKugouScope?>((ref) {
  ref.watch(
    retainedKugouSessionProvider.select(
      (s) => (s?.userId, s?.token, s?.vipToken),
    ),
  );
  final owner = ref.read(retainedKugouSessionProvider);
  if (owner == null) return null;
  final client = MusicHttpClient();
  final scope = RetainedKugouScope(
    MusicPlatformApi(server: ref.watch(musicServerProvider), client: client),
    owner,
    client.close,
  );
  ref.onDispose(scope.close);
  return scope;
});

/// A credential owns a private request jar. Revocation clears it synchronously
/// so even an already-running resolver fails its post-await account guard.
class RetainedKugouScope {
  RetainedKugouScope(this.api, this.owner, this._closeClient) {
    api.session = owner;
  }
  final MusicPlatformApi api;
  final PlatformSession owner;
  final void Function() _closeClient;
  bool _closed = false;
  bool get current => !_closed && api.session?.token == owner.token;
  void close() {
    _closed = true;
    api.session = null;
    _closeClient();
  }
}
