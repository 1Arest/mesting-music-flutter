import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../music_platform_providers.dart';
import '../../platform_backend_providers.dart';
import '../netease_providers.dart';
import 'official_footprint_providers.dart';
import 'official_footprint_repository.dart';
import 'listening_footprint_models.dart';
import 'listening_footprint_reader.dart';

final officialFootprintDetailSourceProvider =
    Provider<OfficialFootprintDetailSource>(
      (ref) => OfficialFootprintRepository(ref.watch(neteaseApiProvider)),
    );

/// No request starts just by creating this provider. It retains only this
/// account session's successful reports; owner/token changes dispose the cache
/// and late responses cannot enter the next account's page.
final listeningFootprintReaderProvider = Provider<ListeningFootprintReader?>((
  ref,
) {
  final account = ref.watch(platformAccountProvider).value;
  if (!ref.watch(usesNeteaseProvider) || account == null) return null;
  final owner = account.ownerId, token = account.token;
  final reader = ListeningFootprintReader(
    ref.watch(officialFootprintDetailSourceProvider),
    now: ref.watch(officialFootprintClockProvider),
    current: () =>
        ref.mounted &&
        ref.read(usesNeteaseProvider) &&
        ref.read(platformAccountProvider).value?.ownerId == owner &&
        ref.read(platformAccountProvider).value?.token == token,
  );
  ref.onDispose(reader.dispose);
  return reader;
});
