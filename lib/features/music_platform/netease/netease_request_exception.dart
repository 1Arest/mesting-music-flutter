import '../../../core/network/music_network_diagnostics.dart';
import '../data/music_platform_api.dart';

/// Structured transport facts for callers that need to distinguish an HTTP
/// failure from a business-code refusal. The message stays compatible with
/// existing music flows; headers, cookies and response bodies are not retained.
class NeteaseRequestException extends MusicPlatformException {
  const NeteaseRequestException(
    super.message, {
    required this.outcome,
    this.httpStatus,
  });

  final MusicNetworkOutcome outcome;
  final int? httpStatus;
}
