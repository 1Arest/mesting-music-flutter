import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/music_platform/netease/netease_api.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_manual_routes.dart';
import 'package:mesting_music/features/music_platform/netease/full/netease_content.dart';

/// Anonymous read-only probes. Never load saved sessions or change accounts.
/// Store status and response shape only, without copying editorial content.
void main() => test(
  'anonymous read-only catalogue probes',
  _probe,
  timeout: const Timeout(Duration(minutes: 5)),
);
Future<void> _probe() async {
  HttpOverrides.global = null;
  final client = http.Client();
  final api = NeteaseApi(client);
  final result = <Map<String, Object?>>[];
  const samples = <String, Map<String, Object?>>{
    '/artist/list': {'type': '1', 'area': '7', 'limit': '3'},
    '/playlist/hot': {},
    '/toplist/detail': {},
    '/album/newest': {},
    '/search/suggest': {'keywords': '周杰伦'},
    '/style/list': {},
    '/style/detail': {'tagId': '1000'},
    '/sheet/list': {'id': '186016'},
    '/mv/first': {'limit': '3'},
    '/dj/toplist': {'type': 'hot', 'limit': '3'},
    '/video/group/list': {},
    '/countries/code/list': {},
  };
  try {
    for (final sample in samples.entries) {
      final contract = neteaseCompleteContract(sample.key, sample.value);
      if (contract == null) {
        result.add({'route': sample.key, 'status': 'missing-contract'});
        continue;
      }
      try {
        final response = await api.request(
          contract.path,
          contract.data,
          weapi: contract.weapi,
        );
        final content = NeteaseContent.parse(response, sample.key);
        Object shape(Object? v, int depth) => v is Map && depth < 3
            ? <String, Object>{
                for (final item in v.entries.take(16))
                  '${item.key}': shape(item.value, depth + 1),
              }
            : v is List
            ? <Object>[
                v.length,
                if (v.isNotEmpty && depth < 3) shape(v.first, depth + 1),
              ]
            : v.runtimeType.toString();
        result.add({
          'route': sample.key,
          'status': 'response',
          'code': response['code'],
          'keys': response.keys.toList(),
          'dataType': response['data'].runtimeType.toString(),
          'parsedRows': content.rows.length,
          'factCount': content.facts.length,
          'shape': shape(response, 0),
        });
      } catch (error) {
        result.add({
          'route': sample.key,
          'status': 'failed',
          'error': '$error',
        });
      }
    }
  } finally {
    client.close();
  }
  final file = File(
    '.codex-artifacts/2026-10-29-netease-full-scope/public-probes.json',
  );
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'anonymous': true,
      'writes': false,
      'accountAccess': false,
      'results': result,
    }),
  );
  stdout.writeln(
    'Anonymous reads: ${result.length}, returned: ${result.where((r) => r['status'] == 'response').length}',
  );
}
