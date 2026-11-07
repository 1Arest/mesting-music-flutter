/// Public transport identity, independent from the library's recording ID.
/// No signed URL or credential belongs here: this value travels with history.
class AudioOrigin {
  const AudioOrigin(this.adapter, this.recordingId);
  final String adapter;
  final String recordingId;
  static const qishui = '汽水官方';
  static const netease = '网易云官方';
  static const kugou = '酷狗概念版';
  bool get isNetease => adapter == netease;
  bool get isKugou =>
      adapter == kugou || adapter == '酷狗概念版账号' || adapter == '酷狗公开音源';
  String get identity => '$adapter|$recordingId';
  Map<String, String> toJson() => {
    'adapter': adapter,
    'recordingId': recordingId,
  };
  static AudioOrigin? fromJson(Object? value) {
    if (value is! Map ||
        value['adapter'] is! String ||
        (value['adapter'] as String).isEmpty) {
      return null;
    }
    return AudioOrigin(
      value['adapter'] as String,
      '${value['recordingId'] ?? ''}',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AudioOrigin && identity == other.identity;
  @override
  int get hashCode => identity.hashCode;
}
