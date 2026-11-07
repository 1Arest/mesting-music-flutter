/// Canonical count fields consumed by the UI. Different NetEase clients have
/// returned short names and *Count names; only numeric count fields belong in
/// this adapter, never user IDs, timestamps, or individual message contents.
Map<String, int> parseNeteaseMessageCounts(Map<String, dynamic> response) {
  const aliases = <String, List<String>>{
    'privateMsgCount': [
      'privateMsgCount',
      'privateCount',
      'privateMsg',
      'newMsgCount',
      'msgCount',
      'msg',
    ],
    'commentCount': ['commentCount', 'newCommentCount', 'comment'],
    'forwardCount': [
      'forwardCount',
      'newForwardCount',
      'forward',
      'mentionCount',
      'atCount',
    ],
    'noticeCount': ['noticeCount', 'newNoticeCount', 'notice'],
    'newFollowerCount': [
      'newFollowerCount',
      'newFollowCount',
      'followerCount',
      'followCount',
      'newFansCount',
      'follow',
    ],
  };
  final nested = response['data'];
  final sources = [
    response,
    if (nested is Map) Map<String, dynamic>.from(nested),
  ];
  final found = <String, int>{};
  for (final group in aliases.entries) {
    for (final source in sources) {
      for (final key in group.value) {
        final value = source[key];
        final number = value is int
            ? value
            : value is String
            ? int.tryParse(value)
            : null;
        if (number == null) continue;
        final bounded = number.clamp(0, 2147483647);
        if (bounded > (found[group.key] ?? -1)) found[group.key] = bounded;
      }
    }
  }
  // An unknown successful envelope is not a successful zero-unread response.
  // The repository can still use real conversation counts as a lower bound.
  if (found.isEmpty) throw const FormatException('网易云未读计数格式暂不可用');
  return Map.unmodifiable(found);
}
