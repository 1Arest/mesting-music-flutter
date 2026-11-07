import 'platform_session.dart';

/// Public profile data is separate from credentials. Missing fields stay null:
/// an absent server value must not turn into an unintended clear on Save.
class PlatformProfileInfo {
  const PlatformProfileInfo(
    this.nickname,
    this.avatarUrl, {
    this.sex,
    this.birthday,
    this.signature,
    this.province,
    this.city,
  });
  final String nickname, avatarUrl;
  final int? sex;
  final String? birthday, signature, province, city;

  factory PlatformProfileInfo.fromJson(
    Map<String, dynamic> payload,
    PlatformSession fallback,
  ) {
    final data = payload['data'] is Map
        ? Map<String, dynamic>.from(payload['data'] as Map)
        : payload;
    String? first(List<String> keys) {
      for (final key in keys) {
        final value = data[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
        if (value is num) return '$value';
      }
      return null;
    }

    final sex = int.tryParse(first(['sex', 'gender']) ?? '');
    return PlatformProfileInfo(
      first(['nickname', 'username', 'name']) ?? fallback.nickname,
      PlatformSession.picture(
        first(['avatar', 'pic', 'img']) ?? fallback.avatarUrl,
      ),
      sex: sex != null && sex >= 0 && sex <= 2 ? sex : null,
      birthday: normalizeBirthday(first(['birthday', 'birthdate'])),
      signature: first(['signature', 'usersign', 'sign']),
      province: first(['province', 'provinceName', 'province_name']),
      city: first(['city', 'cityName', 'city_name']),
    );
  }

  static String? normalizeBirthday(String? text) {
    if (text == null || text.isEmpty) return null;
    final number = int.tryParse(text);
    DateTime? date;
    if (number != null && number > 0) {
      // Kugou timestamps encode a China-local calendar date. Keep that date
      // independent of the timezone used by host tests or a travelling user.
      date = DateTime.fromMillisecondsSinceEpoch(
        number < 100000000000 ? number * 1000 : number,
        isUtc: true,
      ).add(const Duration(hours: 8));
    } else {
      date = DateTime.tryParse(text);
    }
    if (date == null || date.year < 1900 || date.year > DateTime.now().year) {
      return null;
    }
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

/// Only edited fields are sent, including explicit clearing of a known value.
Map<String, Object?> profileChanges(
  PlatformProfileInfo initial, {
  required String nickname,
  required String signature,
  int? sex,
  String? birthday,
  String? province,
  String? city,
}) {
  final result = <String, Object?>{};
  void changed(String key, String? old, String? value) {
    if (value == null) return;
    final trimmed = value.trim();
    if ((old ?? '').trim() != trimmed) result[key] = trimmed;
  }

  changed('nickname', initial.nickname, nickname);
  changed('signature', initial.signature, signature);
  changed('birthday', initial.birthday, birthday);
  changed('province', initial.province, province);
  changed('city', initial.city, city);
  if (sex != null && sex != initial.sex) result['sex'] = sex;
  return result;
}
