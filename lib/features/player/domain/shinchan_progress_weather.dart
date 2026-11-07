/// Progress-character decoration is independent of retired full-screen skins.
/// Keep stable identifiers so a saved choice survives app and theme changes.
enum ShinchanProgressWeather {
  sun('太阳'),
  breeze('微风'),
  sunset('夕阳'),
  night('夜晚'),
  drizzle('细雨'),
  storm('雷雨'),
  parade('游行');

  const ShinchanProgressWeather(this.label);
  final String label;

  static ShinchanProgressWeather? fromName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}
