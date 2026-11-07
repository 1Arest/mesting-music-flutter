import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/auth/auth_providers.dart';
import 'package:mesting_music/features/auth/data/auth_repository.dart';
import 'package:mesting_music/features/auth/domain/auth_models.dart';

void main() {
  test('账号后端状态文案与实际连接模式一致', () {
    expect(
      authBackendStatusLabel(AuthBackendKind.cloudBase),
      'CloudBase 身份认证已连接',
    );
    expect(authBackendStatusLabel(AuthBackendKind.customApi), '云端账号服务已连接');
    expect(authBackendStatusLabel(AuthBackendKind.localPreview), '本机预览模式');
  });

  test('冷启动先发布缓存账号，再在后台更新云端资料', () async {
    final repository = _BackgroundRefreshRepository();
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final restored = await container.read(authControllerProvider.future);

    expect(restored?.user.nickname, '缓存昵称');
    expect(container.read(currentUserProvider)?.nickname, '缓存昵称');
    await repository.refreshStarted.future;
    expect(container.read(currentUserProvider)?.nickname, '缓存昵称');

    repository.refreshGate.complete(
      repository.cached.copyWith(
        user: repository.cached.user.copyWith(nickname: '云端昵称'),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(currentUserProvider)?.nickname, '云端昵称');
  });

  test('访问令牌过期后并发请求只续期一次并更新全局会话', () async {
    final repository = _RenewingRepository();
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(authControllerProvider.future);
    final controller = container.read(authControllerProvider.notifier);
    final first = controller.ensureFreshSession();
    final second = controller.ensureFreshSession();

    await repository.renewStarted.future;
    expect(repository.renewCalls, 1);
    repository.renewGate.complete(repository.fresh);

    expect((await first)?.accessToken, 'fresh-access');
    expect((await second)?.accessToken, 'fresh-access');
    expect(
      container.read(authControllerProvider).value?.accessToken,
      'fresh-access',
    );
  });
}

class _BackgroundRefreshRepository extends UnconfiguredAuthRepository
    implements BackgroundRefreshAuthRepository {
  _BackgroundRefreshRepository();

  final cached = AuthSession(
    user: const AuthUser(uid: 'cached-user', nickname: '缓存昵称'),
    accessToken: 'cached-access',
    refreshToken: 'cached-refresh',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
  );
  final refreshStarted = Completer<void>();
  final refreshGate = Completer<AuthSession?>();

  @override
  Future<AuthSession?> restoreSession() async => cached;

  @override
  Future<AuthSession?> refreshRestoredSession() {
    refreshStarted.complete();
    return refreshGate.future;
  }
}

class _RenewingRepository extends UnconfiguredAuthRepository
    implements RenewableAuthRepository {
  final expired = AuthSession(
    user: const AuthUser(uid: 'renew-user', nickname: '续期用户'),
    accessToken: 'expired-access',
    refreshToken: 'rotating-refresh',
    expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
  );
  final fresh = AuthSession(
    user: const AuthUser(uid: 'renew-user', nickname: '续期用户'),
    accessToken: 'fresh-access',
    refreshToken: 'fresh-refresh',
    expiresAt: DateTime.now().add(const Duration(hours: 2)),
  );
  final renewStarted = Completer<void>();
  final renewGate = Completer<AuthSession?>();
  int renewCalls = 0;

  @override
  Future<AuthSession?> restoreSession() async => expired;

  @override
  Future<AuthSession?> renewSession() {
    renewCalls += 1;
    if (!renewStarted.isCompleted) renewStarted.complete();
    return renewGate.future;
  }
}
