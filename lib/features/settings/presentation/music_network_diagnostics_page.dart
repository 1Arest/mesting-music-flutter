import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/network/music_network_diagnostics.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/music_notice.dart';

/// Local, bounded evidence for intermittent failures on another user's device.
/// Opening/copying this page never probes an account or submits a login/SMS.
class MusicNetworkDiagnosticsPage extends StatelessWidget {
  const MusicNetworkDiagnosticsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('连接与播放诊断')),
    body: ListenableBuilder(
      listenable: MusicNetworkDiagnostics.shared,
      builder: (context, _) {
        final rows = MusicNetworkDiagnostics.shared.rows.reversed.toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            const Text('保留本次启动最近 80 条连接结果。失败后打开此页，可复制记录用于排查。'),
            const SizedBox(height: 16),
            BetaGlassButton(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: MusicNetworkDiagnostics.shared.export()),
                );
                if (context.mounted) {
                  showMusicNotice(
                    context,
                    icon: Icons.check_rounded,
                    title: '诊断记录已复制',
                    message: '',
                  );
                }
              },
              child: const Text('复制诊断记录'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: MusicNetworkDiagnostics.shared.clear,
              child: const Text('清除本次记录'),
            ),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('本次启动暂无连接记录'),
              ),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  '${row['platform']} · ${_operation(row['operation'])}\n'
                  '${_outcome(row['outcome'])} · ${row['elapsedMs']} ms'
                  '${row['status'] == null ? '' : ' · ${row['status']}'}\n'
                  '${row['phase'] == null ? '' : '${_phase(row['phase'])}${row['family'] == null ? '' : ' · ${_family(row['family'])}'}\n'}'
                  '${row['at']}',
                  style: const TextStyle(height: 1.5),
                ),
              ),
          ],
        );
      },
    ),
  );
  static String _operation(Object? name) => switch (name) {
    'playbackUrl' => '播放地址',
    'audio' => '音频加载',
    'sms' => '验证码',
    'login' => '登录',
    'qr' => '扫码',
    'restore' => '本机账号恢复',
    'storage' => '本机账号保存',
    _ => '资料读取',
  };
  static String _phase(Object? name) => switch (name) {
    'credentialValidate' => '平台凭据校验',
    'storageRead' => '读取加密资料',
    'storageDecode' => '解析本机资料',
    'storageWrite' => '保存加密资料',
    'storageVerify' => '回读保存结果',
    'recoveryWrite' => '保存恢复资料',
    'accountPublish' => '本机登录确认',
    'networkSend' => '请求与响应读取',
    'responseDecode' => '解析服务资料',
    'responseValidate' => '平台资料校验',
    _ => '准备连接',
  };
  static String _family(Object? name) => switch (name) {
    'timeout' => '等待超时',
    'keyUnavailable' => '密钥暂不可用',
    'keyInvalidated' => '密钥失效',
    'decrypt' => '解密失败',
    'io' => '本机读写失败',
    'pluginUnavailable' => '存储尚未就绪',
    'format' => '资料格式异常',
    'credentialIncomplete' => '凭据不完整',
    _ => '未分类故障',
  };
  static String _outcome(Object? name) => switch (name) {
    'success' => '连接完成',
    'dns' => '地址解析失败',
    'tls' => '安全连接失败',
    'timeout' => '等待超时',
    'http' => '服务响应异常',
    'business' => '平台未接受',
    'format' => '数据格式异常',
    'cancelled' => '已取消',
    'storage' => '本机加密存储读取失败',
    _ => '连接中断',
  };
}
