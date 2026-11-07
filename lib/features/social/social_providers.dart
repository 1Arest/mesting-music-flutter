import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_providers.dart';
import '../../core/persistence/app_preferences.dart';
import 'data/cloudbase_social_repository.dart';
import 'data/local_preview_social_repository.dart';
import 'data/social_repository.dart';
import 'domain/social_models.dart';

const socialReadTimeout = Duration(seconds: 10);
const socialReadCacheTtl = Duration(minutes: 2);
const socialUserSearchCacheTtl = Duration(minutes: 30);
const _socialStatusSnapshotPrefix = 'social_status_snapshot_v1_';
final Map<String, SocialStatus> _socialStatusMemorySnapshots = {};

String socialStatusSnapshotKey(String uid) =>
    '$_socialStatusSnapshotPrefix${uid.trim()}';

SocialStatus? cachedSocialStatusSnapshot(
  SharedPreferences preferences,
  String uid,
) {
  final normalizedUid = uid.trim();
  if (normalizedUid.isEmpty) return null;
  final memory = _socialStatusMemorySnapshots[normalizedUid];
  if (memory != null) return memory;
  final raw = preferences.getString(socialStatusSnapshotKey(normalizedUid));
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final status = SocialStatus.fromJson(Map<String, Object?>.from(decoded));
    _socialStatusMemorySnapshots[normalizedUid] = status;
    return status;
  } on Object {
    return null;
  }
}

Future<void> rememberSocialStatusSnapshot(
  SharedPreferences preferences,
  String uid,
  SocialStatus status,
) async {
  final normalizedUid = uid.trim();
  if (normalizedUid.isEmpty) return;
  _socialStatusMemorySnapshots[normalizedUid] = status;
  await preferences.setString(
    socialStatusSnapshotKey(normalizedUid),
    jsonEncode(status.toJson()),
  );
}

final socialReadTimeoutProvider = Provider<Duration>(
  (ref) => socialReadTimeout,
);

final socialReadCacheTtlProvider = Provider<Duration>(
  (ref) => socialReadCacheTtl,
);

Duration? _disableSocialRetry(int retryCount, Object error) => null;

Future<T> _readSocial<T>(
  Ref ref,
  Future<T> request, {
  Duration? cacheTtl,
}) async {
  final cacheLink = ref.keepAlive();
  Timer? cacheExpiry;
  ref.onDispose(() => cacheExpiry?.cancel());

  try {
    final value = await request.timeout(
      ref.watch(socialReadTimeoutProvider),
      onTimeout: () => throw const SocialRequestException(
        '好友服务响应较慢，请检查网络后重试',
        code: 'timeout',
      ),
    );
    final Duration effectiveCacheTtl =
        cacheTtl ?? ref.read(socialReadCacheTtlProvider);
    if (effectiveCacheTtl <= Duration.zero) {
      cacheLink.close();
    } else {
      cacheExpiry = Timer(effectiveCacheTtl, cacheLink.close);
    }
    return value;
  } on Object {
    cacheLink.close();
    rethrow;
  }
}

final socialRepositoryProvider = Provider<SocialRepository>((ref) {
  final backend = ref.watch(authBackendKindProvider);
  if (backend == AuthBackendKind.localPreview) {
    return LocalPreviewSocialRepository(
      userProvider: () => ref.read(currentUserProvider),
      preferences: ref.watch(sharedPreferencesProvider),
    );
  }
  if (backend == AuthBackendKind.customApi) {
    return CloudBaseSocialRepository(
      apiBaseUrl: ref.watch(authApiBaseUrlProvider),
      actionPath: '/v1/social/actions',
      sessionProvider: () =>
          ref.read(authControllerProvider.notifier).ensureFreshSession(),
      sessionRefresher: () => ref
          .read(authControllerProvider.notifier)
          .ensureFreshSession(forceRefresh: true),
    );
  }
  return CloudBaseSocialRepository(
    environmentId: cloudBaseEnvironmentId,
    sessionProvider: () =>
        ref.read(authControllerProvider.notifier).ensureFreshSession(),
    sessionRefresher: () => ref
        .read(authControllerProvider.notifier)
        .ensureFreshSession(forceRefresh: true),
  );
});

/// Resolves a media source just before it is handed to a platform player.
/// Direct HTTPS and local file URLs pass through immediately; only historical
/// CloudBase object IDs require a signed download URL.
final socialMediaUrlProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, rawValue) {
      final value = rawValue.trim();
      if (value.isEmpty) return Future<String?>.value(null);
      final repository = ref.watch(socialRepositoryProvider);
      if (repository is SocialMediaUrlResolver) {
        return (repository as SocialMediaUrlResolver).resolveMediaUrl(value);
      }
      return Future<String?>.value(value.startsWith('cloud://') ? null : value);
    }, retry: _disableSocialRetry);

final socialSummaryProvider = FutureProvider.autoDispose<SocialSummary>((ref) {
  ref.watch(currentUserProvider);
  return _readSocial(ref, ref.watch(socialRepositoryProvider).summary());
}, retry: _disableSocialRetry);

final socialStatusProvider = FutureProvider.autoDispose<SocialStatus>((ref) {
  final user = ref.watch(currentUserProvider);
  final preferences = ref.watch(sharedPreferencesProvider);
  final repository = ref.watch(socialRepositoryProvider);
  return _readSocial(ref, repository.getStatus()).then((status) {
    if (user != null) {
      unawaited(rememberSocialStatusSnapshot(preferences, user.uid, status));
    }
    return status;
  });
}, retry: _disableSocialRetry);

final socialUserProvider = FutureProvider.autoDispose
    .family<SocialUser, String>(
      (ref, uid) =>
          _readSocial(ref, ref.watch(socialRepositoryProvider).getUser(uid)),
      retry: _disableSocialRetry,
    );

final socialConnectionsProvider = FutureProvider.autoDispose
    .family<List<SocialUser>, SocialConnectionKind>(
      (ref, kind) => _readSocial(
        ref,
        ref.watch(socialRepositoryProvider).listConnections(kind),
      ),
      retry: _disableSocialRetry,
    );

final socialUserSearchProvider = FutureProvider.autoDispose
    .family<List<SocialUser>, String>((ref, query) {
      final normalized = query.trim();
      if (normalized.runes.length < 2 ||
          ref.watch(currentUserProvider) == null) {
        return const [];
      }
      return _readSocial(
        ref,
        ref.watch(socialRepositoryProvider).searchUsers(normalized),
        cacheTtl: socialUserSearchCacheTtl,
      );
    }, retry: _disableSocialRetry);

final socialConversationsProvider = FutureProvider.autoDispose((ref) {
  // The repository reads credentials lazily and may be the same instance
  // after login changes. The cached request must still belong to one owner.
  ref.watch(currentUserProvider.select((user) => user?.uid));
  return _readSocial(
    ref,
    ref.watch(socialRepositoryProvider).listConversations(),
  );
}, retry: _disableSocialRetry);

/// A refresh may replace the repository/Future while a chat route is closing.
/// Retain that owner's last conversation value through the reload. A distinct
/// family key prevents the previous account's conversations being reused.
final socialConversationsByOwnerProvider = FutureProvider.autoDispose
    .family<List<SocialConversation>, String?>((ref, owner) {
      if (ref.watch(currentUserProvider)?.uid != owner) {
        return Future.value(const []);
      }
      return ref.watch(socialConversationsProvider.future);
    }, retry: _disableSocialRetry);

final socialMessagesProvider = FutureProvider.autoDispose
    .family<List<SocialMessage>, String>(
      (ref, uid) => _readSocial(
        ref,
        ref.watch(socialRepositoryProvider).listMessages(uid),
      ),
      retry: _disableSocialRetry,
    );

void invalidateSocialData(Ref ref, {String? uid, String? query}) {
  ref.invalidate(socialSummaryProvider);
  ref.invalidate(socialConnectionsProvider);
  ref.invalidate(socialConversationsProvider);
  if (uid != null) {
    ref.invalidate(socialUserProvider(uid));
    ref.invalidate(socialMessagesProvider(uid));
  }
  if (query != null) ref.invalidate(socialUserSearchProvider(query));
}
