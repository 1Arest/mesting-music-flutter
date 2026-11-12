/// Selects the account's liked-song playlist from Kugou's mixed playlist list.
/// The server's system marker outranks a legacy display-name fallback. A
/// collected playlist named “默认收藏” is a separate destination, never an alias
/// for the heart button. Keep selection independent of reads/writes so they all
/// resolve the same cloud list, regardless of the server's ordering.
abstract final class KugouFavoritePlaylist {
  static int priority(Map<String, dynamic> row, String userId) {
    final listId = '${row['listid'] ?? ''}';
    if (listId.isEmpty || listId == '0') return 0;
    final creator = '${row['list_create_userid'] ?? ''}';
    final owned = creator.isNotEmpty
        ? creator == userId
        : '${row['type'] ?? 0}' == '0' && '${row['source'] ?? 1}' != '2';
    if (!owned || '${row['type']}' == '1' && '${row['source']}' == '2') {
      return 0;
    }
    final marker = '${row['is_def'] ?? ''}';
    if (marker == '2') return 2;
    // Older responses can omit the system marker. An explicit nonzero marker
    // belongs to a different system list and must not become a name fallback.
    if (marker.isNotEmpty && marker != '0') return 0;
    return const ['我喜欢', '我喜欢的音乐'].contains(row['name']) ? 1 : 0;
  }

  /// Returns only the strongest candidates. The repository rejects ambiguity
  /// instead of silently writing to whichever same-named row arrived first.
  static List<Map<String, dynamic>> candidates(
    List<Map<String, dynamic>> rows,
    String userId,
  ) {
    var best = 0;
    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      final rank = priority(row, userId);
      if (rank == 0 || rank < best) continue;
      if (rank > best) {
        best = rank;
        result.clear();
      }
      result.add(row);
    }
    return result;
  }
}
