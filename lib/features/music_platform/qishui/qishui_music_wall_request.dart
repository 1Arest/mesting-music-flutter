/// Read-only music-wall capability flags used by the shipped official client.
/// UserRepository serializes these flags into a JSON *string*: an empty string
/// omits enable_new_music_wall and can leave listen_duration null. Both retained
/// official versions enable that flag with integer 1. The two unrelated
/// favorites experiments retain their default false values here.
abstract final class QishuiMusicWallRequest {
  static const Map<String, Object> body = {
    // Feed recommendation context is optional and unrelated to the cumulative
    // listening DTO. Do not invent sensor, advertising or recent-play context.
    'feed_music_wall_extra': <String, Object>{},
    'ab_param':
        '{"enable_new_music_wall":1,'
        '"enable_fav_artists":false,"enable_fav_playables":false}',
  };
}
