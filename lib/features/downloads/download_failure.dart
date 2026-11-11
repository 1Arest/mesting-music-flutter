/// Conservative grouping: unknown failures retain their original explanation.
/// An expired login is never presented as an audio copyright/availability issue.
enum DownloadFailure { network, storage, authorization, source, other }

DownloadFailure classifyDownloadFailure(String message) {
  final text = message.toLowerCase();
  if (RegExp(r'登录|账号|授权|permission|denied|401|403').hasMatch(text)) {
    return DownloadFailure.authorization;
  }
  if (RegExp(r'空间|存储|保存|目录|no space|enospc|disk').hasMatch(text)) {
    return DownloadFailure.storage;
  }
  if (RegExp(r'网络|超时|连接|timeout|socket|connection|dns|503|502').hasMatch(text)) {
    return DownloadFailure.network;
  }
  if (RegExp(r'音源|下架|版权|不支持|不完整|音频|404|410').hasMatch(text)) {
    return DownloadFailure.source;
  }
  return DownloadFailure.other;
}

extension DownloadFailureLabel on DownloadFailure {
  String get label => switch (this) {
    DownloadFailure.network => '网络问题',
    DownloadFailure.storage => '存储问题',
    DownloadFailure.authorization => '登录或授权',
    DownloadFailure.source => '音源问题',
    DownloadFailure.other => '其他问题',
  };
}
