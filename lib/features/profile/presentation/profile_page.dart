import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets/route_settled_content.dart';
import '../../../shared/widgets/music_activity_indicator.dart';
import '../../music_platform/presentation/platform_profile.dart';
import '../../player/presentation/music_page_transition.dart';

void openMyPlaylistsFromProfile(BuildContext context) => context.push(
  '/music?view=playlists',
  extra: const MusicPageTransitionIntent.forward(),
);
void openMusicSearchFromProfile(BuildContext context) => context.push(
  '/music/search',
  extra: const MusicPageTransitionIntent.forward(),
);

/// The same platform profile serves all channels. Its data stays scoped to the
/// real selected platform; no retired account or social providers are mounted.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context) => RouteSettledContent(
    builder: (_) => const PlatformProfile(),
    placeholder: const Center(child: MusicActivityIndicator()),
  );
}
