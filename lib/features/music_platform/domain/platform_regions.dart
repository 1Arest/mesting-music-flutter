import 'dart:convert';
import 'package:flutter/services.dart';

class MusicRegion {
  const MusicRegion(this.name, this.code, this.cities);
  final String name, code;
  final List<({String name, String code})> cities;
}

/// Match only administrative-code boundaries, not arbitrary digit prefixes.
/// Providers return 440000/440300 while the offline rows use 44/4403. Six-digit
/// directly administered cities retain their full identity (e.g. 419001).
bool musicRegionMatches(String name, String code, String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return false;
  if (text == name || (code.isNotEmpty && text == code)) return true;
  return code.isNotEmpty &&
      RegExp(r'^\d{6}(?:\d{3}){0,2}$').hasMatch(text) &&
      text.startsWith(code);
}

/// Resolve public profile values without rewriting the stored selection.
/// A picker applies defaults locally; only its explicit Done result is saved.
({MusicRegion? province, ({String name, String code})? city})
resolveMusicRegion(
  List<MusicRegion> regions, {
  String? province,
  String? city,
}) {
  final region = regions
      .where((p) => musicRegionMatches(p.name, p.code, province))
      .firstOrNull;
  return (
    province: region,
    city: region?.cities
        .where((c) => musicRegionMatches(c.name, c.code, city))
        .firstOrNull,
  );
}

/// Offline province/city names are sent to Kugou, never guessed numeric IDs.
/// Municipalities use their own city name rather than a district as a city.
Future<List<MusicRegion>> loadMusicRegions() async {
  final rows =
      jsonDecode(await rootBundle.loadString('assets/data/music-regions.json'))
          as List;
  return rows
      .map((raw) {
        final row = raw as Map;
        final code = '${row['code']}';
        final name = '${row['name']}';
        final municipal = const {'11', '12', '31', '50'}.contains(code);
        return MusicRegion(
          name,
          code,
          municipal
              ? [(name: name, code: '${code}01')]
              : (row['children'] as List)
                    .map(
                      (city) =>
                          (name: '${city['name']}', code: '${city['code']}'),
                    )
                    .toList(growable: false),
        );
      })
      .toList(growable: false);
}
