import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/persistence/app_preferences.dart';
import '../../core/platform/distribution_channel.dart';
import 'beta_account_choice.dart';
import 'beta_entry_flow.dart';
import '../../core/security/session_store.dart';
import '../library/library_providers.dart';
import 'data/auth_repository.dart';
import 'data/cloudbase_auth_repository.dart';
import 'domain/auth_models.dart';

/// Optional build-time override for the Java/MySQL-compatible account API.
///
/// Keeping this empty in a normal build prevents a test endpoint from being
/// selected accidentally by the stable client.
final authApiBaseUrlProvider = Provider<String>((ref) {
  return const String.fromEnvironment('AUTH_API_BASE_URL').trim();
});

enum AuthBackendKind { customApi, cloudBase, localPreview }

const cloudBaseEnvironmentId = String.fromEnvironment(
  'CLOUDBASE_ENV_ID',
  defaultValue: 'mesting-d5gm7tuhxacddccfb',
);

const useCloudBaseAuth = bool.fromEnvironment(
  'USE_CLOUDBASE_AUTH',
  defaultValue: false,
);

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

/// Chooses exactly one authentication backend for the running build.
///
/// Explicit API injection wins for integration testing; otherwise release (or
/// opted-in) builds use CloudBase and debug builds fall back to device-only
/// preview data. Do not merge these branches: their account stores are not
/// interchangeable.
final authBackendKindProvider = Provider<AuthBackendKind>((ref) {
  final baseUrl = ref.watch(authApiBaseUrlProvider);
  if (baseUrl.isNotEmpty) return AuthBackendKind.customApi;
  if (kReleaseMode || useCloudBaseAuth) {
    return AuthBackendKind.cloudBase;
  }
  return AuthBackendKind.localPreview;
});

String authBackendStatusLabel(AuthBackendKind kind) {
  return switch (kind) {
    AuthBackendKind.customApi => '云端账号服务已连接',
    AuthBackendKind.cloudBase => 'CloudBase 身份认证已连接',
    AuthBackendKind.localPreview => '本机预览模式',
  };
}

/// Creates the repository matching [authBackendKindProvider].
///
/// Downstream UI depends only on [AuthRepository], which keeps credential and
/// session handling consistent while deployment backends evolve separately.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return switch (ref.watch(authBackendKindProvider)) {
    AuthBackendKind.customApi => HttpAuthRepository(
      baseUrl: ref.watch(authApiBaseUrlProvider),
      sessionStore: ref.watch(sessionStoreProvider),
    ),
    AuthBackendKind.cloudBase => CloudBaseAuthRepository(
      environmentId: cloudBaseEnvironmentId,
      sessionStore: ref.watch(sessionStoreProvider),
      enableAccountCloudProfile: true,
    ),
    AuthBackendKind.localPreview => LocalPreviewAuthRepository(
      preferences: ref.watch(sharedPreferencesProvider),
    ),
  };
});

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);

final currentUserProvider = Provider<AuthUser?>((ref) {
  return ref.watch(authControllerProvider).value?.user;
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider) != null;
});

/// Owns the authenticated UI state and guards refresh-token races.
class AuthController extends AsyncNotifier<AuthSession?> {
  AuthRepository get _repository => ref.read(authRepositoryProvider);
  Object? lastError;
  // Refresh-token rotation is single-use on the server. Share an in-flight
  // renewal so concurrent API calls cannot race and invalidate each other.
  Future<AuthSession?>? _sessionRenewal;

  @override
  Future<AuthSession?> build() async {
    if (DistributionChannel.isBeta) {
      ref.listen(betaAccountChoiceProvider, (previous, choice) {
        if (choice == BetaAccountChoice.kugou ||
            choice == BetaAccountChoice.netease ||
            choice == BetaAccountChoice.qishui ||
            choice == BetaAccountChoice.guest) {
          state = const AsyncData(null);
        }
      });
      final choice = ref.read(betaAccountChoiceProvider);
      if (choice == BetaAccountChoice.kugou ||
          choice == BetaAccountChoice.netease ||
          choice == BetaAccountChoice.qishui ||
          choice == BetaAccountChoice.guest) {
        return null;
      }
    }
    final repository = _repository;
    final restored = await repository.restoreSession();
    // A delayed CloudBase restoration cannot replace a newly selected platform
    // account. This also keeps an unavailable CloudBase off the music path.
    if (DistributionChannel.isBeta &&
        {
          BetaAccountChoice.kugou,
          BetaAccountChoice.netease,
          BetaAccountChoice.qishui,
          BetaAccountChoice.guest,
        }.contains(ref.read(betaAccountChoiceProvider))) {
      return null;
    }
    if (restored != null && repository is BackgroundRefreshAuthRepository) {
      unawaited(
        _refreshRestoredAccount(
          repository as BackgroundRefreshAuthRepository,
          restored,
        ),
      );
    }
    return restored;
  }

  Future<void> _refreshRestoredAccount(
    BackgroundRefreshAuthRepository repository,
    AuthSession restored,
  ) async {
    // Let AsyncNotifier publish the cached value before a very fast test or
    // local response attempts to replace it.
    await Future<void>.delayed(Duration.zero);
    AuthSession? refreshed;
    try {
      refreshed = await repository.refreshRestoredSession();
    } on Object {
      // A cached, non-expired session remains usable when the background
      // account reconciliation cannot reach the network.
      return;
    }
    final current = state.value;
    if (current == null ||
        current.user.uid != restored.user.uid ||
        current.accessToken != restored.accessToken) {
      return;
    }
    state = AsyncData(refreshed);
  }

  Future<EmailVerificationChallenge> requestEmailCode({required String email}) {
    return _repository.requestEmailCode(email: email);
  }

  Future<bool> refreshAccount() => _run(_repository.refreshAccount);

  /// Returns a usable session, coalescing simultaneous refresh attempts.
  Future<AuthSession?> ensureFreshSession({bool forceRefresh = false}) {
    final current = state.value;
    if (current == null) return Future<AuthSession?>.value();
    if (!forceRefresh && !current.isExpired) {
      return Future<AuthSession?>.value(current);
    }
    final activeRenewal = _sessionRenewal;
    if (activeRenewal != null) return activeRenewal;

    late final Future<AuthSession?> renewal;
    renewal = _renewSession(current).whenComplete(() {
      if (identical(_sessionRenewal, renewal)) {
        _sessionRenewal = null;
      }
    });
    _sessionRenewal = renewal;
    return renewal;
  }

  Future<AuthSession?> _renewSession(AuthSession expected) async {
    try {
      final repository = _repository;
      final refreshed = switch (repository) {
        RenewableAuthRepository renewing => await renewing.renewSession(),
        _ => await repository.restoreSession(),
      };
      final current = state.value;
      if (current == null ||
          current.user.uid != expected.user.uid ||
          current.accessToken != expected.accessToken) {
        return current;
      }
      if (refreshed == null || refreshed.user.uid != expected.user.uid) {
        state = const AsyncData(null);
        return null;
      }
      state = AsyncData(refreshed);
      return refreshed;
    } on Object catch (error, stackTrace) {
      lastError = error;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<bool> registerWithEmail({
    required String email,
    required String password,
    required String verificationId,
    required String verificationCode,
  }) {
    return _run(
      () => _repository.registerWithEmail(
        email: email,
        password: password,
        verificationId: verificationId,
        verificationCode: verificationCode,
      ),
    );
  }

  Future<bool> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _run(
      () => _repository.signInWithEmail(email: email, password: password),
    );
  }

  Future<PhoneVerificationChallenge> requestPhoneCode({
    required String phone,
    required bool registration,
  }) {
    return _repository.requestPhoneCode(
      phone: phone,
      registration: registration,
    );
  }

  Future<bool> verifyPhoneCode({
    required String phone,
    required String code,
    required String verificationId,
    required bool registration,
  }) {
    return _run(
      () => _repository.verifyPhoneCode(
        phone: phone,
        code: code,
        verificationId: verificationId,
        registration: registration,
      ),
    );
  }

  Future<bool> updateProfile({
    required String nickname,
    required String bio,
    int? age,
    String zodiac = '',
    String? avatarPath,
  }) {
    return _run(
      () => _repository.updateProfile(
        nickname: nickname,
        bio: bio,
        age: age,
        zodiac: zodiac,
        avatarPath: avatarPath,
      ),
    );
  }

  Future<SecurityVerificationChallenge> requestCurrentIdentityCode({
    required AuthMethod method,
  }) {
    return _repository.requestCurrentIdentityCode(method: method);
  }

  Future<String> verifyCurrentIdentity({
    required String verificationId,
    required String verificationCode,
  }) {
    return _repository.verifyCurrentIdentity(
      verificationId: verificationId,
      verificationCode: verificationCode,
    );
  }

  Future<SecurityVerificationChallenge> requestBindingCode({
    required AuthMethod method,
    required String account,
  }) {
    return _repository.requestBindingCode(method: method, account: account);
  }

  Future<bool> bindCredential({
    required AuthMethod method,
    required String account,
    required String verificationId,
    required String verificationCode,
    required String sudoToken,
  }) {
    return _run(
      () => _repository.bindCredential(
        method: method,
        account: account,
        verificationId: verificationId,
        verificationCode: verificationCode,
        sudoToken: sudoToken,
      ),
    );
  }

  Future<SecurityVerificationChallenge> requestPasswordResetCode({
    required AuthMethod method,
    required String account,
  }) {
    return _repository.requestPasswordResetCode(
      method: method,
      account: account,
    );
  }

  Future<PasswordResetProof> verifyPasswordResetCode({
    required AuthMethod method,
    required String account,
    required String verificationId,
    required String verificationCode,
  }) {
    return _repository.verifyPasswordResetCode(
      method: method,
      account: account,
      verificationId: verificationId,
      verificationCode: verificationCode,
    );
  }

  Future<void> resetPassword({
    required PasswordResetProof proof,
    required String newPassword,
  }) {
    return _repository.resetPassword(proof: proof, newPassword: newPassword);
  }

  Future<void> deleteAccount({required String sudoToken}) async {
    final current = state.value;
    if (current == null) {
      throw const AuthRequestException('登录状态已失效，请重新登录');
    }
    lastError = null;
    try {
      await _repository.deleteAccount(sudoToken: sudoToken);
    } on Object catch (error, stackTrace) {
      lastError = error;
      Error.throwWithStackTrace(error, stackTrace);
    }

    // The server has already confirmed permanent deletion. Local cleanup must
    // never revive this session if one non-critical cache entry is unavailable.
    try {
      await ref.read(appDatabaseProvider).deleteOwnerData(current.user.uid);
      await _clearDeletedAccountPreferences(current.user.uid);
    } on Object {
      // The server has already completed the irreversible part. Never report
      // a successful account deletion as failed only because a local cache is
      // locked or already absent.
    } finally {
      state = const AsyncData(null);
    }
  }

  Future<void> signOut() async {
    final previous = state;
    state = const AsyncLoading();
    try {
      await _repository.signOut();
      if (DistributionChannel.isBeta) {
        await ref
            .read(betaAccountChoiceProvider.notifier)
            .select(BetaAccountChoice.guest);
      }
      state = const AsyncData(null);
      if (DistributionChannel.isBeta) {
        await ref.read(betaEntryFlowProvider.notifier).welcome();
      }
    } on Object {
      state = previous;
      rethrow;
    }
  }

  Future<AuthSession?> rememberedAccount() {
    return ref.read(sessionStoreProvider).readRemembered();
  }

  Future<void> _clearDeletedAccountPreferences(String uid) async {
    final preferences = ref.read(sharedPreferencesProvider);
    final encodedUid = Uri.encodeComponent(uid);
    final backgroundToken = sha256
        .convert(utf8.encode(uid))
        .toString()
        .substring(0, 16);
    final localBackgroundKey = 'profile_background_v1_${backgroundToken}_value';
    final localBackgroundPath = preferences.getString(localBackgroundKey);
    final keys = <String>{
      'library_cloud_bootstrapped_v2_$encodedUid',
      'library_cloud_last_pull_v1_$encodedUid',
      'social_status_snapshot_v1_$uid',
      'social_attention_known_followers_v1_$uid',
      'social_attention_pending_followers_v1_$uid',
      'social_attention_known_messages_v1_$uid',
      'profile_background_v1_${backgroundToken}_kind',
      localBackgroundKey,
      'profile_background_cloud_v1_${backgroundToken}_kind',
      'profile_background_cloud_v1_${backgroundToken}_value',
      'profile_background_cloud_v1_${backgroundToken}_ready',
    };
    for (final key in keys) {
      await preferences.remove(key);
    }
    await _removeManagedProfileBackground(localBackgroundPath);
  }

  Future<void> _removeManagedProfileBackground(String? path) async {
    if (path == null || path.trim().isEmpty) return;
    try {
      final root = await getApplicationDocumentsDirectory();
      final directory = Directory(
        '${root.path}${Platform.pathSeparator}profile_backgrounds',
      ).absolute;
      final file = File(path).absolute;
      final prefix = '${directory.path}${Platform.pathSeparator}';
      if (!file.path.startsWith(prefix) || !await file.exists()) return;
      await file.delete();
    } on Object {
      // A stale local preview file must never make a completed cloud deletion
      // look like a failed account deletion.
    }
  }

  Future<bool> quickSignIn() async {
    final store = ref.read(sessionStoreProvider);
    final remembered = await store.readRemembered();
    if (remembered == null) return false;
    state = const AsyncLoading();
    lastError = null;
    try {
      await store.restoreRememberedAsActive();
      final restored = await _repository.restoreSession();
      if (restored == null) {
        await store.forgetRemembered();
        state = const AsyncData(null);
        return false;
      }
      await store.remember(restored);
      if (DistributionChannel.isBeta) {
        await ref
            .read(betaAccountChoiceProvider.notifier)
            .select(BetaAccountChoice.mesting);
      }
      state = AsyncData(restored);
      if (_repository case final BackgroundRefreshAuthRepository repository) {
        unawaited(_refreshRestoredAccount(repository, restored));
      }
      return true;
    } on Object catch (error, stackTrace) {
      lastError = error;
      await store.clear();
      state = AsyncError<AuthSession?>(error, stackTrace);
      return false;
    }
  }

  Future<void> forgetRememberedAccount() {
    return ref.read(sessionStoreProvider).forgetRemembered();
  }

  Future<bool> _run(Future<AuthSession> Function() request) async {
    final previous = state.value;
    lastError = null;
    if (previous == null) state = const AsyncLoading();
    try {
      if (DistributionChannel.isBeta &&
          const {
            BetaAccountChoice.kugou,
            BetaAccountChoice.netease,
            BetaAccountChoice.qishui,
          }.contains(ref.read(betaAccountChoiceProvider))) {
        throw StateError('请先退出当前音乐平台账号');
      }
      final session = await request();
      if (DistributionChannel.isBeta) {
        if (const {
          BetaAccountChoice.kugou,
          BetaAccountChoice.netease,
          BetaAccountChoice.qishui,
        }.contains(ref.read(betaAccountChoiceProvider))) {
          throw StateError('当前已切换为音乐平台账号，请先退出');
        }
        await ref
            .read(betaAccountChoiceProvider.notifier)
            .select(BetaAccountChoice.mesting);
      }
      state = AsyncData(session);
      return true;
    } on Object catch (error, stackTrace) {
      lastError = error;
      state = previous == null
          ? AsyncError<AuthSession?>(error, stackTrace)
          : AsyncData(previous);
      return false;
    }
  }
}
