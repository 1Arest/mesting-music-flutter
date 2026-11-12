import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show ChangeNotifierProvider;
import '../../core/persistence/app_preferences.dart';
import '../../shared/models/track.dart';
import 'data/favorite_pins.dart';
import 'library_providers.dart';

final favoritePinsProvider = ChangeNotifierProvider(
  (ref) => FavoritePins(ref.watch(sharedPreferencesProvider)),
);

/// Loaded details stay lazy. A saved pinned catalogue row may appear ahead of
/// that window only after this account's complete ID index confirms membership.
final favoriteDisplayTracksProvider = Provider<AsyncValue<List<Track>>>((ref) {
  final pins = ref.watch(favoritePinsProvider);
  final owner = ref.watch(activeLibraryOwnerProvider);
  final value = ref.watch(favoriteTracksProvider);
  if (!pins.hasPins(owner)) return value;
  final membership = ref.watch(completeFavoriteIdsProvider).value;
  return value.whenData(
    (tracks) => pins.apply(
      owner,
      tracks,
      membership ?? tracks.map((t) => t.id).toSet(),
    ),
  );
});
