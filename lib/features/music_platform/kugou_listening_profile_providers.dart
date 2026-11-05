import '../../core/network/system_music_io_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/kugou_listening_profile_repository.dart';
import 'data/kugou_official_api.dart';
import 'data/music_platform_api.dart';
import 'domain/kugou_listening_profile.dart';
import 'domain/platform_session.dart';
import 'music_platform_providers.dart';

final kugouListeningProfileClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// 昵称/头像更新不重建传输；凭据或平台变化会关闭旧client和身份检查。
/// 即使账号 A→B→A，第一轮 A 的迟到请求也不能成为第三轮的有效资料。
final kugouListeningProfileRepositoryProvider =
    Provider<KugouListeningProfileRepository>((ref) {
      ref.watch(
        platformAccountProvider.select(
          (value) => (
            value.value?.platform,
            value.value?.userId,
            value.value?.token,
            value.value?.kugouStandardToken,
          ),
        ),
      );
      final api = ref.watch(musicPlatformApiProvider);
      final client = SystemMusicIoClient();
      var closed = false;
      // 监听在账号状态发布时同步关闭旧身份，不能等待下一帧provider重建。
      // 这样同一帧内的A→B→A也无法让第一轮A的迟到回执复活。
      ref.listen(
        platformAccountProvider.select(
          (value) => (
            value.value?.platform,
            value.value?.userId,
            value.value?.token,
            value.value?.kugouStandardToken,
          ),
        ),
        (previous, next) {
          if (previous != next && !closed) {
            closed = true;
            client.close();
          }
        },
      );
      ref.onDispose(() {
        closed = true;
        client.close();
      });
      final clock = ref.watch(kugouListeningProfileClockProvider);
      return KugouListeningProfileRepository(
        api: api,
        official: KugouOfficialApi(
          client: client,
          currentIdentity: () =>
              closed ? null : ref.read(platformAccountProvider).value,
          device: () => KugouOfficialApi.registeredDevice(api),
          clock: clock,
        ),
        clock: clock,
      );
    });

final kugouListeningProfileReaderProvider =
    Provider<KugouListeningProfileReader?>((ref) {
      ref.watch(
        platformAccountProvider.select(
          (value) => (
            value.value?.platform,
            value.value?.userId,
            value.value?.token,
            value.value?.kugouStandardToken,
          ),
        ),
      );
      final owner = ref.read(platformAccountProvider).value;
      if (owner == null || owner.platform != MusicPlatform.kugou) {
        return null;
      }
      final reader = KugouListeningProfileReader(
        owner: owner,
        repository: ref.watch(kugouListeningProfileRepositoryProvider),
      );
      ref.onDispose(reader.dispose);
      return reader;
    });

/// 每项独立保留成功快照；有效期后可重新读取，失败不清空已有资料或邻项。
class KugouProfileRead<T> {
  T? value;
  String? error;
  bool loading = false, loginRequired = false;
  Future<void>? _pending;
  DateTime? _readAt;
  int _revision = 0;
}

/// 轻量页面订阅边界，资料变化不重建整份个人歌单。所有快照只活在本账号周期。
class KugouListeningProfileReader extends ChangeNotifier {
  KugouListeningProfileReader({required this.owner, required this.repository});
  final PlatformSession owner;
  final KugouListeningProfileRepository repository;
  final profile = KugouProfileRead<KugouMusicProfile>();
  final grade = KugouProfileRead<KugouGrade>();
  final medals = KugouProfileRead<KugouMedalCollection>();
  final _statistics = <String, KugouProfileRead<KugouListeningStatistics>>{};
  final _queries = <String, (KugouListenPeriod, DateTime)>{};
  bool _closed = false;

  bool belongsTo(PlatformSession session) =>
      !_closed &&
      owner.ownerId == session.ownerId &&
      owner.token == session.token &&
      owner.kugouStandardToken == session.kugouStandardToken;

  String _key(KugouListenPeriod period, DateTime date) =>
      '${period.index}:${period.start(date).millisecondsSinceEpoch}';

  KugouProfileRead<KugouListeningStatistics> statistics(
    KugouListenPeriod period,
    DateTime date,
  ) {
    final key = _key(period, date);
    _queries[key] = (period, period.start(date));
    return _statistics.putIfAbsent(key, KugouProfileRead.new);
  }

  /// An independently read official daily result can refresh the visible
  /// snapshot. It never turns a local upload into proof of official booking.
  void acceptStatistics(KugouListeningStatistics value) {
    if (_closed) return;
    final state = statistics(value.period, value.date);
    state.value = value;
    state._revision++;
    state._readAt = value.readAt;
    state.error = null;
    state.loginRequired = false;
    notifyListeners();
  }

  /// Refresh only already requested, current periods. No historical reports,
  /// medals or whole-library collections are polled after each listening tick.
  Future<void> refreshCurrentStatistics() async {
    if (_closed) return;
    final now = repository.clock();
    final pending = <Future<void>>[];
    for (final (period, date) in _queries.values.toList()) {
      if (period != KugouListenPeriod.year && date == period.start(now)) {
        pending.add(loadStatistics(period, date));
      }
    }
    if (grade.value != null) pending.add(loadGrade());
    await Future.wait(pending);
  }

  Future<void> loadStatistics(
    KugouListenPeriod period,
    DateTime date, {
    bool force = false,
  }) => _load(
    statistics(period, date),
    () => repository.statistics(owner, period, date),
    force,
  );
  Future<void> loadProfile({bool force = false}) =>
      _load(profile, () => repository.profile(owner), force);
  Future<void> loadGrade({bool force = false}) =>
      _load(grade, () => repository.grade(owner), force);
  Future<void> loadMedals({bool force = false}) =>
      _load(medals, () => repository.medals(owner), force);

  Future<void> loadOverview({bool force = false}) => Future.wait([
    loadStatistics(KugouListenPeriod.month, repository.clock(), force: force),
    loadGrade(force: force),
    loadMedals(force: force),
  ]);

  Future<void> _load<T>(
    KugouProfileRead<T> state,
    Future<T> Function() request,
    bool force,
  ) {
    if (_closed) {
      return Future.value();
    }
    if (state._pending != null) {
      return state._pending!;
    }
    final fresh =
        state._readAt != null &&
        repository.clock().difference(state._readAt!) <
            const Duration(minutes: 2);
    if (!force && (state.error != null || state.value != null && fresh)) {
      return Future.value();
    }
    state.loading = true;
    state.error = null;
    state.loginRequired = false;
    notifyListeners();
    final revision = state._revision;
    Future<void> run() async {
      try {
        final value = await request();
        if (!_closed && revision == state._revision) {
          state.value = value;
          state._readAt = repository.clock();
        }
      } catch (error) {
        if (!_closed && revision == state._revision) {
          state.error = error is KugouOfficialException
              ? error.message
              : error is MusicPlatformException
              ? error.message
              : '这项酷狗资料读取失败，请重试';
          state.loginRequired =
              error is KugouOfficialException && error.loginRequired;
        }
      } finally {
        state._pending = null;
        if (!_closed) {
          state.loading = false;
          notifyListeners();
        }
      }
    }

    return state._pending = run();
  }

  @override
  void dispose() {
    _closed = true;
    _statistics.clear();
    _queries.clear();
    super.dispose();
  }
}
