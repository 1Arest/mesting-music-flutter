import '../../../shared/widgets/music_activity_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../themes/music_theme_tokens.dart';
import '../app_update_providers.dart';
import '../data/java_mysql_test_channel_repository.dart';
import '../domain/app_update_models.dart';

const javaMysqlTestChannelSheetKey = ValueKey<String>(
  'java-mysql-test-channel-sheet',
);

Future<void> showJavaMysqlTestChannelSheet(BuildContext context) {
  return showLiquidGlassBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const JavaMysqlTestChannelSheet(),
  );
}

class JavaMysqlTestChannelSheet extends ConsumerStatefulWidget {
  const JavaMysqlTestChannelSheet({super.key});

  @override
  ConsumerState<JavaMysqlTestChannelSheet> createState() =>
      _JavaMysqlTestChannelSheetState();
}

class _JavaMysqlTestChannelSheetState
    extends ConsumerState<JavaMysqlTestChannelSheet> {
  AppUpdateManifest? _manifest;
  String? _errorMessage;
  var _loading = true;
  var _downloading = false;
  var _receivedBytes = 0;

  @override
  void initState() {
    super.initState();
    _loadManifest();
  }

  Future<void> _loadManifest() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final manifest = await ref
          .read(javaMysqlTestChannelRepositoryProvider)
          .fetchManifest();
      if (!mounted) return;
      setState(() {
        _manifest = manifest;
        _loading = false;
      });
    } on AppUpdateException catch (error) {
      if (!mounted) return;
      setState(() {
        _manifest = null;
        _errorMessage = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _downloadAndInstall() async {
    final manifest = _manifest;
    if (manifest == null || _downloading) return;
    final platform = ref.read(appUpdatePlatformProvider);
    if (!await platform.canRequestPackageInstalls()) {
      await platform.openInstallPermission();
      if (!mounted) return;
      setState(() {
        _errorMessage = '请允许“安装未知应用”后返回此页，再次点击下载安装。';
      });
      return;
    }

    setState(() {
      _downloading = true;
      _errorMessage = null;
      _receivedBytes = 0;
    });
    try {
      final path = await ref
          .read(javaMysqlTestChannelRepositoryProvider)
          .download(
            manifest,
            onProgress: (received, _) {
              if (!mounted) return;
              setState(() => _receivedBytes = received);
            },
          );
      if (!mounted) return;
      await platform.installExternalApk(
        path,
        expectedPackageName: JavaMysqlTestChannelRepository.packageName,
      );
      if (!mounted) return;
      setState(() => _downloading = false);
    } on AppUpdateException catch (error) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _errorMessage = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final manifest = _manifest;
    final progress = manifest == null || manifest.sizeBytes <= 0
        ? 0.0
        : (_receivedBytes / manifest.sizeBytes).clamp(0.0, 1.0);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + bottomInset),
        child: Column(
          key: javaMysqlTestChannelSheetKey,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Java + MySQL 测试版',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '独立安装，不会覆盖或影响当前稳定版。仅适用于愿意协助验证新后端的测试者。',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
            ),
            const SizedBox(height: 18),
            const _RiskLine('当前仍使用 HTTP 测试接口，请勿在不可信网络中使用真实账号。'),
            const _RiskLine('头像跨设备、旧账号密码迁移、聊天与一起听仍在验证。'),
            const _RiskLine('测试包有独立数据；遇到异常请停止测试并反馈。'),
            const SizedBox(height: 20),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: MusicActivityIndicator(independent: true),
                ),
              )
            else if (manifest == null) ...[
              Text(
                _errorMessage ?? '测试通道暂未开放',
                style: TextStyle(color: tokens.textSecondary),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('java-mysql-test-retry'),
                onPressed: _loadManifest,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重新检查'),
              ),
            ] else ...[
              Text(
                '可下载 v${manifest.versionName} · ${manifest.sizeLabel}',
                style: TextStyle(color: tokens.textSecondary),
              ),
              if (_downloading) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 8),
                Text(
                  '正在下载 ${(progress * 100).round()}%',
                  style: TextStyle(color: tokens.textSecondary),
                ),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Color(0xFFC24A34)),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('java-mysql-test-download'),
                  onPressed: _downloading ? null : _downloadAndInstall,
                  icon: Icon(
                    _downloading
                        ? Icons.downloading_rounded
                        : Icons.download_rounded,
                  ),
                  label: Text(_downloading ? '正在下载' : '下载安装测试版'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RiskLine extends StatelessWidget {
  const _RiskLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 17,
            color: tokens.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tokens.textSecondary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
