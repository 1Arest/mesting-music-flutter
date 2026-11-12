import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';

import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_music_chrome_scope.dart';
import '../../../shared/widgets/beta_page_motion.dart';
import '../data/kugou_official_api.dart';
import '../data/kugou_standard_login.dart';
import '../domain/platform_session.dart';
import '../music_platform_providers.dart';
import '../kugou_listening_profile_providers.dart';
import '../../../core/network/music_http_client.dart';
import '../../themes/music_typography.dart';

/// 生产复用本机注册设备；测试可注入响应，不需要访问手机或真实账号。
final kugouStandardAuthorizationClientFactoryProvider =
    Provider<http.Client Function()>((ref) => MusicHttpClient.new);
final kugouStandardAuthorizationDeviceProvider =
    Provider<Future<Map<String, String>> Function()>((ref) {
      final api = ref.watch(musicPlatformApiProvider);
      return () => KugouOfficialApi.registeredDevice(api);
    });

Future<bool> openKugouStandardAuthorization(
  BuildContext context,
  PlatformSession owner,
) async {
  final accepted =
      await Navigator.of(context).push<bool>(
        betaContentRoute(KugouStandardAuthorizationPage(owner: owner)),
      ) ==
      true;
  if (accepted && context.mounted) {
    // Re-read the current reader outside route build. Same-token verification
    // must retry a cached failure too; invalidating a provider while its route
    // subscription is paused can race TickerMode's reactivation.
    final reader = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(kugouListeningProfileReaderProvider);
    unawaited(reader?.loadOverview(force: true));
  }
  return accepted;
}

/// 为当前UID补充标准客户端授权。扫码期间不更换主登录，也不恢复/重置播放。
class KugouStandardAuthorizationPage extends ConsumerStatefulWidget {
  const KugouStandardAuthorizationPage({required this.owner, super.key});
  final PlatformSession owner;
  @override
  ConsumerState<KugouStandardAuthorizationPage> createState() =>
      _StandardAuthorizationState();
}

class _StandardAuthorizationState
    extends ConsumerState<KugouStandardAuthorizationPage> {
  http.Client? _client;
  KugouStandardQrChallenge? _challenge;
  bool _loading = false, _polling = false;
  bool _revoked = false;
  int _generation = 0;
  String? _message;
  String? _committingToken;
  Timer? _delay;
  Completer<void>? _waiting;

  bool get _current {
    if (!mounted || _revoked) return false;
    final owner = ref.read(platformAccountProvider).value;
    return owner?.platform == MusicPlatform.kugou &&
        owner?.userId == widget.owner.userId &&
        owner?.token == widget.owner.token &&
        owner?.kugouStandardToken == widget.owner.kugouStandardToken;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _cancelDelay() {
    _delay?.cancel();
    _delay = null;
    final pending = _waiting;
    _waiting = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  Future<void> _pause() async {
    _cancelDelay();
    final done = _waiting = Completer<void>();
    _delay = Timer(const Duration(seconds: 2), () {
      if (!done.isCompleted) done.complete();
    });
    await done.future;
    if (identical(_waiting, done)) {
      _waiting = null;
      _delay = null;
    }
  }

  Future<void> _start() async {
    if (!_current) return;
    final generation = ++_generation;
    _cancelDelay();
    _client?.close();
    final client = _client = ref.read(
      kugouStandardAuthorizationClientFactoryProvider,
    )();
    setState(() {
      _loading = true;
      _polling = false;
      _challenge = null;
      _message = null;
    });
    final service = KugouStandardLoginService(
      client: client,
      device: ref.read(kugouStandardAuthorizationDeviceProvider),
      current: () => generation == _generation && _current,
    );
    try {
      final challenge = await service.createQr();
      if (!_current || generation != _generation) return;
      setState(() {
        _challenge = challenge;
        _loading = false;
        _polling = true;
        _message = '请使用当前酷狗账号扫码，并在官版中确认';
      });
      while (_current &&
          generation == _generation &&
          DateTime.now().isBefore(challenge.expiresAt)) {
        await _pause();
        if (!_current || generation != _generation) return;
        final result = await service.poll(challenge);
        if (!_current || generation != _generation) return;
        if (result == null) continue;
        _committingToken = '${result['token'] ?? ''}';
        try {
          await ref
              .read(platformAccountProvider.notifier)
              .acceptKugouStandard(
                result,
                expected: widget.owner,
                isCurrent: () =>
                    mounted && !_revoked && generation == _generation,
              );
        } finally {
          _committingToken = null;
        }
        if (mounted && generation == _generation) {
          Navigator.of(context).pop(true);
        }
        return;
      }
      if (mounted && generation == _generation) {
        setState(() {
          _polling = false;
          _message = '二维码已过期，请刷新后重新扫码';
        });
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _polling = false;
          _message = error is KugouOfficialException
              ? error.message
              : error is KugouStandardLoginException
              ? error.message
              : '验证未完成，请确认使用同一酷狗账号后重试';
        });
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _cancelDelay();
    _client?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(platformAccountProvider, (_, next) {
      final active = next.value;
      if (_committingToken != null &&
          active?.platform == MusicPlatform.kugou &&
          active?.userId == widget.owner.userId &&
          active?.token == widget.owner.token &&
          active?.kugouStandardToken == _committingToken) {
        return;
      }
      if (active?.platform != MusicPlatform.kugou ||
          active?.userId != widget.owner.userId ||
          active?.token != widget.owner.token ||
          active?.kugouStandardToken != widget.owner.kugouStandardToken) {
        _revoked = true;
        _generation++;
        _cancelDelay();
        _client?.close();
      }
    });
    final active = ref.watch(platformAccountProvider).value;
    final same =
        !_revoked &&
        active?.platform == MusicPlatform.kugou &&
        active?.userId == widget.owner.userId &&
        active?.token == widget.owner.token &&
        active?.kugouStandardToken == widget.owner.kugouStandardToken;
    return BetaMusicChromeCover(
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                child: Row(
                  children: [
                    const BetaGlassBackButton(),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        '验证酷狗官方功能',
                        style: TextStyle(
                          fontSize: MusicTypography.sectionTitleSize,
                          fontWeight: MusicTypography.titleWeight,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      widget.owner.nickname.isEmpty
                          ? '当前酷狗账号'
                          : widget.owner.nickname,
                      style: const TextStyle(
                        fontSize: MusicTypography.titleSize,
                        fontWeight: MusicTypography.titleWeight,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '使用官版酷狗扫码，为这个账号开启听歌统计、等级和徽章所需的授权。音乐库、队列和进度会保留。',
                      style: TextStyle(height: 1.6),
                    ),
                    const SizedBox(height: 24),
                    if (!same)
                      const Text('当前账号已变化，请返回后重新打开。')
                    else if (_loading)
                      const Center(child: BetaActivityIndicator())
                    else if (_challenge != null)
                      Center(
                        child: Container(
                          color: Colors.white,
                          padding: const EdgeInsets.all(16),
                          child: QrImageView(
                            data: _challenge!.qrcodeData,
                            size: 230,
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    if (_message != null && same)
                      Text(_message!, textAlign: TextAlign.center),
                    if (_polling && same)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                          child: BetaActivityIndicator(label: '等待扫码确认'),
                        ),
                      ),
                    const SizedBox(height: 18),
                    if (same)
                      Center(
                        child: TextButton(
                          onPressed: _loading ? null : _start,
                          child: const Text('刷新二维码'),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
