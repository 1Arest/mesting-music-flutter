import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../music_platform_providers.dart';
import '../platform_backend_providers.dart';
import 'netease_user_repository.dart';

final neteaseUserRepositoryProvider = Provider(
  (ref) => NeteaseUserRepository(ref.watch(neteaseMusicRepositoryProvider)),
);

class NeteaseUserRelation {
  const NeteaseUserRelation(this.followed, {this.busy = false});
  final bool followed, busy;
}

/// Shared by search rows, profiles and connection lists. A write publishes only
/// after upstream confirms it; duplicate taps and stale-account completions
/// cannot change the new account's relationship state.
class NeteaseUserRelations extends Notifier<Map<String, NeteaseUserRelation>> {
  @override
  Map<String, NeteaseUserRelation> build() {
    ref.watch(
      platformAccountProvider.select((v) => (v.value?.ownerId, v.value?.token)),
    );
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
    bool current() =>
        ref.mounted &&
        identical(repository, ref.read(neteaseUserRepositoryProvider)) &&
        ref.read(platformAccountProvider).value?.ownerId == identity?.ownerId &&
        ref.read(platformAccountProvider).value?.token == identity?.token;
    state = {...state, id: NeteaseUserRelation(previous, busy: true)};
    try {
      await repository.follow(id, followed);
      if (current()) state = {...state, id: NeteaseUserRelation(followed)};
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
