import '../../../shared/models/track.dart';

abstract interface class MusicSource {
  String get id;

  String get label;

  bool get isConfigured;

  Future<List<Track>> search(
    String query, {
    int limit = 20,
    Future<void>? abortTrigger,
  });
}

class MusicSourceException implements Exception {
  const MusicSourceException({
    required this.sourceLabel,
    required this.message,
    this.isTimeout = false,
  });

  final String sourceLabel;
  final String message;
  final bool isTimeout;

  @override
  String toString() => '$sourceLabel：$message';
}
