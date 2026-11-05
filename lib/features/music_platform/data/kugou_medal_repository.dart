import '../domain/kugou_listening_profile.dart';
import '../domain/kugou_medal_catalog.dart';
import '../domain/platform_session.dart';
import 'kugou_official_api.dart';

/// 与官版勋章收藏馆同合同；读请求可以显式重试，写操作只提交一次。
class KugouMedalRepository {
  const KugouMedalRepository(this.official);
  final KugouOfficialApi official;

  int _uid(PlatformSession owner) {
    final uid = int.tryParse(owner.userId);
    if (uid == null || uid <= 0) {
      throw const KugouOfficialException('酷狗账号信息不完整，请重新验证');
    }
    return uid;
  }

  Future<Map<String, dynamic>> _read(
    KugouOfficialRoute route,
    PlatformSession owner,
    Map<String, Object?> body,
  ) async {
    final payload = await official.request(route, owner, body: body);
    if (payload['data'] is! Map) {
      throw const KugouOfficialException('酷狗未返回这项徽章资料，请稍后重试');
    }
    return kugouObject(payload['data']);
  }

  Future<KugouMedalSummary> summary(PlatformSession owner) async =>
      KugouMedalSummary(
        await _read(KugouOfficialRoute.medalSummary, owner, {
          'target_userid': _uid(owner), 'ret_classify_list': 1, 'ret_medals': 1,
          // 不触发新获得/升级勋章弹窗或已读清除。
          'ret_last_medal': 0, 'ret_upgrade_medal': 0,
        }),
        official.clock(),
      );

  Future<KugouMedalList> list(
    PlatformSession owner,
    String category, {
    int page = 1,
  }) async {
    final data = await _read(KugouOfficialRoute.medalList, owner, {
      'target_userid': _uid(owner),
      'type': category,
      'page': page,
      'page_size': 30,
      'sort': 0,
    });
    if (data['list'] is! List) {
      throw const KugouOfficialException('徽章列表读取不完整，请重试');
    }
    return KugouMedalList(
      kugouMedalRows(
        data['list'],
      ).map((r) => KugouMedalItem(r, category: category)).toList(),
      kugouNonnegative(data['total']),
      page,
      official.clock(),
    );
  }

  Future<KugouMedalDetail> detail(
    PlatformSession owner,
    KugouMedalItem item,
  ) async {
    if (item.classifyId == null || item.type.isEmpty) {
      throw const KugouOfficialException('这枚徽章的官方信息不完整，请刷新');
    }
    final data = await _read(KugouOfficialRoute.medalLevels, owner, {
      'target_userid': _uid(owner),
      'type': item.type,
      'classify_id': item.classifyId,
    });
    if (data['medal_list'] is! List) {
      throw const KugouOfficialException('徽章详情读取不完整，请重试');
    }
    return KugouMedalDetail(data, item.type);
  }

  Future<KugouMedalList> owned(
    PlatformSession owner, {
    required int source,
    int page = 1,
  }) async {
    final data = await _read(KugouOfficialRoute.medalHave, owner, {
      'target_userid': _uid(owner),
      'page': page,
      'page_size': 30,
      'source': source,
    });
    if (data['medals'] is! List) {
      throw const KugouOfficialException('可佩戴徽章读取不完整，请重试');
    }
    return KugouMedalList(
      kugouMedalRows(data['medals']).map((r) => KugouMedalItem(r)).toList(),
      kugouNonnegative(data['total']),
      page,
      official.clock(),
    );
  }

  Future<void> wear(PlatformSession owner, KugouMedalItem item) async {
    if (!item.earned || item.classifyId == null || item.type.isEmpty) {
      throw const KugouOfficialException('这枚徽章当前不可佩戴，请刷新查看最新状态');
    }
    await official.request(
      KugouOfficialRoute.medalWear,
      owner,
      body: {
        'type': item.type,
        'classify_id': item.classifyId,
        'wear_action': item.selected(1) > 0 ? 1 : 0,
        'source': 3,
      },
    );
  }

  Future<void> select(
    PlatformSession owner,
    int source,
    List<KugouMedalItem> items,
  ) async {
    final limit = source == 1
        ? 5
        : source == 2
        ? 2
        : 0;
    if (limit == 0 ||
        items.length > limit ||
        items.map((i) => i.key).toSet().length != items.length ||
        items.any(
          (i) => i.id == null || i.classifyId == null || i.type.isEmpty,
        )) {
      throw const KugouOfficialException('佩戴选择不完整，请刷新后重试');
    }
    await official.request(
      KugouOfficialRoute.medalSelect,
      owner,
      body: {
        'source': source,
        'selected_medals': items.map((i) => i.selection).toList(),
      },
    );
  }

  Future<void> receive(PlatformSession owner, KugouMedalItem item) async {
    if (!item.canReceive || item.id == null || item.classifyId == null) {
      throw const KugouOfficialException('这枚徽章当前不可领取，请刷新查看最新状态');
    }
    await official.request(
      KugouOfficialRoute.medalReceive,
      owner,
      body: {'id': item.id, 'type': item.type, 'classify_id': item.classifyId},
    );
  }
}
