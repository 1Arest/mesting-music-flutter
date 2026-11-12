import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/audio/playback_providers.dart';
import '../../shared/models/track.dart';
import '../history/listening_replay.dart';
import '../player/sharing/song_share.dart';
import 'listening_atmosphere.dart';
import 'listening_keepsake.dart';
import 'personal_decorations.dart';
import 'personal_style.dart';

/// Read-only samples use the production renderers and explicit option overrides.
/// No preview writes preferences, starts audio, exports files or records history.
class PersonalStylePreview extends ConsumerWidget {
  const PersonalStylePreview({
    required this.kind,
    required this.value,
    super.key,
  });
  final String kind, value;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(personalStyleProvider);
    final color = personalPalettes[value] ?? saved.accent;
    Widget sample;
    switch (kind) {
      case 'poster':
        sample = _PosterPreview(template: PosterTemplate.values.byName(value));
      case 'keepsake':
        sample = FittedBox(
          child: SizedBox(
            width: 360,
            child: ListeningKeepsakeCard(
              design: KeepsakeTemplate.values.byName(value),
              replay: const ListeningReplay(0, [], []),
              year: DateTime.now().year,
              month: value == 'collection' ? null : DateTime.now().month,
              preview: true,
            ),
          ),
        );
      case 'mini':
        sample = Center(
          child: PersonalMiniPlayer(
            finish: MiniPlayerFinish.values.byName(value),
            child: Container(
              height: 45,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Row(
                children: [
                  Icon(Icons.album_rounded, size: 26, color: color),
                  const SizedBox(width: 5),
                  const Expanded(
                    child: Text('正在播放', style: TextStyle(fontSize: 10)),
                  ),
                  const Icon(Icons.pause_rounded, size: 17),
                ],
              ),
            ),
          ),
        );
      case 'atmosphere':
        sample = ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
              ),
              ListeningAtmosphereLayer(
                preview: true,
                style: PersonalStyle.fromJson({
                  ...saved.toJson(),
                  'atmosphere': value,
                  'strength': .9,
                }),
              ),
              Center(
                child: Icon(
                  value == 'off' ? Icons.block : Icons.music_note_rounded,
                  size: 26,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        );
      case 'accessory':
        sample = Center(
          child: PersonalAvatarDecoration(
            accessory: AvatarAccessory.values.byName(value),
            child: CircleAvatar(
              radius: 23,
              backgroundColor: color.withValues(alpha: .18),
              child: const Icon(Icons.person_outline_rounded),
            ),
          ),
        );
      default:
        final bundle = personalPaletteBundle(value);
        sample = Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final c in [
                    color,
                    Color(bundle['lyricColor'] as int? ?? color.toARGB32()),
                    color.withValues(alpha: .45),
                  ])
                    Padding(
                      padding: const EdgeInsets.all(3),
                      child: CircleAvatar(radius: 8, backgroundColor: c),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '让音乐陪你',
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
    }
    return RepaintBoundary(
      child: MediaQuery.withNoTextScaling(
        child: ExcludeSemantics(child: sample),
      ),
    );
  }
}

class _PosterPreview extends ConsumerStatefulWidget {
  const _PosterPreview({required this.template});
  final PosterTemplate template;
  @override
  ConsumerState<_PosterPreview> createState() => _PosterPreviewState();
}

class _PosterPreviewState extends ConsumerState<_PosterPreview> {
  Future<Uint8List>? _image;
  Track? _track;
  @override
  Widget build(BuildContext context) {
    final track = ref.exists(audioHandlerProvider)
        ? ref.watch(currentTrackProvider)
        : personalStyleDemoTrack;
    if (_image == null ||
        _track?.id != track.id ||
        _track?.coverAsset != track.coverAsset) {
      _track = track;
      // Small previews share the full export's drawing code without allocating
      // five 1080px export images while the user scrolls the settings page.
      _image = generateSongPoster(
        track,
        template: widget.template,
        pixelRatio: .5,
        fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
      );
    }
    return FutureBuilder<Uint8List>(
      future: _image,
      builder: (context, result) {
        if (result.hasData) {
          return Image.memory(
            result.data!,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            excludeFromSemantics: true,
          );
        }
        if (result.hasError) return const Icon(Icons.image_outlined);
        return const Center(child: Icon(Icons.image_outlined, size: 22));
      },
    );
  }
}
