import 'package:flutter/material.dart';
import '../../../core/network/music_diagnostic_clipboard.dart';
import '../../../core/network/music_network_diagnostics.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_page_motion.dart';
import '../../music_platform/qishui/qishui_diagnostics_page.dart';

/// Local, bounded evidence for intermittent failures on another user's device.
/// Opening/copying this page never probes an account or submits a login/SMS.
class MusicNetworkDiagnosticsPage extends StatefulWidget {
  const MusicNetworkDiagnosticsPage({super.key});
  @override
  State<MusicNetworkDiagnosticsPage> createState() =>
      _MusicNetworkDiagnosticsPageState();
}

class _MusicNetworkDiagnosticsPageState
    extends State<MusicNetworkDiagnosticsPage> {
  bool _copying = false;
  String? _copyMessage;

  Future<void> _copy({required bool compact}) async {
    if (_copying) return;
    // Freeze before crossing the platform channel. New playback events must
    // not change the string against which the clipboard is verified.
    final snapshot = compact
        ? MusicNetworkDiagnostics.shared.exportCompact()
        : MusicNetworkDiagnostics.shared.export();
    setState(() {
      _copying = true;
      _copyMessage = '正在复制并核对剪贴板…';
    });
    final result = await MusicDiagnosticClipboard.copy(snapshot);
    if (!mounted) return;
    setState(() {
      _copying = false;
      _copyMessage = switch (result) {
        MusicDiagnosticCopyResult.verified => '已复制并核对。粘贴后请确认内容末尾完整。',
        MusicDiagnosticCopyResult.mismatch => '剪贴板内容核对不一致，请重试复制精简记录。',
        MusicDiagnosticCopyResult.unavailable => '未能核对剪贴板内容，请重试复制精简记录。',
      };
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('连接与播放诊断')),
    body: ListenableBuilder(
      listenable: MusicNetworkDiagnostics.shared,
      builder: (context, _) {
        final rows = MusicNetworkDiagnostics.shared.rows.reversed.toList();
        final buttonHeight =
            (MediaQuery.textScalerOf(context).scale(17) * 1.4 + 24).clamp(
              52.0,
              double.infinity,
            );
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            const Text('保留本次启动最近 80 条连接结果。失败后优先复制精简记录，包含最近一次故障及同平台前序阶段。'),
            const SizedBox(height: 16),
            BetaGlassButton(
              height: buttonHeight,
              label: '汽水专用诊断',
              onPressed: () => Navigator.of(
                context,
              ).push(betaContentRoute<void>(const QishuiDiagnosticsPage())),
              child: const Text('汽水专用诊断'),
            ),
            const SizedBox(height: 12),
            BetaGlassButton(
              height: buttonHeight,
              interactionEnabled: !_copying,
              onPressed: () => _copy(compact: true),
              child: const Text('复制精简记录'),
            ),
            const SizedBox(height: 12),
            BetaGlassButton(
              height: buttonHeight,
              interactionEnabled: !_copying,
              onPressed: () => _copy(compact: false),
              child: const Text('复制诊断记录'),
            ),
            if (_copyMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(liveRegion: true, child: Text(_copyMessage!)),
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
                  '${_status(row)}\n'
                  '${row['phase'] == null ? '' : '${_phase(row['phase'])}${row['family'] == null ? '' : ' · ${_family(row['family'])}'}\n'}'
                  '${row['nativeStep'] == null ? '' : '${_nativeStep(row['nativeStep'])}\n'}'
                  '${row['nativeReason'] == null ? '' : '${_nativeReason(row['nativeReason'])}\n'}'
                  '${row['at']}',
                  style: const TextStyle(height: 1.5),
                ),
              ),
          ],
        );
      },
    ),
  );

  /// A transport status and a platform's business code can both be 301. Keep
  /// their meaning visible without exposing a response body or redirect URL.
  static String _status(Map<String, Object> row) {
    final status = row['status'];
    if (status is! int) return '';
    final label = row['outcome'] == 'business'
        ? '业务码'
        : status >= 100 && status <= 599
        ? 'HTTP'
        : '状态码';
    return ' · $label $status';
  }

  static String _operation(Object? name) => switch (name) {
    'playbackUrl' => '播放地址',
    'audio' => '音频加载',
    'sms' => '验证码',
    'login' => '登录',
    'qr' => '扫码',
    'restore' => '本机账号恢复',
    'storage' => '本机账号保存',
    'rewardBalance' => '免费听余额',
    'rewardProgress' => '领取进度',
    'rewardQualification' => '领取资格',
    'rewardClaim' => '奖励领取',
    'rewardSignIn' => '每日签到',
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
    'playerInfoRead' => '播放资料读取',
    'mediaModelParse' => '音频候选解析',
    'mediaSelection' => '音频选择',
    'audioRead' => '音频文件读取',
    'audioDecode' => '本机音频准备',
    'audioVerify' => '音频时长与格式校验',
    'accountSigning' => '账号参与签名检查',
    'entitlementRead' => '账号权益读取',
    _ => '准备连接',
  };
  static String _nativeStep(Object? name) => switch (name) {
    'cachePath' => '私有缓存路径校验',
    'sourceRead' => '读取临时音频文件',
    'authorization' => '解析音频播放授权',
    'containerParse' => '解析音频容器与加密分段',
    'sampleDecrypt' => '音频分段解密',
    'cacheWrite' => '写入临时可播放文件',
    'metadataRead' => '读取实际音频格式与时长',
    _ => '本机音频处理',
  };
  static String _nativeReason(Object? name) => switch (name) {
    'cachePathInvalid' => '缓存路径未通过校验',
    'cacheFileMissing' => '临时音频文件不存在',
    'cacheOutputExists' => '临时音频文件冲突',
    'sourceReadFailed' => '临时音频文件读取未完成',
    'authorizationInvalid' => '播放授权解析未通过',
    'mediaStructureUnsupported' => '音频容器结构暂不受支持',
    'encryptionUnsupported' => '音频加密格式暂不受支持',
    'sampleTableInvalid' => '加密分段资料不完整或暂不受支持',
    'sampleDecryptFailed' => '音频分段解密未通过',
    'cacheWriteFailed' => '临时音频文件写入未完成',
    'metadataUnsupported' => '实际音频格式或时长读取未通过',
    'operationInvalid' => '音频准备操作无效',
    'bridgeUnavailable' => '本机音频组件尚未就绪',
    _ => '本机音频处理失败',
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
