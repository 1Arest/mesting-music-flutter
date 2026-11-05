import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:http/http.dart' as http;

import 'data/embedded_music_server.dart';
import 'data/music_platform_api.dart';
import 'data/platform_session_store.dart';
import 'data/kugou_account_store.dart';
import 'domain/platform_session.dart';
import '../../core/platform/distribution_channel.dart';
import '../../core/performance/startup_timing_probe.dart';
import '../auth/beta_account_choice.dart';
import '../auth/beta_entry_flow.dart';
import 'netease/netease_providers.dart';
import 'netease/netease_session.dart';
import 'retained_kugou_scope.dart';

final musicServerProvider = Provider<MusicServer>(
  (ref) => EmbeddedMusicServer(),
);
final platformSessionStoreProvider = Provider<PlatformSessionStore>(
  (ref) => SecureKugouAccountStore(),
);

/// 只向页面公开昵称等展示资料，凭据仍由加密仓库及切换协调层持有。
final savedKugouAccountsProvider = FutureProvider<List<KugouSavedAccount>>((
  ref,
) async {
  final store = ref.watch(platformSessionStoreProvider);
  ref.watch(retainedKugouMutationProvider);
  if (store is KugouAccountStore) return (await store.snapshot()).accounts;
  final session = await store.read();
  return session == null
      ? const []
      : [
          KugouSavedAccount(
            userId: session.userId,
            nickname: session.nickname,
            avatarUrl: session.avatarUrl,
          ),
        ];
}, retry: (_, _) => null);
final musicPlatformApiProvider = Provider<MusicPlatformApi>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return MusicPlatformApi(
    server: ref.watch(musicServerProvider),
    client: client,
  );
});

final platformAccountProvider =
    AsyncNotifierProvider<PlatformAccountController, PlatformSession?>(
      PlatformAccountController.new,
      // Recovery is user-driven after the bounded storage retries. Riverpod's
      // default build retry keeps .future pending on a permanent format error
      // and prevents the explicit fresh-login replacement from proceeding.
      retry: (retryCount, error) => null,
    );

/// A separate controller deliberately never reads authControllerProvider.
/// Storage operations run in order so a slow login write cannot resurrect a
/// credential after a later logout has already removed it.
class PlatformAccountController extends AsyncNotifier<PlatformSession?> {
  Future<void> _pendingMutation = Future<void>.value();

  /// Installed by the application audio binding. Keeping this boundary injected
  /// makes authentication/storage testable without constructing a second player.
  Future<void> Function(String ownerId)? preparePlatformSwitch;

  Future<void> _prepare(String ownerId) async {
    await preparePlatformSwitch?.call(ownerId);
  }

  void _publish(PlatformSession? session) {
    // Kugou transports must never see a NetEase cookie or public projection.
    ref.read(musicPlatformApiProvider).session =
        session?.platform == MusicPlatform.netease ? null : session;
    if (session?.platform != MusicPlatform.netease) {
      ref.read(neteaseApiProvider).configure(null);
    }
    state = AsyncData(session);
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final result = _pendingMutation.then((_) => operation());
    // Failure must reach the caller, while releasing the queue for retries.
    _pendingMutation = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  Future<PlatformSession?> build() async {
    if (DistributionChannel.isBeta) {
      ref.listen(betaAccountChoiceProvider, (previous, choice) {
        if (choice == BetaAccountChoice.mesting ||
            choice == BetaAccountChoice.guest) {
          _publish(null);
        }
      });
      final choice = ref.read(betaAccountChoiceProvider);
      if (choice == BetaAccountChoice.mesting ||
          choice == BetaAccountChoice.guest) {
        return null;
      }
    }
    final PlatformSession? session;
    try {
      if (ref.read(betaAccountChoiceProvider) == BetaAccountChoice.netease) {
        final saved = await ref
            .read(neteaseSessionStoreProvider)
            .read()
            .timeout(const Duration(seconds: 5));
        ref.read(musicPlatformApiProvider).session = null;
        ref.read(neteaseApiProvider).configure(saved);
        return saved?.identity;
      }
      session = await ref
          .watch(platformSessionStoreProvider)
          .read()
          .timeout(const Duration(seconds: 5));
    } on Object catch (error) {
      // An opt-in diagnostic records categories only. Exception messages and
      // encrypted/decrypted account values must never enter timing logs.
      if (StartupTimingProbe.enabled) {
        final code = error is PlatformException
            ? '_${error.code.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '')}'
            : '';
        StartupTimingProbe.mark('account_error_${error.runtimeType}$code');
      }
      rethrow;
    }
    StartupTimingProbe.mark('account_storage_ready');
    if (session != null && DistributionChannel.isBeta) {
      // On upgrade, prefer the existing platform identity when no choice was
      // saved by Beta.1. No CloudBase request is needed to make that decision.
      final choice = ref.read(betaAccountChoiceProvider);
      if (choice == BetaAccountChoice.mesting ||
          choice == BetaAccountChoice.guest) {
        return null;
      }
      await ref
          .read(betaAccountChoiceProvider.notifier)
          .select(BetaAccountChoice.kugou);
    }
    ref.read(musicPlatformApiProvider).session = session;
    return session;
  }

  /// Only explicit login UI calls this boundary. A restoration failure is
  /// retryable and must not prevent a new, platform-confirmed authentication.
  /// Old encrypted bytes remain untouched until accept durably writes new ones.
  Future<void> readyForInteractiveLogin() async {
    if (state.hasError) return;
    try {
      await future;
    } on Object {
      if (!ref.mounted || !state.hasError) rethrow;
    }
  }

  Future<void> accept(
    Map<String, dynamic> result, {
    String? loginMethod,
  }) => _serialize(() async {
    // Initialization must settle before a fresh login may replace its state.
    await readyForInteractiveLogin();
    if (DistributionChannel.isBeta &&
        ref.read(betaAccountChoiceProvider) == BetaAccountChoice.mesting) {
      throw const MusicPlatformException('请先退出当前 Mesting 账号');
    }
    final hadAccount = state.value != null;
    final session = PlatformSession.fromJson(
      {...result}
        ..remove('mesting_kugou_standard_token')
        ..remove('mesting_kugou_standard_vip_token'),
    );
    await _selectKugou(session, loginMethod: loginMethod);
    if (DistributionChannel.isBeta && !hadAccount) {
      ref.read(betaEntryFlowProvider.notifier).authenticated();
    }
  });

  /// 先冻结旧账号的真实播放，再提交登录快照，最后一次性发布新归属。
  /// 偏好/安全存储失败会回滚登录选择，绝不把两账号队列或在途响应混合。
  Future<void> _selectKugou(
    PlatformSession session, {
    String? loginMethod,
    bool Function()? isCurrent,
  }) async {
    void check() {
      if (isCurrent != null && !isCurrent()) {
        throw const MusicPlatformException('授权已取消，请重新打开验证');
      }
    }

    check();
    final store = ref.read(platformSessionStoreProvider);
    var committed = session;
    final previous = await store.read();
    final snapshot = store is KugouAccountStore ? await store.snapshot() : null;
    final choice = ref.read(betaAccountChoiceProvider);
    check();
    if (state.value?.ownerId != session.ownerId) {
      await _prepare(session.ownerId);
    }
    try {
      if (store is KugouAccountStore) {
        await store.select(session, loginMethod: loginMethod);
        committed = await store.read() ?? (throw StateError('账号保存未完成，请重试'));
      } else {
        await store.write(session);
      }
      check();
      if (DistributionChannel.isBeta) {
        await ref
            .read(betaAccountChoiceProvider.notifier)
            .select(BetaAccountChoice.kugou);
      }
      check();
    } catch (_) {
      if (snapshot != null && store is KugouAccountStore) {
        await store.restore(snapshot);
      } else if (previous != null) {
        await store.write(previous);
      }
      if (choice != null && ref.read(betaAccountChoiceProvider) != choice) {
        await ref.read(betaAccountChoiceProvider.notifier).select(choice);
      }
      rethrow;
    }
    ref.read(retainedKugouMutationProvider.notifier).publish(committed);
    ref.invalidate(savedKugouSessionProvider);
    _publish(committed);
  }

  Future<void> switchKugouAccount(String userId) => _serialize(() async {
    await readyForInteractiveLogin();
    if (state.value?.platform == MusicPlatform.kugou &&
        state.value?.userId == userId) {
      return;
    }
    final store = ref.read(platformSessionStoreProvider);
    final session = store is KugouAccountStore
        ? await store.account(userId)
        : await store.read();
    if (session == null || session.userId != userId) {
      throw const MusicPlatformException('该账号的本机登录已移除，请重新添加');
    }
    if (ref.read(betaAccountChoiceProvider) == BetaAccountChoice.mesting) {
      throw const MusicPlatformException('请先退出当前 Mesting 账号');
    }
    await _selectKugou(session);
  });

  /// 标准版重新验证必须属于发起验证的同一UID及同一主登录周期。
  /// 补充凭据不更换音乐协议、音乐库归属或播放队列。
  Future<void> acceptKugouStandard(
    Map<String, dynamic> result, {
    required PlatformSession expected,
    bool Function()? isCurrent,
  }) => _serialize(() async {
    await readyForInteractiveLogin();
    if (isCurrent != null && !isCurrent()) {
      throw const MusicPlatformException('授权已取消，请重新打开验证');
    }
    final current = state.value;
    final verified = PlatformSession.fromJson(result);
    if (current?.platform != MusicPlatform.kugou ||
        current?.userId != expected.userId ||
        current?.token != expected.token ||
        current?.kugouStandardToken != expected.kugouStandardToken ||
        result['mesting_kugou_appid'] != 1005 ||
        verified.userId != expected.userId) {
      throw const MusicPlatformException('请使用当前酷狗账号完成验证；账号已变化时请重新打开');
    }
    await _selectKugou(
      PlatformSession(
        userId: current!.userId,
        token: current.token,
        vipToken: current.vipToken,
        nickname: current.nickname,
        avatarUrl: current.avatarUrl,
        kugouStandardToken: verified.token,
        kugouStandardVipToken: verified.vipToken,
      ),
      isCurrent: isCurrent,
    );
  });

  Future<void> removeKugouAccount(String userId) => _serialize(() async {
    await readyForInteractiveLogin();
    // 当前账号通过原有退出流程移除，保留欢迎/路由归位和暂停契约。
    if (state.value?.platform == MusicPlatform.kugou &&
        state.value?.userId == userId) {
      throw const MusicPlatformException('请先退出当前账号，再从列表移除');
    }
    final store = ref.read(platformSessionStoreProvider);
    if (store is! KugouAccountStore) return;
    await store.remove(userId);
    ref.invalidate(savedKugouAccountsProvider);
  });

  Future<void> acceptNetease(NeteaseSession session) => _serialize(() async {
    await readyForInteractiveLogin();
    if (ref.read(betaAccountChoiceProvider) == BetaAccountChoice.mesting) {
      throw const MusicPlatformException('请先退出当前 Mesting 账号');
    }
    final hadAccount = state.value != null;
    await ref.read(neteaseSessionStoreProvider).write(session);
    ref.read(retainedNeteaseEpochProvider.notifier).advance();
    await _prepare(session.identity.ownerId);
    await ref
        .read(betaAccountChoiceProvider.notifier)
        .select(BetaAccountChoice.netease);
    ref.read(neteaseApiProvider).configure(session);
    _publish(session.identity);
    if (!hadAccount) ref.read(betaEntryFlowProvider.notifier).authenticated();
  });

  /// Read the retained credential before changing anything visible. Selecting
  /// another platform never clears either store; logout alone erases a login.
  Future<void> switchPlatform(MusicPlatform platform) => _serialize(() async {
    await readyForInteractiveLogin();
    if (state.value?.platform == platform) return;
    final netease = platform == MusicPlatform.netease
        ? await ref.read(neteaseSessionStoreProvider).read()
        : null;
    final next = platform == MusicPlatform.kugou
        ? await ref.read(platformSessionStoreProvider).read()
        : netease?.identity;
    if (next == null) throw const MusicPlatformException('请先登录该平台');
    await _prepare(next.ownerId);
    await ref
        .read(betaAccountChoiceProvider.notifier)
        .select(
          platform == MusicPlatform.kugou
              ? BetaAccountChoice.kugou
              : BetaAccountChoice.netease,
        );
    ref.read(neteaseApiProvider).configure(netease);
    _publish(next);
  });

  Future<PlatformSession?> retainedIdentity(MusicPlatform platform) async {
    if (platform == MusicPlatform.kugou) {
      return ref
          .read(platformSessionStoreProvider)
          .read()
          .timeout(const Duration(seconds: 5));
    }
    return (await ref
            .read(neteaseSessionStoreProvider)
            .read()
            .timeout(const Duration(seconds: 5)))
        ?.identity;
  }

  /// Refresh display metadata without re-authenticating or replaying onboarding.
  /// A profile response from a previous account cannot replace a new session.
  Future<void> updateProfileMetadata(
    PlatformSession expected, {
    String? nickname,
    String? avatarUrl,
  }) => _serialize(() async {
    final current = await future;
    if (current?.ownerId != expected.ownerId ||
        current?.token != expected.token) {
      throw const MusicPlatformException('账号已变化，请返回后重新操作');
    }
    if (current!.platform == MusicPlatform.netease) {
      final saved = await ref.read(neteaseSessionStoreProvider).read();
      if (saved == null ||
          saved.identity.ownerId != current.ownerId ||
          saved.credentialId != current.token) {
        throw const MusicPlatformException('账号已变化，请重新登录');
      }
      final updated = NeteaseSession(
        userId: saved.userId,
        cookies: saved.cookies,
        deviceId: saved.deviceId,
        nickname: nickname ?? saved.nickname,
        avatarUrl: avatarUrl?.isNotEmpty == true ? avatarUrl! : saved.avatarUrl,
      );
      await ref.read(neteaseSessionStoreProvider).write(updated);
      ref.read(retainedNeteaseEpochProvider.notifier).advance();
      _publish(updated.identity);
      return;
    }
    final updated = PlatformSession(
      userId: current.userId,
      token: current.token,
      vipToken: current.vipToken,
      kugouStandardToken: current.kugouStandardToken,
      kugouStandardVipToken: current.kugouStandardVipToken,
      nickname: nickname ?? current.nickname,
      avatarUrl: avatarUrl?.isNotEmpty == true ? avatarUrl! : current.avatarUrl,
    );
    await ref.read(platformSessionStoreProvider).write(updated);
    ref.read(retainedKugouMutationProvider.notifier).publish(updated);
    ref.invalidate(savedKugouSessionProvider);
    _publish(updated);
  });

  /// Refresh in a private jar and commit only after secure-store readback.
  /// A failed refresh leaves the currently working credential untouched.
  Future<void> refreshNetease() => _serialize(() async {
    final current = await future;
    final saved = await ref.read(neteaseSessionStoreProvider).read();
    if (current?.platform != MusicPlatform.netease ||
        saved == null ||
        saved.credentialId != current?.token) {
      throw const MusicPlatformException('请先登录网易云账号');
    }
    final client = ref.read(neteaseApiProvider).loginClient()..configure(saved);
    await client.call('/login/refresh', expectedCredential: saved.credentialId);
    final updated = NeteaseSession(
      userId: saved.userId,
      cookies: client.cookies,
      deviceId: saved.deviceId,
      nickname: saved.nickname,
      avatarUrl: saved.avatarUrl,
    );
    await ref.read(neteaseSessionStoreProvider).write(updated);
    ref.read(retainedNeteaseEpochProvider.notifier).advance();
    ref.read(neteaseApiProvider).configure(updated);
    _publish(updated.identity);
  });

  Future<void> signOut() => _serialize(() async {
    await future;
    // Remove the credential before publishing guest state; failure remains
    // visible so the UI never falsely promises the credential was removed.
    await _prepare('local');
    if (state.value?.platform == MusicPlatform.netease) {
      await ref.read(neteaseSessionStoreProvider).clear();
      ref.read(retainedNeteaseEpochProvider.notifier).advance();
      ref.read(neteaseApiProvider).configure(null);
    } else {
      await ref.read(platformSessionStoreProvider).clear();
      ref.read(retainedKugouMutationProvider.notifier).publish(null);
      ref.invalidate(savedKugouSessionProvider);
    }
    if (DistributionChannel.isBeta) {
      await ref
          .read(betaAccountChoiceProvider.notifier)
          .select(BetaAccountChoice.guest);
    }
    _publish(null);
    if (DistributionChannel.isBeta) {
      await ref.read(betaEntryFlowProvider.notifier).welcome();
    }
  });
}

enum PlatformLoginMethod { kugouQr, phone, wechatQr, qqQr }

class PlatformQrChallenge {
  const PlatformQrChallenge({
    required this.method,
    required this.parameters,
    required this.imageBase64,
  });
  final PlatformLoginMethod method;
  final Map<String, String> parameters;
  final String imageBase64;
}

/// Stateless login protocol adapter. The page owns cancellation/generation,
/// while only PlatformAccountController is allowed to persist credentials.
class PlatformLoginService {
  PlatformLoginService(this.api);
  final MusicPlatformApi api;

  Future<PlatformQrChallenge> createQr(PlatformLoginMethod method) async {
    switch (method) {
      case PlatformLoginMethod.kugouQr:
        final keyResult = await api.get('/login/qr/key');
        final key = MusicPlatformApi.objectMap(keyResult['data'])['qrcode'];
        if (key == null || '$key'.isEmpty) {
          throw const MusicPlatformException('无法生成酷狗二维码，请重试');
        }
        final result = await api.get(
          '/login/qr/create',
          query: {'key': '$key', 'qrimg': 'true'},
        );
        final image = MusicPlatformApi.objectMap(result['data'])['base64'];
        return _challenge(method, {'key': '$key'}, image);
      case PlatformLoginMethod.wechatQr:
        final result = await api.get('/login/wx/create');
        final image = MusicPlatformApi.objectMap(
          result['qrcode'],
        )['qrcodebase64'];
        final uuid = '${result['uuid'] ?? ''}';
        if (uuid.isEmpty) throw const MusicPlatformException('微信二维码会话缺失');
        return _challenge(method, {'uuid': uuid}, image);
      case PlatformLoginMethod.qqQr:
        final result = await api.get('/login/qq/qr/create');
        const fields = [
          'qrsig',
          'ptqrtoken',
          'pt_login_sig',
          'pt_openlogin_data',
          'xlogin_url',
          'cookie',
        ];
        final parameters = <String, String>{};
        for (final field in fields) {
          final value = '${result[field] ?? ''}';
          if (value.isEmpty) throw const MusicPlatformException('QQ 二维码会话缺失');
          parameters[field] = value;
        }
        return _challenge(method, parameters, result['qrcode']);
      case PlatformLoginMethod.phone:
        throw ArgumentError('Phone login does not use a QR challenge');
    }
  }

  PlatformQrChallenge _challenge(
    PlatformLoginMethod method,
    Map<String, String> parameters,
    Object? image,
  ) {
    final value = '${image ?? ''}'.split(',').last;
    if (value.isEmpty) throw const MusicPlatformException('二维码图片暂时不可用，请刷新');
    try {
      base64Decode(value);
    } on FormatException {
      throw const MusicPlatformException('二维码图片格式异常，请刷新');
    }
    return PlatformQrChallenge(
      method: method,
      parameters: parameters,
      imageBase64: value,
    );
  }

  /// Returns a credential only after the platform reports completed login.
  /// Pending scans return null; terminal states stop polling with a safe error.
  Future<Map<String, dynamic>?> poll(PlatformQrChallenge challenge) async {
    final path = switch (challenge.method) {
      PlatformLoginMethod.kugouQr => '/login/qr/check',
      PlatformLoginMethod.wechatQr => '/login/wx/check',
      PlatformLoginMethod.qqQr => '/login/qq/qr/check',
      PlatformLoginMethod.phone => throw StateError('No QR session'),
    };
    var result = await api.get(
      path,
      query: {
        ...challenge.parameters,
        'timestamp': '${DateTime.now().millisecondsSinceEpoch}',
      },
      allowBusinessError: true,
    );
    var data = MusicPlatformApi.objectMap(result['data'] ?? result);
    if (challenge.method == PlatformLoginMethod.wechatQr) {
      final code = '${result['wx_errcode'] ?? ''}';
      if (code == '405') {
        final wxCode = '${result['wx_code'] ?? ''}';
        if (wxCode.isEmpty) throw const MusicPlatformException('微信授权信息缺失，请重试');
        result = await api.get('/login/openplat', query: {'code': wxCode});
        data = MusicPlatformApi.objectMap(result['data']);
      } else if (code == '402' || code == '403') {
        throw const MusicPlatformException('二维码已过期或授权已取消，请刷新');
      } else if (code == '408' || code == '404') {
        return null;
      } else {
        throw const MusicPlatformException('微信扫码状态异常，请刷新重试');
      }
    }
    if (challenge.method == PlatformLoginMethod.kugouQr) {
      final status = '${data['status'] ?? ''}';
      if (status == '800' || status == '0') {
        throw const MusicPlatformException('二维码已过期，请刷新');
      }
      if (status != '4') return null;
    }
    if (data['token'] != null &&
        data['userid'] != null &&
        (challenge.method != PlatformLoginMethod.qqQr ||
            '${result['status']}' == '1')) {
      return data;
    }
    if (challenge.method == PlatformLoginMethod.qqQr) {
      final code = '${result['code'] ?? result['ptui_code'] ?? ''}';
      // The Rust adapter uses string statuses for pending and terminal scans.
      // Stop on expiry/rejection instead of polling a dead session for minutes.
      final status = '${result['status'] ?? ''}';
      if (code == '65' ||
          status == 'expired' ||
          status == 'blocked' ||
          result['error'] != null) {
        throw const MusicPlatformException('QQ 扫码未能完成，请刷新或选择其他登录方式');
      }
    }
    return null;
  }

  Future<void> sendCode(String phone) async {
    if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
      throw const MusicPlatformException('请输入正确的 11 位手机号');
    }
    await api.ensureRegisteredDevice();
    final result = await api.get(
      '/captcha/sent',
      query: {'mobile': phone},
      allowBusinessError: true,
    );
    if ('${result['status']}' != '1') {
      final code = '${result['error_code'] ?? result['errcode'] ?? ''}';
      throw MusicPlatformException(
        code == '20015' ? '平台拒绝了验证码请求（20015），请核对手机号后重试' : '验证码未发送成功，请稍后重试',
        code: code,
      );
    }
  }

  Future<Map<String, dynamic>> phoneLogin(
    String phone,
    String code, {
    String? userId,
  }) => api.get(
    '/login/cellphone',
    query: {'mobile': phone, 'code': code, 'userid': ?userId},
    allowBusinessError: true,
  );
}
