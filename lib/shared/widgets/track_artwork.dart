import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/distribution_channel.dart';
import '../../features/music_platform/data/platform_artwork.dart';
import '../../features/music_platform/platform_artwork_providers.dart';
import '../models/track.dart';
import 'artwork_image.dart';

/// A song-aware image boundary. Generic artwork (avatars, local themes) never
/// depends on platform metadata. An expired cover gets one metadata repair,
/// while ArtworkImage owns bounded transport retries and decode sizing.
class TrackArtwork extends ConsumerStatefulWidget {
  const TrackArtwork({
    required this.track,
    this.width,
    this.height,
    this.decodeWidth,
    this.decodeHeight,
    this.fit = BoxFit.cover,
    this.retryOnNetworkError = true,
    super.key,
  });
  final Track track;
  final double? width, height, decodeWidth, decodeHeight;
  final BoxFit fit;
  final bool retryOnNetworkError;
  @override
  ConsumerState<TrackArtwork> createState() => _TrackArtworkState();
}

class _TrackArtworkState extends ConsumerState<TrackArtwork> {
  String? _failedUri;
  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final platform =
        DistributionChannel.isBeta && track.source == TrackSource.kugou;
    final original = track.coverAsset;
    final local =
        original.startsWith('assets/') ||
        original.startsWith('file:') ||
        original.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(original);
    final repair =
        platform &&
        !local &&
        (PlatformArtwork.normalize(original).isEmpty || _failedUri == original);
    final restored = repair
        ? ref.watch(platformArtworkProvider(track)).value
        : null;
    final uri = restored?.isNotEmpty == true ? restored! : original;
    return ArtworkImage(
      frameOwner: '${track.source.name}:${track.id}',
      uri: uri,
      width: widget.width,
      height: widget.height,
      decodeWidth: widget.decodeWidth,
      decodeHeight: widget.decodeHeight,
      fit: widget.fit,
      retryOnNetworkError: widget.retryOnNetworkError,
      onNetworkError: platform && !repair
          ? () {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _failedUri != original) {
                  setState(() => _failedUri = original);
                }
              });
            }
          : null,
    );
  }
}
