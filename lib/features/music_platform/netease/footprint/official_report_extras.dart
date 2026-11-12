/// The public listen-home page consumes these independent report blocks.
/// Missing sections remain absent: local history never fills official stats.
class OfficialReportItem {
  const OfficialReportItem({
    this.title = '',
    this.detail = '',
    this.cover = '',
    this.id = '',
    this.percent,
  });
  final String title, detail, cover, id;
  final double? percent;
}

class OfficialReportExtras {
  const OfficialReportExtras({
    this.achievement = '',
    this.achievementDetail = '',
    this.covers = const [],
    this.songCount,
    this.songs = const [],
    this.artists = const [],
    this.genres = const [],
    this.ages = const [],
    this.languages = const [],
  });
  final String achievement, achievementDetail;
  final List<String> covers;
  final int? songCount;
  final List<OfficialReportItem> songs, artists, genres, ages, languages;

  factory OfficialReportExtras.parse(Map<String, dynamic> data) {
    Map object(Object? v) => v is Map ? v : const {};
    String text(Object? v) =>
        v is String ? v.substring(0, v.length.clamp(0, 256)) : '';
    String id(Object? v) {
      final s = '$v';
      return RegExp(r'^[1-9]\d{0,19}$').hasMatch(s) ? s : '';
    }

    String image(Object? v) {
      final s = text(v), uri = Uri.tryParse(s);
      if (uri == null ||
          !{'http', 'https'}.contains(uri.scheme) ||
          uri.userInfo.isNotEmpty) {
        return '';
      }
      return uri.replace(scheme: 'https').toString();
    }

    List<OfficialReportItem> items(
      String block,
      String title, {
      String? identifier,
      bool ratio = false,
    }) {
      final source = object(data[block]);
      final raw = source['sections'];
      if (raw is! List) return const [];
      final extra = source['songItems'];
      return List.unmodifiable(
        raw
            .take(24)
            .toList()
            .asMap()
            .entries
            .map((entry) {
              // Official listen-home's We renderer zips sections with songItems
              // by index. Era/language metadata and representative cover/ID are
              // separate arrays; reading sections alone loses real cover art.
              final row = <Object?, Object?>{
                ...object(entry.value),
                if (extra is List && entry.key < extra.length)
                  ...object(extra[entry.key]),
              };
              final number = row['percent'];
              final percent = number is num
                  ? number.toDouble()
                  : double.tryParse('$number');
              final heading = title == 'age'
                  ? officialReportAge('${row[title] ?? ''}')
                  : text(row[title]);
              return OfficialReportItem(
                title: heading,
                detail: [
                  text(row['text']),
                  text(row['field']),
                  if (title == 'age') text(row['songName']),
                ].where((s) => s.isNotEmpty).join(' · '),
                cover: image(row['picUrl']),
                id: identifier == null ? '' : id(row[identifier]),
                percent:
                    ratio &&
                        percent != null &&
                        percent.isFinite &&
                        percent >= 0 &&
                        percent <= 100
                    ? percent
                    : null,
              );
            })
            .where((v) => v.title.isNotEmpty),
      );
    }

    final achievement = object(
      object(data['listenTimeDistributionBlock'])['achievementTitle'],
    );
    final wall = object(data['wallpaperBlock']), rawCovers = wall['picUrls'];
    final count = wall['songCount'];
    return OfficialReportExtras(
      achievement: text(achievement['mainTitle']),
      achievementDetail: text(achievement['subTitle']),
      covers: rawCovers is List
          ? List.unmodifiable(
              rawCovers.take(30).map(image).where((v) => v.isNotEmpty),
            )
          : const [],
      songCount: count is int && count >= 0 ? count : null,
      songs: items('topSongBlock', 'songName', identifier: 'songId'),
      artists: items('topArtistBlock', 'artistName', identifier: 'artistId'),
      genres: items('topStyleBlock', 'genreName', ratio: true),
      ages: items('topAgeBlock', 'age', identifier: 'songId'),
      languages: items('topLanguageBlock', 'language', ratio: true),
    );
  }
}

/// Same era grouping as public listen-home module 69650/eK.
String officialReportAge(String value) {
  final year = int.tryParse(value);
  if (year == null) return value;
  if (year >= 2020) return '2020年后';
  if (year >= 2000) return '${year ~/ 10}0-${year ~/ 10}9';
  if (year >= 1910) return '${year % 100 ~/ 10}0年代';
  if (year >= 1900) return '20世纪初';
  return '${year ~/ 10}0年代';
}

/// Badge asset names are declared by the official public page; report titles
/// still come from the server. New titles fall back to text until mapped.
const officialAchievementImages = <String, String>{
  '云村超级乐迷':
      'https://sg.music.163.com/st/listen-home/static/media/super_fan_pic.fc4c65dd.png',
  '云村发烧友':
      'https://sg.music.163.com/st/listen-home/static/media/heavy_enthusiast_pic.9b987c66.png',
  '听歌全勤奖':
      'https://sg.music.163.com/st/listen-home/static/media/perfect_attendance_pic.20bac56c.png',
  '云村失踪人口':
      'https://sg.music.163.com/st/listen-home/static/media/missing_person_pic.1fadb1e8.png',
  '自律达人':
      'https://sg.music.163.com/st/listen-home/static/media/self_discipline_pic.bffd0768.png',
  '云村夜猫子':
      'https://sg.music.163.com/st/listen-home/static/media/night_owl_pic.b2ebde54.png',
  '红心收藏家':
      'https://sg.music.163.com/st/listen-home/static/media/heart_collector_pic.80b6f112.png',
  '音乐漫游者':
      'https://sg.music.163.com/st/listen-home/static/media/music_wander_pic.ff8943da.png',
  '黑胶大师':
      'https://sg.music.163.com/st/listen-home/static/media/vinyl_master_pic.5e50336d.png',
};
