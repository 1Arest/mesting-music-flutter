import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';

/// Layout/navigation fixtures have no account to restore. Explicitly isolate
/// them from platform secure-storage timeouts; storage behaviour has its own
/// dedicated tests and must not depend on widget-test scheduling.
class NoMusicAccountFixture extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => null;
}
