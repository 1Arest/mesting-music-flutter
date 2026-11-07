import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/music_http_client.dart';

import 'netease_api.dart';
import 'netease_session.dart';

final neteaseSessionStoreProvider = Provider<NeteaseSessionStore>(
  (ref) => const SecureNeteaseSessionStore(),
);
final neteaseApiProvider = Provider<NeteaseApi>((ref) {
  final client = MusicHttpClient();
  ref.onDispose(client.close);
  return NeteaseApi(client);
});
