import 'dart:convert';
import 'kugou_listening_profile.dart';
import 'platform_session.dart';

class KugouMedalCategory {
  const KugouMedalCategory(this.raw);
  final Map<String, dynamic> raw;
  String get type => '${raw['type'] ?? ''}';
  String get name => '${raw['name'] ?? ''}';
  int? get count => kugouNonnegative(raw['have_total']);
  List<KugouMedalCategory> get children => kugouMedalRows(
    raw['secondary_menu'],
  ).map(KugouMedalCategory.new).toList(growable: false);
}

List<Map<String, dynamic>> kugouMedalRows(Object? value) => value is List
    ? value.whereType<Map>().map(kugouObject).toList(growable: false)
    : const [];

class KugouMedalItem {
  const KugouMedalItem(this.raw, {this.category = ''});
  final Map<String, dynamic> raw;
  final String category;
  String get type => '${raw['type'] ?? category}';
  int? get classifyId => kugouNonnegative(raw['classify_id']);
  int? get id => kugouNonnegative(raw['id']);
  String get key => '$type:$classifyId:$id:${raw['ds2nd_classify_name'] ?? ''}';
  String get name => '${raw['name'] ?? ''}';
  String get level => '${raw['ds2nd_classify_name'] ?? ''}';
  String get image => PlatformSession.picture(raw['big_pic_v3']);
  String get receivedAt => '${raw['receive_time'] ?? ''}';
  bool get earned =>
      kugouNonnegative(raw['is_light_up']) == 1 &&
      kugouNonnegative(raw['is_exptime']) == 0;
  bool get expired => kugouNonnegative(raw['is_exptime']) == 1;
  bool get canReceive => kugouNonnegative(raw['tag_type']) == 1;
  int selected(int source) =>
      kugouNonnegative(
        raw[source == 1 ? 'selected_no' : 'comment_selected_no'],
      ) ??
      0;
  Map<String, Object?> get selection => {
    'type': type,
    'classify_id': classifyId,
    'id': id,
  };
}

class KugouMedalSummary {
  const KugouMedalSummary(this.raw, this.readAt);
  final Map<String, dynamic> raw;
  final DateTime readAt;
  int? get total =>
      kugouNonnegative(kugouObject(raw['user_info'])['medal_total']);
  List<KugouMedalCategory> get categories =>
      kugouMedalRows(raw['classify_list']).map(KugouMedalCategory.new).toList();
  List<KugouMedalItem> get worn =>
      kugouMedalRows(raw['medals']).map((r) => KugouMedalItem(r)).toList();
}

class KugouMedalList {
  const KugouMedalList(this.items, this.total, this.page, this.readAt);
  final List<KugouMedalItem> items;
  final int? total;
  final int page;
  final DateTime readAt;
  bool get hasMore =>
      items.isNotEmpty &&
      (total == null ? items.length == 30 : page * 30 < total!);
}

class KugouMedalDetail {
  const KugouMedalDetail(this.raw, this.category);
  final Map<String, dynamic> raw;
  final String category;
  List<KugouMedalItem> get levels => raw['medal_info'] is Map
      ? [KugouMedalItem(kugouObject(raw['medal_info']), category: category)]
      : kugouMedalRows(
          raw['medal_list'],
        ).map((r) => KugouMedalItem(r, category: category)).toList();

  /// 只呈现服务返回的文案，不将动态脚本、交易按钮或内部条件键当作说明。
  List<String> get conditions {
    final result = <String>{};
    void visit(Object? value, int depth) {
      if (depth > 6 || result.length >= 30) return;
      if (value is Map) {
        for (final entry in value.entries) {
          final item = entry.value;
          if (const {
                'title',
                'name',
                'desc',
                'description',
                'task_desc',
                'text',
              }.contains(entry.key) &&
              item is String &&
              item.trim().isNotEmpty &&
              item.length < 1000) {
            result.add(item.replaceAll(RegExp(r'<[^>]*>'), '').trim());
          } else if (item is Map || item is List) {
            visit(item, depth + 1);
          }
        }
      } else if (value is List) {
        for (final item in value.take(50)) {
          visit(item, depth + 1);
        }
      }
    }

    for (final key in [
      'medal_rule_data',
      'medal_task_data',
      'user_level_status',
    ]) {
      var value = raw[key];
      if (value is String && value.length < 100000) {
        try {
          value = jsonDecode(value);
        } catch (_) {
          continue;
        }
      }
      visit(value, 0);
    }
    return result.toList(growable: false);
  }
}
