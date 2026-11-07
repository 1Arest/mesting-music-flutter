import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_native_routes.g.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_catalog.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_manual_routes.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/netease-full-upstream-contracts.json',
            ).readAsStringSync(),
          )
          as Map;
  for (final raw in fixture['cases'] as List) {
    final item = raw as Map;
    test('original Node contract ${item['route']} ${item['variant']}', () {
      final contract = neteaseNativeRoute(
        '${item['route']}',
        Map<String, Object?>.from(item['query'] as Map),
        clock: () => DateTime.fromMillisecondsSinceEpoch(1793232000000),
      );
      expect(contract, isNotNull);
      expect({
        'path': contract!.path,
        'data': contract.data,
        'weapi': contract.weapi,
      }, item['expected']);
    });
  }
  test('catalogue contains every documented address and Together workflow', () {
    final json =
        jsonDecode(
              File('assets/data/netease-full-catalog.json').readAsStringSync(),
            )
            as Map;
    final entries = [
      for (final raw in json['entries'] as List)
        NeteaseEndpoint.fromJson(Map<String, dynamic>.from(raw)),
    ];
    expect(entries.length, 305);
    expect(entries.map((e) => e.route).toSet().length, 305);
    expect(entries.map((e) => e.tab).toSet(), {'发现', '功能', '音乐库', '我的'});
    for (final endpoint in entries) {
      expect(endpoint.title, isNotEmpty);
      expect(endpoint.category, isNotEmpty);
      for (final param in endpoint.parameters) {
        expect(
          neteaseFieldLabels.containsKey(param.key),
          isTrue,
          reason: 'Unlabelled ${endpoint.route} ${param.key}',
        );
      }
      final query = <String, Object?>{
        for (final p in endpoint.parameters) p.key: '7',
      };
      final alreadyNormalized = {
        '/login/cellphone',
        '/login',
        '/login/qr/key',
        '/login/qr/check',
        '/login/refresh',
        '/login/status',
        '/user/detail',
        '/playlist/tracks',
        '/comment/new',
      };
      final workflows = {
        '/login/qr/create',
        '/register/anonimous',
        '/avatar/upload',
        '/playlist/cover/update',
        '/comment/hotwall/list',
        '/related/playlist',
        '/playlist/track/all',
        '/cloud',
        '/batch',
        '/inner/version',
        '/voice/upload',
        '/audio/match',
      };
      if (!alreadyNormalized.contains(endpoint.route) &&
          !workflows.contains(endpoint.route)) {
        expect(
          neteaseCompleteContract(endpoint.route, query),
          isNotNull,
          reason: 'No executable path for ${endpoint.route}',
        );
      }
      if (endpoint.route.startsWith('/send/') ||
          endpoint.route == '/digitalAlbum/ordering') {
        expect(endpoint.write, isTrue);
      }
    }
    expect(entries.where((e) => e.unavailable != null).map((e) => e.route), [
      '/comment/hotwall/list',
    ]);
    expect(neteaseNativeRoute('/arbitrary/admin/path', {}), isNull);
  });
  test('creation and FM feedback are writes, status statistics are reads', () {
    final json =
        jsonDecode(
              File('assets/data/netease-full-catalog.json').readAsStringSync(),
            )
            as Map;
    final byRoute = {
      for (final raw in json['entries'] as List)
        raw['route'] as String: NeteaseEndpoint.fromJson(
          Map<String, dynamic>.from(raw),
        ),
    };
    for (final route in [
      '/playlist/create',
      '/playlist/track/add',
      '/fm_trash',
    ]) {
      expect(byRoute[route]!.write, isTrue, reason: route);
    }
    for (final route in [
      '/cellphone/existence/check',
      '/playlist/mylike',
      '/mv/detail/info',
      '/video/detail/info',
      '/yunbei/today',
      '/signin/progress',
    ]) {
      expect(byRoute[route]!.write, isFalse, reason: route);
    }
  });
}
