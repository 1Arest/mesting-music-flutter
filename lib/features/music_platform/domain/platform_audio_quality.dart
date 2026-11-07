/// Request codes are the pinned upstream's real `/song/url` contract.
enum PlatformAudioQuality {
  standard('128', '标准'),
  high('320', '高品质'),
  lossless('flac', '无损'),
  hiRes('high', 'Hi-Res'),
  // NetEase-specific codes never enter Kugou's hash/quality contract. The
  // original four persisted values above retain their existing meaning.
  higher('netease_higher', '较高'),
  jyEffect('netease_jyeffect', '高清臻音'),
  sky('netease_sky', '沉浸环绕声'),
  jyMaster('netease_jymaster', '超清母带'),
  dolby('netease_dolby', '杜比全景声'),
  vivid('netease_vivid', '臻音全景声');

  const PlatformAudioQuality(this.code, this.label);
  final String code;
  final String label;
  bool get neteaseOnly => index > hiRes.index;
  String get neteaseLabel => this == high ? '极高' : label;
  String get neteaseLevel => switch (this) {
    standard => 'standard',
    high => 'exhigh',
    lossless => 'lossless',
    hiRes => 'hires',
    higher => 'higher',
    jyEffect => 'jyeffect',
    sky => 'sky',
    jyMaster => 'jymaster',
    dolby => 'dolby',
    vivid => 'vivid',
  };
  static const neteaseOrder = [
    standard,
    higher,
    high,
    lossless,
    hiRes,
    jyEffect,
    sky,
    jyMaster,
    dolby,
    vivid,
  ];
  static PlatformAudioQuality? fromNeteaseLevel(Object? level) =>
      values.where((v) => v.neteaseLevel == level).firstOrNull;

  static PlatformAudioQuality? fromCode(Object? code) {
    for (final value in values) {
      if (value.code == '$code') return value;
    }
    return null;
  }

  /// Follow the upstream downgrade chain; never label the request as the
  /// delivered quality. Unknown responses stay unknown in the player badge.
  List<PlatformAudioQuality> get fallbackChain =>
      neteaseOnly ? [this] : values.take(index + 1).toList().reversed.toList();
}
