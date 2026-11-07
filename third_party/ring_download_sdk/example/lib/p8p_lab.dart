// Manual download UI. Uses the same public SDK as host apps, without fixture
// transports, custom certificates, native probe hooks or an APK installer.
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:ring_download_sdk/ring_download_sdk.dart';

void main() => runApp(const P8PDownloadLab());

class P8PDownloadLab extends StatelessWidget {
  const P8PDownloadLab({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'P8P 下载实验室',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff235bd4)),
      useMaterial3: true,
    ),
    home: const P8PLabPage(),
  );
}

class P8PLabPage extends StatefulWidget {
  const P8PLabPage({super.key});
  @override
  State<P8PLabPage> createState() => _P8PLabPageState();
}

class _P8PLabPageState extends State<P8PLabPage> {
  final _url = TextEditingController();
  final _events = <String>[];
  RingDownloadSdk? _sdk;
  RingDownloadTask? _task;
  StreamSubscription<RingDownloadProgress>? _progress;
  String _appId = 'lifering', _status = '准备开始';
  bool _busy = false,
      _cancelled = false,
      _p8p = true,
      _external = false,
      _sharing = true;
  int _received = 0, _total = 0, _seed = 0, _peer = 0;
  String _receipt = '';

  @override
  void dispose() {
    _task?.cancel();
    unawaited(_progress?.cancel() ?? Future<void>.value());
    unawaited(_sdk?.dispose() ?? Future<void>.value());
    _url.dispose();
    super.dispose();
  }

  String _bytes(int bytes) => '${(bytes / 1048576).toStringAsFixed(2)} MiB';

  void _diagnostic(RingDownloadDiagnostic event) {
    if (!mounted) return;
    setState(() {
      _seed = max(_seed, event.seedBytes ?? 0);
      _peer = max(_peer, event.peerBytes ?? 0);
      _events.add('${event.stage} · ${event.code}');
      if (_events.length > 80) _events.removeAt(0);
    });
    debugPrint('P8P_LAB_DIAGNOSTIC ${event.toJson()}');
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _cancelled = false;
      _received = _total = _seed = _peer = 0;
      _receipt = '';
      _events.clear();
      _status = _external ? '开始外部 HTTPS 下载…' : '读取公开 APK 信息…';
    });
    final watch = Stopwatch()..start();
    try {
      // Dispose the preceding idle sharing owner before creating another SDK.
      final previous = _sdk;
      _sdk = null;
      await previous?.dispose();
      if (!mounted || _cancelled) return;
      final sdk = RingDownloadSdk(
        RingDownloadConfig(
          appId: _appId,
          enableP2P: _p8p,
          enableP8P: _p8p,
          allowSharing: _sharing && _p8p,
          onDiagnostic: _diagnostic,
        ),
      );
      _sdk = sdk;
      final request = _external
          ? RingDownloadRequest(url: Uri.parse(_url.text.trim()))
          : await sdk.latestRelease();
      // A cancelled metadata lookup must never start a late download.
      if (!mounted || _cancelled) return;
      final task = sdk.download(request);
      _task = task;
      setState(() => _status = '下载中');
      _progress = task.progress.listen((event) {
        if (!mounted) return;
        setState(() {
          _received = event.receivedBytes;
          _total = event.totalBytes;
          _status = event.state == RingDownloadState.verifying ? '校验中…' : '下载中';
        });
      });
      final receipt = await task.completed;
      await receipt.revalidate();
      if (!mounted) return;
      setState(() {
        _received = receipt.fileSize;
        _status = '下载完成';
        _receipt =
            '用时 ${(watch.elapsedMilliseconds / 1000).toStringAsFixed(2)} 秒'
            '\n文件 ${_bytes(receipt.fileSize)}'
            '\n校验 ${receipt.verification.name}'
            '\nSHA256 ${receipt.sha256}';
      });
      debugPrint(
        'P8P_LAB_COMPLETE ${receipt.fileSize} ${receipt.sha256} '
        '${receipt.verification.name}',
      );
    } on RingDownloadException catch (error) {
      if (mounted) setState(() => _status = '下载结果：${error.code.name}');
    } catch (_) {
      if (mounted) setState(() => _status = '下载失败，请检查链接和网络');
    } finally {
      await _progress?.cancel();
      _progress = null;
      _task = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  void _cancel() {
    if (!_busy) return;
    _cancelled = true;
    _task?.cancel();
    // Metadata lookup has no task yet. Its completion checks this flag.
    if (_task == null) {
      setState(() {
        _status = '已取消，正在结束请求';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('P8P 下载实验室')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('手动测试包 · SDK ${RingSdkStatus.sdkVersion}'),
          const SizedBox(height: 8),
          const Text('HTTPS 立即下载，有可用节点时 P8P 介入。此包只下载和校验，不安装下载到的 APK。'),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _appId,
            decoration: const InputDecoration(labelText: '公开应用'),
            items: const [
              DropdownMenuItem(value: 'lifering', child: Text('LifeRing')),
              DropdownMenuItem(value: 'wedo', child: Text('WeDo')),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() => _appId = value!),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启用 P8P 协作'),
            subtitle: const Text('关闭后使用 HTTPS；开启不代表本次一定有 P8P 字节'),
            value: _p8p,
            onChanged: _busy
                ? null
                : (value) {
                    _sdk?.setSharingEnabled(_sharing && value);
                    setState(() => _p8p = value);
                  },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('前台 Wi-Fi 分享'),
            subtitle: const Text('仅授权且前台、非计费 Wi-Fi、文件已校验时上传；后台和蜂窝不上传'),
            value: _sharing,
            onChanged: (value) {
              _sdk?.setSharingEnabled(value && _p8p);
              setState(() => _sharing = value);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('测试外部 COS / CDN 链接'),
            subtitle: const Text('直接 HTTPS，不查询本站 health；只填 HTTPS 链接即可'),
            value: _external,
            onChanged: _busy
                ? null
                : (value) => setState(() => _external = value),
          ),
          if (_external)
            TextField(
              controller: _url,
              enabled: !_busy,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: '外部 HTTPS 下载地址'),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _busy ? null : _start,
                child: const Text('开始 / 续传下载'),
              ),
              OutlinedButton(
                onPressed: _busy ? _cancel : null,
                child: const Text('取消下载'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(_status, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_busy || _received > 0)
            LinearProgressIndicator(
              value: _total > 0 ? (_received / _total).clamp(0, 1) : null,
            ),
          const SizedBox(height: 8),
          Text(
            '${_bytes(_received)} / ${_total > 0 ? _bytes(_total) : "总大小未知"}',
          ),
          Text('已校验种子数据 ${_bytes(_seed)} · 用户互传 ${_bytes(_peer)}'),
          if (_receipt.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SelectableText(_receipt),
            ),
          const Divider(height: 30),
          Text('最近事件', style: Theme.of(context).textTheme.titleSmall),
          const Text('完成收据代表文件下载完成；来源字节用于诊断，不用于判断整包成功。'),
          for (final event in _events.reversed.take(24)) Text(event),
        ],
      ),
    ),
  );
}
