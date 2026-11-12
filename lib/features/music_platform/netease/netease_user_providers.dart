import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../music_platform_providers.dart';
import '../platform_backend_providers.dart';
import '../data/music_platform_api.dart';
import '../domain/platform_session.dart';
import 'netease_connection_models.dart';
import 'netease_user_repository.dart';

final neteaseUserRepositoryProvider = Provider(
  (ref) => NeteaseUserRepository(ref.watch(neteaseMusicRepositoryProvider)),
);

/// The owner's official totals are independent of loaded relation pages. A
/// failed/missing field never falls back to an invented zero or partial count.
final neteasePersonalStatsProvider =
    FutureProvider.autoDispose<NeteasePersonalStats?>((ref) async {
      final account = ref.watch(platformAccountProvider).value;
      if (account?.platform != MusicPlatform.netease) return null;
      return ref
          .watch(neteaseUserRepositoryProvider)
          .personalStats(account!.userId);
      // A visible failure is retried by the page's explicit refresh. Riverpod's
      // generic exponential retry also retries missing/expired credentials and
      // would leave a hidden retained My tab scheduling account reads forever.
    }, retry: (_, _) => null);

class NeteaseUserRelation {
  const NeteaseUserRelation(this.followed, {this.busy = false});
  final bool followed, busy;
}

/// Shared by search rows, profiles and connection lists. A write publishes only
/// after upstream confirms it; duplicate taps and stale-account completions
/// cannot change the new account's relationship state.
class NeteaseUserRelations extends Notifier<Map<String, NeteaseUserRelation>> {
  int _epoch = 0;
  @override
  Map<String, NeteaseUserRelation> build() {
    ref.watch(
      platformAccountProvider.select((v) => (v.value?.ownerId, v.value?.token)),
    );
    ++_epoch;
    return const {};
  }

  Future<void> setFollowed(
    String id,
    bool followed, {
    required bool previous,
  }) async {
    if (state[id]?.busy == true) return;
    final repository = ref.read(neteaseUserRepositoryProvider);
    final identity = ref.read(platformAccountProvider).value;
    if (identity?.platform != MusicPlatform.netease) {
      throw const MusicPlatformException('请先登录网易云');
    }
    final epoch = _epoch;
    bool current() =>
        ref.mounted &&
        epoch == _epoch &&
        identical(repository, ref.read(neteaseUserRepositoryProvider)) &&
        ref.read(platformAccountProvider).value?.ownerId == identity?.ownerId &&
        ref.read(platformAccountProvider).value?.token == identity?.token;
    state = {...state, id: NeteaseUserRelation(previous, busy: true)};
    try {
      await repository.follow(id, followed);
      if (current()) {
        state = {...state, id: NeteaseUserRelation(followed)};
        ref.invalidate(neteasePersonalStatsProvider);
      }
    } on Object {
      if (current()) state = {...state, id: NeteaseUserRelation(previous)};
      rethrow;
    }
  }
}

final neteaseUserRelationsProvider =
    NotifierProvider<NeteaseUserRelations, Map<String, NeteaseUserRelation>>(
      NeteaseUserRelations.new,
    );

/// Artist subscriptions never share a map key or write endpoint with users.
/// The generation also rejects a late completion after A -> B -> A relogin.
class NeteaseArtistRelations
    extends Notifier<Map<String, NeteaseUserRelation>> {
  int _epoch = 0;
  @override
  Map<String, NeteaseUserRelation> build() {
    ref.watch(
      platformAccountProvider.select((v) => (v.value?.ownerId, v.value?.token)),
    );
    ++_epoch;
    return const {};
  }

  Future<void> setSubscribed(
    String id,
    bool subscribed, {
    required bool previous,
  }) async {
    if (state[id]?.busy == true) return;
    final repository = ref.read(neteaseUserRepositoryProvider);
    final identity = ref.read(platformAccountProvider).value;
    if (identity?.platform != MusicPlatform.netease) {
      throw const MusicPlatformException('请先登录网易云');
    }
    final epoch = _epoch;
    bool current() =>
        ref.mounted &&
        epoch == _epoch &&
        identical(repository, ref.read(neteaseUserRepositoryProvider)) &&
        ref.read(platformAccountProvider).value?.ownerId == identity?.ownerId &&
        ref.read(platformAccountProvider).value?.token == identity?.token;
    state = {...state, id: NeteaseUserRelation(previous, busy: true)};
    try {
      await repository.subscribeArtist(id, subscribed);
      if (current()) {
        state = {...state, id: NeteaseUserRelation(subscribed)};
        ref.invalidate(neteasePersonalStatsProvider);
      }
    } on Object {
      if (current()) state = {...state, id: NeteaseUserRelation(previous)};
      rethrow;
    }
  }
}

final neteaseArtistRelationsProvider =
    NotifierProvider<NeteaseArtistRelations, Map<String, NeteaseUserRelation>>(
      NeteaseArtistRelations.new,
    );
