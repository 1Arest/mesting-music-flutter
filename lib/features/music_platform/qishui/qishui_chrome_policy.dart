/// Only the Soda music root already contains full playback controls. Keep its
/// secondary pages and every other platform's accessory contract unchanged.
bool qishuiMusicRootHidesMiniPlayer({
  required bool qishui,
  required String location,
  bool hasSecondaryPage = false,
}) {
  if (!qishui || hasSecondaryPage) return false;
  final uri = Uri.parse(location);
  return uri.path == '/music' && uri.queryParameters['view'] == null;
}
