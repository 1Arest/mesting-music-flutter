import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../domain/platform_session.dart';
import 'music_platform_api.dart';

/// 明确列举已从官版20.8.6或它实际加载的官方H5代码核实的服务。
/// 调用方不能传任意主机，也不能借查询参数覆盖账号归属。
enum KugouOfficialRoute {
  medalSummary('medal.kugou.com', '/v3/medal/user_summary_medal'),
  medalList('medal.kugou.com', '/v1/medal/user_medal_list'),
  medalLevels('medal.kugou.com', '/v1/medal/user_medal_levels'),
  medalDetail('medal.kugou.com', '/v1/medal/user_medal_detail'),
  medalWear('medal.kugou.com', '/v1/medal/append_wear'),
  medalSelect('medal.kugou.com', '/v1/medal/batch_select_medal'),
  medalReceive('medal.kugou.com', '/v1/user_center/receive_medal'),
  medalHave('medal.kugou.com', '/v1/medal/get_user_have'),
  levelInfo('songplay.kugou.com', '/v1/listen_level/my_info'),
  levelRank('songplay.kugou.com', '/v1/listen_level/rank'),
  levelLike('songplay.kugou.com', '/v1/listen_level/like_user'),
  levelUnlike('songplay.kugou.com', '/v1/listen_level/unlike_user'),
  rankCities('userinfo.user.kugou.com', '/v1/get_rank_citylist'),
  setRankCity('userinfo.user.kugou.com', '/v1/set_rank_city'),
  statistics('lstatistics2.kugou.com', '/v1/listen_statistics'),
  friendRank('gateway.kugou.com', '/songplay/v1/rank/friend_play_duration'),
  medals('gateway.kugou.com', '/medal/v2/user_center/my_medals'),
  medalConfigs('gateway.kugou.com', '/medal/v1/medal/configs'),
  medalTotal('gateway.kugou.com', '/medal/v2/medal/user_total'),
  annual2019('inventory2018.kugou.com', '/v1/user_year_2019/get_data'),
  annual2020('inventory2018.kugou.com', '/v1/user_year_2020/get_data'),
  annual2021('inventory2018.kugou.com', '/v1/user_year_2021/get_data'),
  annual2022('inventory2018.kugou.com', '/v1/user_year_2022/get_data'),
  annual2023('inventory2018.kugou.com', '/v1/user_year_2023/get_data'),
  annual('inventory2018.kugou.com', '/v1/user_year/get_data');

  const KugouOfficialRoute(this.host, this.path);
  final String host, path;
}

class KugouOfficialException implements Exception {
  const KugouOfficialException(this.message, {this.loginRequired = false});
  final String message;
  final bool loginRequired;
  @override
  String toString() => message;
}

/// 签名按官方H5已发布的2919协议完成，按实际授权使用3116或1005身份。
/// 不能将Lite token改标成1005。网络回执和账号变化都在返回结果前核对。
class KugouOfficialApi {
  KugouOfficialApi({
    required this.client,
    required this.currentIdentity,
    required this.device,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final http.Client client;
  final PlatformSession? Function() currentIdentity;
  final Future<Map<String, String>> Function() device;
  final DateTime Function() clock;
  static const _h5Key = 'NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt';

  static String signature(Map<String, String> query, String body) {
    final keys = query.keys.where((k) => k != 'signature').toList()..sort();
    return md5
        .convert(
          utf8.encode(
            '$_h5Key${keys.map((k) => '$k=${query[k]}').join()}$body$_h5Key',
          ),
        )
        .toString();
  }

  static Future<Map<String, String>> registeredDevice(
    MusicPlatformApi api,
  ) async {
    await api.ensureRegisteredDevice();
    final directory = await getApplicationSupportDirectory();
    final file = File(
      '${directory.path}/music_platform/runtime/device_info.json',
    );
    if (!await file.exists() || await file.length() > 16384) {
      throw const KugouOfficialException('设备注册尚未完成，请稍后重试');
    }
    final data = jsonDecode(await file.readAsString());
    if (data is! Map) {
      throw const KugouOfficialException('设备信息读取失败，请重试');
    }
    final values = {
      for (final k in ['mid', 'uuid', 'dfid']) k: '${data[k] ?? ''}',
    };
    if (values.values.any((v) => v.isEmpty || v == '-' || v.length > 128)) {
      throw const KugouOfficialException('设备注册尚未完成，请稍后重试');
    }
    return values;
  }

  bool isCurrent(PlatformSession owner) =>
      currentIdentity()?.platform == MusicPlatform.kugou &&
      currentIdentity()?.userId == owner.userId &&
      currentIdentity()?.token == owner.token &&
      currentIdentity()?.kugouAppId == owner.kugouAppId &&
      currentIdentity()?.kugouStandardToken == owner.kugouStandardToken;
  void _check(PlatformSession owner) {
    if (!isCurrent(owner)) {
      throw const KugouOfficialException('账号已变化，请重新打开页面');
    }
  }

  Future<Map<String, dynamic>> request(
    KugouOfficialRoute route,
    PlatformSession owner, {
    Map<String, String> query = const {},
    Map<String, Object?>? body,
  }) async {
    _check(owner);
    final identity = await device();
    _check(owner);
    final encoded = body == null ? '' : jsonEncode(body);
    final report =
        route.host == 'lstatistics2.kugou.com' ||
        route.host == 'inventory2018.kugou.com' ||
        route.host == 'gateway.kugou.com';
    final parameters = <String, String>{
      // 身份字段始终由本次实际授权生成，调用方查询参数无权覆盖或混入。
      for (final entry in query.entries)
        if (!{
          'userid',
          'token',
          'clienttoken',
          'kugouid',
          'appid',
          'clientver',
          'clienttime',
          'mid',
          'uuid',
          'dfid',
          'srcappid',
          'signature',
        }.contains(entry.key))
          entry.key: entry.value,
      ...identity,
      'srcappid': '2919',
      'appid': '${owner.kugouAppId}',
      'clientver': '${owner.kugouClientVersion}',
      // 听歌报告显式按秒；新版等级/勋章H5通用签名补全使用毫秒。
      'clienttime':
          '${report ? clock().millisecondsSinceEpoch ~/ 1000 : clock().millisecondsSinceEpoch}',
      'userid': owner.userId,
      if (route.host == 'inventory2018.kugou.com') ...{
        // 官版年度报告采用 year 模式，不能把普通token参数套到年度合同。
        'kugouid': owner.userId, 'clienttoken': owner.kugouOfficialToken,
      } else
        'token': owner.kugouOfficialToken,
    };
    parameters['signature'] = signature(parameters, encoded);
    final request = http.Request(
      body == null ? 'GET' : 'POST',
      Uri.https(route.host, route.path, parameters),
    )..followRedirects = false;
    request.headers.addAll({
      'Accept': 'application/json',
      'Cache-Control': 'no-cache',
      'Referer': 'https://h5.kugou.com/',
      'Origin': 'https://h5.kugou.com',
    });
    if (body != null) {
      request.headers['Content-Type'] = 'application/json;charset=utf-8';
      request.body = encoded;
    }
    try {
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 15));
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 15),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > 4 * 1024 * 1024) {
          throw const FormatException();
        }
      }
      _check(owner);
      if (response.statusCode != 200) {
        throw const KugouOfficialException('酷狗服务暂时不可用，请重试');
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) {
        throw const FormatException();
      }
      final payload = Map<String, dynamic>.from(decoded);
      if ('${payload['status']}' != '1') {
        final code = '${payload['errcode'] ?? payload['error_code'] ?? ''}';
        final auth = {'30000', '20018'}.contains(code);
        throw KugouOfficialException(
          auth ? '该官方服务需要重新验证酷狗登录' : '酷狗暂未返回这项资料，请重试',
          loginRequired: auth,
        );
      }
      return payload;
    } on KugouOfficialException {
      rethrow;
    } catch (_) {
      throw const KugouOfficialException('酷狗资料读取失败，请检查网络后重试');
    }
  }
}
