import 'package:pinyin/pinyin.dart';

import '../../../shared/models/track.dart';

final _hanCharacter = RegExp('[\u3400-\u9fff]');
final _searchSeparator = RegExp(r'[\s/,&，、·•\-—_()（）\[\]【】]+');
final _searchNoise = RegExp('[^a-z0-9\u3400-\u9fff]+');
final Map<String, _PhoneticForms> _phoneticCache = {};

/// Scores literal, pinyin, initial-pinyin and small edit-distance matches.
///
/// Larger values are better. Zero means that the candidate is not a useful
/// local fuzzy match, although remote providers may still keep it as a
/// fallback result.
int fuzzyTextMatchScore(String rawQuery, String candidate) {
  final query = _normalizeSearchText(rawQuery);
  if (query.isEmpty || candidate.trim().isEmpty) return 0;

  var best = 0;
  for (final part in _candidateParts(candidate)) {
    final normalized = _normalizeSearchText(part);
    if (normalized.isEmpty) continue;
    best = _max(best, _literalScore(query, normalized));

    final partHasHan = _hanCharacter.hasMatch(part);
    final queryHasHan = _hanCharacter.hasMatch(rawQuery);
    if (queryHasHan) {
      best = _max(best, _approximateScore(query, normalized, base: 760));
      continue;
    }

    final forms = _phoneticForms(part);
    final hanBonus = partHasHan ? 80 : 0;
    best = _max(
      best,
      _phoneticScore(query, forms.full, exactBase: 1060 + hanBonus),
    );
    best = _max(
      best,
      _phoneticScore(query, forms.initials, exactBase: 1080 + hanBonus),
    );
    if (query.length >= 4) {
      best = _max(
        best,
        _approximateScore(query, forms.full, base: 820 + (partHasHan ? 40 : 0)),
      );
    }
  }
  return best;
}

int fuzzyTrackMatchScore(String query, Track track) {
  final title = fuzzyTextMatchScore(query, track.title);
  final artist = fuzzyTextMatchScore(query, track.artist);
  final album = fuzzyTextMatchScore(query, track.album);
  return _max(
    _max(title == 0 ? 0 : title + 30, artist == 0 ? 0 : artist + 20),
    album,
  );
}

/// Reorders provider results without issuing any additional remote request.
///
/// When [matchingOnly] is true, unmatched candidates are removed. This is
/// used for local libraries; online results retain their provider fallback.
List<Track> rankTracksForFuzzyQuery(
  String query,
  Iterable<Track> tracks, {
  bool matchingOnly = false,
}) {
  final ranked = <_RankedTrack>[];
  var index = 0;
  for (final track in tracks) {
    final score = fuzzyTrackMatchScore(query, track);
    if (!matchingOnly || score > 0) {
      ranked.add(_RankedTrack(track: track, score: score, index: index));
    }
    index += 1;
  }
  ranked.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    return byScore != 0 ? byScore : a.index.compareTo(b.index);
  });
  return List<Track>.unmodifiable(ranked.map((entry) => entry.track));
}

int _literalScore(String query, String candidate) {
  if (candidate == query) return 1000;
  if (candidate.startsWith(query)) return 920;
  if (candidate.contains(query)) return 820;
  return 0;
}

int _phoneticScore(String query, String candidate, {required int exactBase}) {
  if (candidate.isEmpty) return 0;
  if (candidate == query) return exactBase;
  if (candidate.startsWith(query)) return exactBase - 80;
  if (candidate.contains(query)) return exactBase - 160;
  return 0;
}

int _approximateScore(String query, String candidate, {required int base}) {
  if (query.length < 2 || candidate.length < 2) return 0;
  final longest = _max(query.length, candidate.length);
  final allowedDistance = longest <= 6 ? 1 : 2;
  if ((query.length - candidate.length).abs() > allowedDistance) return 0;
  final distance = _damerauLevenshtein(query, candidate);
  if (distance == 0 || distance > allowedDistance) return 0;
  final similarity = 1 - (distance / longest);
  if (longest > 2 && similarity < .66) return 0;
  return base - (distance - 1) * 90;
}

Iterable<String> _candidateParts(String candidate) sync* {
  final trimmed = candidate.trim();
  if (trimmed.isEmpty) return;
  yield trimmed;
  final seen = <String>{trimmed};
  for (final part in trimmed.split(_searchSeparator)) {
    final value = part.trim();
    if (value.isNotEmpty && seen.add(value)) yield value;
  }
}

String _normalizeSearchText(String value) =>
    value.toLowerCase().replaceAll(_searchNoise, '');

_PhoneticForms _phoneticForms(String value) {
  final cached = _phoneticCache[value];
  if (cached != null) return cached;

  final full = StringBuffer();
  final initials = StringBuffer();
  var atAsciiWordStart = true;
  for (final rune in value.runes) {
    final character = String.fromCharCodes([rune]);
    if (_hanCharacter.hasMatch(character)) {
      final pinyin = _characterPinyin(character);
      if (pinyin.isNotEmpty) {
        full.write(pinyin);
        initials.write(pinyin[0]);
      }
      atAsciiWordStart = true;
      continue;
    }

    final ascii = character.toLowerCase();
    if (RegExp(r'[a-z0-9]').hasMatch(ascii)) {
      full.write(ascii);
      if (atAsciiWordStart) initials.write(ascii);
      atAsciiWordStart = false;
    } else {
      atAsciiWordStart = true;
    }
  }
  final forms = _PhoneticForms(
    full: _normalizeSearchText(full.toString()),
    initials: _normalizeSearchText(initials.toString()),
  );
  if (_phoneticCache.length >= 512) {
    _phoneticCache.remove(_phoneticCache.keys.first);
  }
  _phoneticCache[value] = forms;
  return forms;
}

String _characterPinyin(String character) {
  try {
    return PinyinHelper.getPinyin(
      character,
      separator: '',
      format: PinyinFormat.WITHOUT_TONE,
    ).toLowerCase();
  } on Object {
    return '';
  }
}

int _damerauLevenshtein(String left, String right) {
  if (left == right) return 0;
  if (left.isEmpty) return right.length;
  if (right.isEmpty) return left.length;

  final previousPrevious = List<int>.filled(right.length + 1, 0);
  var previous = List<int>.generate(right.length + 1, (index) => index);
  for (var leftIndex = 1; leftIndex <= left.length; leftIndex += 1) {
    final current = List<int>.filled(right.length + 1, 0);
    current[0] = leftIndex;
    for (var rightIndex = 1; rightIndex <= right.length; rightIndex += 1) {
      final substitutionCost =
          left.codeUnitAt(leftIndex - 1) == right.codeUnitAt(rightIndex - 1)
          ? 0
          : 1;
      current[rightIndex] = _min(
        _min(current[rightIndex - 1] + 1, previous[rightIndex] + 1),
        previous[rightIndex - 1] + substitutionCost,
      );
      if (leftIndex > 1 &&
          rightIndex > 1 &&
          left.codeUnitAt(leftIndex - 1) == right.codeUnitAt(rightIndex - 2) &&
          left.codeUnitAt(leftIndex - 2) == right.codeUnitAt(rightIndex - 1)) {
        current[rightIndex] = _min(
          current[rightIndex],
          previousPrevious[rightIndex - 2] + 1,
        );
      }
    }
    for (var index = 0; index < previous.length; index += 1) {
      previousPrevious[index] = previous[index];
    }
    previous = current;
  }
  return previous[right.length];
}

int _min(int left, int right) => left < right ? left : right;
int _max(int left, int right) => left > right ? left : right;

class _PhoneticForms {
  const _PhoneticForms({required this.full, required this.initials});

  final String full;
  final String initials;
}

class _RankedTrack {
  const _RankedTrack({
    required this.track,
    required this.score,
    required this.index,
  });

  final Track track;
  final int score;
  final int index;
}
