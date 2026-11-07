class LyricsLine {
  const LyricsLine({required this.time, required this.text});

  final Duration time;
  final String text;
}

class LyricsDocument {
  const LyricsDocument({required this.lines, required this.isSynced});

  final List<LyricsLine> lines;
  final bool isSynced;

  int activeIndexAt(Duration position) {
    if (!isSynced || lines.isEmpty) return -1;
    var low = 0;
    var high = lines.length - 1;
    var result = -1;
    while (low <= high) {
      final middle = (low + high) >> 1;
      if (lines[middle].time <= position) {
        result = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return result;
  }
}
