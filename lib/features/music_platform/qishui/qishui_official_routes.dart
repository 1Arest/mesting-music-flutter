/// Exact common API contracts recovered from the official Soda APK. These
/// routes are not guessed `/pc` translations. A Web login keeps its real PC
/// signer identity and same-origin cookies; server acceptance is a separate
/// device/account validation, never implied by a passing protocol fixture.
class QishuiOfficialRoutes {
  const QishuiOfficialRoutes._();

  static bool formMutation(String path) =>
      path == '/luna/me/follow' || path == '/luna/me/unfollow';

  static bool supports(String method, String path) {
    if (method == 'POST') {
      return path == '/luna/search/track' ||
          path == '/luna/me/music_wall' ||
          path == '/luna/me/collection/artist' ||
          path == '/luna/me/collection/artist/delete' ||
          formMutation(path);
    }
    if (method != 'GET') return false;
    if (path == '/luna/user/info' || path == '/luna/me/collection/artist') {
      return true;
    }
    return RegExp(
      r'^/luna/users/[0-9]{1,30}/(?:following|follower)$',
    ).hasMatch(path);
  }
}
