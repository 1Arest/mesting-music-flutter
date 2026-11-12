import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../music_platform_providers.dart';
import '../../platform_backend_providers.dart';
import '../netease_providers.dart';
import 'official_footprint.dart';
import 'official_footprint_reader.dart';
import 'official_footprint_repository.dart';

final officialFootprintSourceProvider = Provider<OfficialFootprintSource>(
  (ref) => OfficialFootprintRepository(ref.watch(neteaseApiProvider)),
);
final officialFootprintClockProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

/// Preserve successful values when revisiting the page in this account session.
/// Account/token changes dispose this reader; no network read or timer runs
/// merely because it remains in memory after the visible page closes.
final officialFootprintReaderProvider = Provider<OfficialFootprintReader?>((
  ref,
) {
  final account = ref.watch(platformAccountProvider).value;
  if (!ref.watch(usesNeteaseProvider) || account == null) return null;
  final owner = account.ownerId, token = account.token;
  final reader = OfficialFootprintReader(
    ref.watch(officialFootprintSourceProvider),
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
