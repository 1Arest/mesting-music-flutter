import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'qishui_providers.dart';
import 'qishui_search_catalog.dart';

/// Bind one catalog to the same account epoch as the typed music repository.
/// It never opens its own client or imports another account's Cookie jar.
final qishuiSearchCatalogProvider = Provider<QishuiSearchCatalog>((ref) {
  final music = ref.watch(qishuiRepositoryProvider);
  return QishuiSearchCatalog(
    request:
        (
          path, {
          body = const {},
          query = const {},
          get = false,
          abortTrigger,
        }) => music.call(
          path,
          body: body,
          query: query,
          get: get,
          abortTrigger: abortTrigger,
        ),
  );
});
