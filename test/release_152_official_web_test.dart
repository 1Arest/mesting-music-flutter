import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/music_platform/data/kugou_official_web_contract.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';

void main() {
  test(
    'official navigation excludes spoofed hosts, redirects, trades and credential URLs',
    () {
      for (final url in [
        'http://activity.kugou.com/page/x',
        'https://activity.kugou.com.evil.test/x',
        'https://bad@activity.kugou.com/x',
        'https://activity.kugou.com:8443/x',
        'https://activity.kugou.com/pay/order',
        'https://activity.kugou.com/path?token=secret',
        'https://activity.kugou.com/path?URL=https%3A%2F%2Fevil.test',
      ]) {
        expect(
          KugouOfficialWebContract.accepts(Uri.parse(url)),
          false,
          reason: url,
        );
      }
      expect(
        KugouOfficialWebContract.accepts(KugouOfficialWebContract.rules),
        true,
      );
      expect(
        KugouOfficialWebContract.accepts(
          Uri.parse(
            'https://activity.kugou.com/page/v-21847b5d/detail.html?type=listen&classifyId=3',
          ),
        ),
        true,
      );
    },
  );
  test(
    'bridge executes with official auxiliary identity, escapes HTML and revokes credentials',
    () async {
      final html = KugouOfficialWebContract.bootstrap(
        session: const PlatformSession(
          userId: '1',
          token: 'lite-fixture',
          kugouStandardToken: 'standard-fixture',
          nickname: '</script><script>throw Error("injected")</script>',
        ),
        device: const {
          'mid': 'real-mid',
          'uuid': 'real-uuid',
          'dfid': 'real-dfid',
        },
        grade: const {'p_grade': 3},
      );
      final script = html.substring(
        '<script>'.length,
        html.length - '</script>'.length,
      );
      final harness =
          '''
const vm=require('vm');
const context={window:{},document:{currentScript:{remove(){}},addEventListener(){}},JSON,Object,Number};
context.window.top=context.window;
vm.createContext(context);vm.runInContext(${jsonEncode(script)},context);
const invoke=context.window.external.superCall;
const user=JSON.parse(invoke(101));const version=JSON.parse(invoke(122));
if(user.token!=='standard-fixture'||user.appid!==1005||version.version!==20869||user.gradeData.p_grade!==3)throw Error('wrong identity');
if(JSON.parse(invoke(764)).status!==0)throw Error('fabricated signing success');
context.window.__mestingKugouRevoke();
if(JSON.parse(context.window.external.superCall(101)).token)throw Error('credential survived revoke');
process.stdout.write('passed');
''';
      final result = await Process.run('node', ['-e', harness]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, 'passed');
      expect(
        html.split('</script>').length,
        2,
        reason: 'untrusted nickname cannot close the bootstrap script',
      );
    },
  );
}
