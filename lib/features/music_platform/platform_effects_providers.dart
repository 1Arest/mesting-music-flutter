import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/platform_effects_repository.dart';
import 'music_platform_providers.dart';

final platformEffectsRepositoryProvider = Provider<PlatformEffectsRepository>(
  (ref) => PlatformEffectsRepository(ref.watch(musicPlatformApiProvider)),
);
