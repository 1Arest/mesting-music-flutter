import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/beta_glass_controls.dart';
import '../../themes/music_typography.dart';
import '../presentation/platform_design.dart';
import 'qishui_api.dart';
import 'qishui_signer_connection.dart';
import 'qishui_signer_settings.dart';

class QishuiSignerSettingsPage extends ConsumerStatefulWidget {
  const QishuiSignerSettingsPage({super.key});
  @override
  ConsumerState<QishuiSignerSettingsPage> createState() =>
      _SignerSettingsState();
}

class _SignerSettingsState extends ConsumerState<QishuiSignerSettingsPage> {
  final _address = TextEditingController();
  final _token = TextEditingController();
  bool _hydrated = false, _testing = false, _saving = false, _reveal = false;
  String? _message;
  bool _failed = false;
  bool _accountBoundSigning = false;
  Completer<void>? _abort;

  void _edited(String _) => setState(() => _message = null);

  Future<void> _run({required bool test}) async {
    if (_saving || _testing) return;
    QishuiSignerConfig config;
    try {
      config = QishuiSignerConfig.parse(
        _address.text,
        _token.text,
        accountBoundSigning: _accountBoundSigning,
      );
    } on FormatException catch (error) {
      setState(() {
        _message = error.message;
        _failed = true;
      });
      return;
    }
    setState(() {
      _testing = test;
      _saving = !test;
      _message = null;
    });
    try {
      if (test) {
        final abort = _abort = Completer<void>();
        await ref.read(qishuiSignerProbeProvider)(config, abort.future);
      } else {
        await ref.read(qishuiSignerSettingsProvider.notifier).save(config);
      }
      if (mounted) {
        setState(() {
          _failed = false;
          _message = test ? '连接和签名检查通过。真实歌曲播放仍需实际验证。' : '已保存，后续签名请求使用你的助手。';
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = error is QishuiException
              ? error.message
              : error is QishuiSignerSettingsFailure
              ? error.message
              : test
              ? '签名服务检查未完成，请检查地址和助手状态'
              : '设置保存失败，请重试；原配置已保留';
        });
      }
    } finally {
      _abort = null;
      if (mounted) {
        setState(() {
          _testing = false;
          _saving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    if (_abort?.isCompleted == false) _abort!.complete();
    _address.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(qishuiSignerSettingsProvider);
    final enabled = !_testing && !_saving;
    return PopScope(
      canPop: !_saving,
      child: PlatformPageFrame(
        title: '汽水签名服务',
        pageKey: const ValueKey('qishui-signer-settings-page'),
        child: settings.when(
          loading: () => const Center(child: Text('正在读取签名服务设置…')),
          error: (_, _) => Center(
            child: BetaGlassButton(
              onPressed: () => ref.invalidate(qishuiSignerSettingsProvider),
              child: const Text('设置未能读取，点击重试'),
            ),
          ),
          data: (saved) {
            if (!_hydrated) {
              _hydrated = true;
              _address.text =
                  saved?.baseUri.toString() ?? qishuiSelfHostedSignerAddress;
              _token.text = saved?.accessToken ?? '';
              _accountBoundSigning = saved?.accountBoundSigning ?? false;
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 220),
              children: [
                const Text('连接你的签名助手', style: MusicTypography.sectionTitle),
                const SizedBox(height: 10),
                Text(saved == null ? '未配置访问令牌，填写并保存后才能使用签名服务。' : '当前已使用自建服务。'),
                const SizedBox(height: 24),
                TextField(
                  key: const ValueKey('qishui-signer-address'),
                  controller: _address,
                  enabled: enabled,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: _edited,
                  decoration: const InputDecoration(
                    labelText: '服务地址',
                    hintText: 'https://nas.example.com/qishui-signer/',
                    helperText: '支持 HTTP / HTTPS、端口和路径前缀，也可粘贴 /sign 地址',
                    helperMaxLines: 6,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  key: const ValueKey('qishui-signer-token'),
                  controller: _token,
                  enabled: enabled,
                  obscureText: !_reveal,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [],
                  onChanged: _edited,
                  decoration: InputDecoration(
                    labelText: '访问令牌',
                    helperText: '填写助手生成的令牌，在当前设备加密保存',
                    helperMaxLines: 6,
                    suffixIcon: IconButton(
                      tooltip: _reveal ? '隐藏访问令牌' : '显示访问令牌',
                      onPressed: enabled
                          ? () => setState(() => _reveal = !_reveal)
                          : null,
                      icon: Icon(
                        _reveal ? Icons.visibility_off : Icons.visibility,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SwitchListTile.adaptive(
                  key: const ValueKey('qishui-account-signing'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('账号参与签名'),
                  subtitle: const Text(
                    '开启后，歌曲请求所需的 Cookie 会通过 HTTPS 交给你自建的 NAS 生成签名，用于核对当前账号的播放权益。请只填写你信任并管理的服务地址。',
                  ),
                  value: _accountBoundSigning,
                  onChanged: enabled
                      ? (value) => setState(() {
                          _accountBoundSigning = value;
                          _message = null;
                        })
                      : null,
                ),
                const SizedBox(height: 12),
                const Text(
                  '默认关闭。公共签名服务和诊断导出不接收账号 Cookie。测试连接仍使用匿名请求；开关在保存后生效。',
                  style: MusicTypography.footnote,
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    BetaGlassButton(
                      key: const ValueKey('qishui-signer-test'),
                      loading: _testing,
                      onPressed: enabled ? () => _run(test: true) : null,
                      child: const Text('测试连接'),
                    ),
                    BetaGlassButton(
                      key: const ValueKey('qishui-signer-save'),
                      accent: true,
                      loading: _saving,
                      onPressed: enabled ? () => _run(test: false) : null,
                      child: const Text('保存并使用'),
                    ),
                  ],
                ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _message!,
                        key: const ValueKey('qishui-signer-result'),
                        style: TextStyle(
                          color: _failed
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                const Text(
                  '签名助手只处理签名，音乐仍从汽水官方获取。测试连接不会播放歌曲或修改账号内容。',
                  style: MusicTypography.footnote,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
