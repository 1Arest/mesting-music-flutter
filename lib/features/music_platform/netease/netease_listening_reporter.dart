import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/audio/actual_listening_counter.dart';
import '../../../core/audio/playback_providers.dart';
import '../../../core/diagnostics/local_music_diagnostics.dart';
import '../../../core/persistence/app_preferences.dart';
import '../../../shared/models/track.dart';
import '../data/music_platform_api.dart';
import '../listening_sync/listening_sync_coordinator.dart';
import '../listening_sync/listening_sync_models.dart';
import '../listening_sync/listening_sync_store.dart';
import '../listening_sync/listening_sync_providers.dart';
import '../music_platform_providers.dart';
import '../platform_backend_providers.dart';
import 'netease_music_repository.dart';
import 'netease_footprint.dart';
import 'netease_native_journal.dart';

/// A disabled experimental transport must not drain its old open/queued rows
/// through either endpoint. Preserve their evidence until separately reviewed.
bool holdNeteaseNativeRecord(
  ListeningSyncEntry row, {
  required bool nativeLogEnabled,
}) => !nativeLogEnabled && row.number('protocolVersion') == 3;

final neteaseFootprintProvider = FutureProvider.autoDispose<NeteaseFootprint?>((
  ref,
) async {
  if (!ref.watch(usesNeteaseProvider)) return null;
  return ref.watch(neteaseMusicRepositoryProvider).footprint();
}, retry: (_, _) => null);

/// A platform-specific reporter shares the monotonic counter and durable
/// journal, never Kugou's endpoints. Every playback instance sends at most one
/// scrobble; a process/network interruption becomes uncertain, not a blind retry.
class NeteaseListeningReporter with WidgetsBindingObserver {
  NeteaseListeningReporter({
    required this.feed,
    required this.music,
    required this.store,
    required this.current,
    ListeningClock? clock,
    this.observeLifecycle = true,
    this.automaticTimers = true,
  }) : clock = clock ?? MonotonicListeningClock(),
       owner = music.api.session?.identity.ownerId ?? '' {
    _subscriptions.add(feed.tracks.listen(_track));
    _subscriptions.add(
      feed.states.listen((state) {
        _counter?.update(
          playing: state.playing,
          ready: state.ready,
          seeking: feed.isSeeking,
          speed: state.speed,
        );
        _startWhenReady();
        if (state.completed) _finish(endReason: 'playend');
      }),
    );
    _subscriptions.add(
      feed.seeks.listen((seeking) {
        _counter?.update(seeking: seeking);
        // Decoder readiness can arrive before an awaited seek finishes. The
        // seek-end edge must retry opening, without counting the seek itself.
        if (!seeking) _startWhenReady();
      }),
    );
    _subscriptions.add(
      feed.repeatBoundaries.listen((_) {
        _finish(endReason: 'playend');
        _track(feed.currentTrack, repeat: true);
      }),
    );
    if (observeLifecycle) WidgetsBinding.instance.addObserver(this);
    if (automaticTimers) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => checkpoint());
    }
    _track(feed.currentTrack);
    _initialTrack = false;
    _schedule(_recover);
  }
  final ListeningAudioFeed feed;
  final NeteaseMusicRepository music;
  final ListeningSyncStore store;
  final bool Function() current;
  final ListeningClock clock;
  final bool observeLifecycle, automaticTimers;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Timer? _timer;
  Track? _song;
  ActualListeningCounter? _counter;
  String? _event;
  DateTime? _startedAt;
  Future<void> _tail = Future.value();
  bool _disposed = false;
  bool _started = false;
  bool _initialTrack = true;
  final String owner;
  void _schedule(Future<void> Function() action) {
    _tail = _tail.then((_) => action()).catchError((Object _) {});
  }

  void _track(Track? song, {bool repeat = false}) {
    if (_disposed || (!repeat && _song?.id == song?.id)) return;
    _finish();
    _song = song;
    if (song?.source != TrackSource.netease ||
        song!.externalUrl.contains('/program?') ||
        !RegExp(r'^netease_\d+$').hasMatch(song.id)) {
      return;
    }
    _event =
        'netease-play:${clock.now.microsecondsSinceEpoch}:${song.platformSongId}';
    _started = false;
    _startedAt = null;
    _counter = ActualListeningCounter(clock)
      ..update(
        playing: feed.currentState.playing,
        ready: feed.currentState.ready,
        seeking: feed.isSeeking,
        speed: feed.currentState.speed,
      );
    // Metadata can change before the old audio source reports loading. Wait
    // for the new track's playback-state event; a repeat is already audible.
    if (_initialTrack || repeat) _startWhenReady();
  }

  void _startWhenReady() {
    final song = _song, event = _event;
    final state = feed.currentState;
    if (_disposed ||
        _started ||
        song == null ||
        event == null ||
        !state.playing ||
        !state.ready ||
        feed.isSeeking ||
        !current()) {
      return;
    }
    _started = true;
    _startedAt = clock.now;
    final startedAt = _startedAt!;
    _schedule(() async {
      if (!current()) return;
      await store.put(
        owner: owner,
        id: '$event:start',
        kind: 'netease-startplay',
        payload: {
          'id': NeteaseMusicRepository.songId(song.id),
          'title': song.title,
          'startlogtime': startedAt.millisecondsSinceEpoch ~/ 1000,
          'protocolVersion': music.nativeLogEnabled ? 3 : 2,
          if (music.nativeLogEnabled)
            'eventlogtime': startedAt.millisecondsSinceEpoch ~/ 1000,
        },
        now: clock.now,
        state: ListeningSyncState.queued,
      );
      await _sendQueued();
    });
  }

  void checkpoint() {
    final song = _song, event = _event, counter = _counter;
    if (song == null || event == null || counter == null) return;
    final heard = counter.sample();
    final mediaMs = counter.sampleMediaMilliseconds();
    final startedAt = _startedAt;
    final measuredAt = clock.now;
    _schedule(() async {
      await _save(
        event,
        song,
        heard,
        mediaMs,
        startedAt,
        measuredAt: measuredAt,
        close: false,
      );
      if (current()) await _verifyRecent();
    });
  }

  void _finish({String endReason = 'interrupt'}) {
    final song = _song, event = _event, counter = _counter;
    _counter = null;
    _event = null;
    if (song == null || event == null || counter == null) return;
    final heard = counter.sample();
    final mediaMs = counter.sampleMediaMilliseconds();
    final startedAt = _startedAt;
    final measuredAt = clock.now;
    _schedule(() async {
      await _save(
        event,
        song,
        heard,
        mediaMs,
        startedAt,
        measuredAt: measuredAt,
        endReason: endReason,
        close: true,
      );
      if (current()) await _sendQueued();
    });
  }

  Future<void> _save(
    String event,
    Track song,
    int heard,
    int mediaMs,
    DateTime? startedAt, {
    // Kept positional in the call sites so each queued save captures the
    // timestamp and durations before a later track changes controller state.
    required bool close,
    required DateTime measuredAt,
    String endReason = 'interrupt',
  }) async {
    if (heard < 1000 || owner.isEmpty) return;
    final payload = <String, Object?>{
      'id': NeteaseMusicRepository.songId(song.id),
      'time': mediaMs ~/ 1000,
      'realtime': heard ~/ 1000,
      if (startedAt != null)
        'startlogtime': startedAt.millisecondsSinceEpoch ~/ 1000,
      'mediaHeardMs': mediaMs,
      'protocolVersion': music.nativeLogEnabled ? 3 : 2,
      if (music.nativeLogEnabled) ...{
        'eventlogtime': measuredAt.millisecondsSinceEpoch ~/ 1000,
        'endReason': endReason,
      },
      'heardMs': heard,
      'sourceid': 0,
      'title': song.title,
    };
    await store.put(
      owner: owner,
      id: event,
      kind: 'netease-scrobble',
      payload: payload,
      now: clock.now,
      state: ListeningSyncState.open,
    );
    final row = await store.entry(owner, event);
    if (row != null) {
      await store.change(
        row,
        close ? ListeningSyncState.queued : ListeningSyncState.open,
        clock.now,
        expected: ListeningSyncState.open,
        payload: payload,
      );
    }
  }

  Future<void> _recover() async {
    if (!current()) return;
    final rows = await store.entries(
      owner,
      kinds: {'netease-scrobble', 'netease-startplay'},
      states: {ListeningSyncState.open},
    );
    for (final row in rows) {
      if (holdNeteaseNativeRecord(
        row,
        nativeLogEnabled: music.nativeLogEnabled,
      )) {
        continue;
      }
      if (row.id != _event) {
        await store.change(
          row,
          ListeningSyncState.queued,
          clock.now,
          expected: ListeningSyncState.open,
        );
      }
    }
    await _sendQueued();
  }

  Future<void> _sendQueued() async {
    final rows = await store.entries(
      owner,
      kinds: {'netease-scrobble', 'netease-startplay'},
      states: {ListeningSyncState.queued},
    );
    for (final pending in rows) {
      if (!current()) return;
      var row = pending;
      if (holdNeteaseNativeRecord(
        row,
        nativeLogEnabled: music.nativeLogEnabled,
      )) {
        continue;
      }
      final native = row.number('protocolVersion') == 3;
      if (native) {
        final claimed = await claimNeteaseNativeLog(store, row, clock.now);
        if (claimed == null) continue;
        row = claimed;
      } else if (!await store.change(
        row,
        ListeningSyncState.dispatched,
        clock.now,
        expected: ListeningSyncState.queued,
      )) {
        continue;
      }
      final started = row.kind == 'netease-startplay';
      final mediaSeconds = row.number('time');
      final realSeconds = row.payload.containsKey('realtime')
          ? row.number('realtime')
          : row.number('heardMs') > 0
          ? row.number('heardMs') ~/ 1000
          : mediaSeconds;
      try {
        final epoch = RegExp(r'^netease-play:(\d+):').firstMatch(row.id);
        final originalStart = row.number('startlogtime') > 0
            ? DateTime.fromMillisecondsSinceEpoch(
                row.number('startlogtime') * 1000,
              )
            : epoch != null
            ? DateTime.fromMicrosecondsSinceEpoch(int.parse(epoch[1]!))
            : row.createdAt;
        final response = await music.reportPlayback(
          id: '${row.payload['id']}',
          started: started,
          seconds: mediaSeconds,
          sourceId: '${row.payload['sourceid'] ?? 0}',
          realSeconds: realSeconds,
          startedAt: originalStart,
          nativeSequence: native ? row.number('nativeSequence') : null,
          eventTime: native
              ? DateTime.fromMillisecondsSinceEpoch(
                  row.number('eventlogtime') * 1000,
                )
              : null,
          endReason: row.text('endReason').isEmpty
              ? 'interrupt'
              : row.text('endReason'),
        );
        await store.change(
          row,
          ListeningSyncState.accepted,
          clock.now,
          expected: ListeningSyncState.dispatched,
        );
        _traceSubmit(
          started: started,
          mediaSeconds: mediaSeconds,
          realSeconds: realSeconds,
          outcome: ListeningSyncState.accepted,
          businessCode: int.tryParse('${response['code']}'),
          native: native,
        );
      } catch (e) {
        final outcome = e is MusicPlatformException && e.code.isNotEmpty
            ? ListeningSyncState.rejected
            : ListeningSyncState.unknown;
        _traceSubmit(
          started: started,
          mediaSeconds: mediaSeconds,
          realSeconds: realSeconds,
          outcome: outcome,
          native: native,
          businessCode: e is MusicPlatformException
              ? int.tryParse(e.code)
              : null,
        );
        await store.change(
          row,
          outcome,
          clock.now,
          expected: ListeningSyncState.dispatched,
        );
      }
    }
  }

  /// Diagnostic builds emit measured durations and normalized outcomes only.
  /// Never pass journal/account identifiers or transport objects to the logger.
  void _traceSubmit({
    required bool started,
    required int mediaSeconds,
    required int realSeconds,
    required ListeningSyncState outcome,
    int? businessCode,
    bool native = false,
  }) {
    if (!LocalMusicDiagnostics.enabled) return;
    try {
      LocalMusicDiagnostics.record('netease.playback_submit', {
        'started': started,
        'mediaSeconds': mediaSeconds,
        'realtimeSeconds': realSeconds,
        'transport': native ? 'android-bi-v3' : 'weblog',
        'outcome': outcome.name,
        'businessCode': ?businessCode,
      });
    } catch (_) {
      // Best-effort diagnostics must never change a journal/send outcome.
    }
  }

  /// Log receipt is insufficient evidence of cloud indexing. Verify with the
  /// account's read API, allowing a few checkpoints for eventual consistency.
  /// These are read retries only; neither start nor duration writes are resent.
  Future<void> _verifyRecent() async {
    if (!current()) return;
    final entries = await store.entries(
      owner,
      kinds: {'netease-startplay'},
      states: {ListeningSyncState.accepted},
    );
    final pending = entries
        .where(
          (row) =>
              !holdNeteaseNativeRecord(
                row,
                nativeLogEnabled: music.nativeLogEnabled,
              ) &&
              row.payload['cloudConfirmed'] != true &&
              row.number('verificationAttempts') < 3,
        )
        .take(10)
        .toList();
    if (pending.isEmpty || !current()) return;
    try {
      final result = await music.call('/record/recent/song', {'limit': 100});
      if (!current()) return;
      final recent = NeteaseMusicRepository.rows(
        NeteaseMusicRepository.object(result['data'])['list'],
      );
      for (final row in pending) {
        final found = recent.any((item) {
          final data = NeteaseMusicRepository.object(item['data']);
          final song = NeteaseMusicRepository.object(data['song']);
          final id = '${song['id'] ?? data['id'] ?? item['id'] ?? ''}';
          final played = int.tryParse('${item['playTime']}') ?? 0;
          return id == '${row.payload['id']}' &&
              played >= row.createdAt.millisecondsSinceEpoch - 2000;
        });
        await store.change(
          row,
          row.state,
          clock.now,
          expected: row.state,
          payload: {
            ...row.payload,
            'cloudConfirmed': found,
            'verificationAttempts': row.number('verificationAttempts') + 1,
          },
        );
      }
    } catch (_) {
      /* Keep receipt and cloud confirmation distinct on read errors. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => checkpoint();
  Future<void> settle() => _tail;

  /// Only journal rows known never to have been dispatched are eligible.
  /// Accepted/rejected/unknown rows and date-only daily aggregates are not
  /// converted into new events. The active track stays open until it ends.
  Future<void> recoverPending() {
    _schedule(_recover);
    return _tail;
  }

  void dispose() {
    _finish();
    _disposed = true;
    _timer?.cancel();
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    if (observeLifecycle) WidgetsBinding.instance.removeObserver(this);
  }
}

final neteaseListeningEnabledProvider =
    NotifierProvider<NeteaseListeningSetting, bool>(
      NeteaseListeningSetting.new,
    );

class NeteaseListeningSetting extends Notifier<bool> {
  @override
  bool build() =>
      ref
          .watch(sharedPreferencesProvider)
          .getBool('netease_listening_reporting_v1') ??
      true;
  Future<void> setEnabled(bool value) async {
    if (!await ref
        .read(sharedPreferencesProvider)
        .setBool('netease_listening_reporting_v1', value)) {
      throw const MusicPlatformException('播放同步设置未保存');
    }
    state = value;
  }
}

final neteaseListeningReporterProvider = Provider<NeteaseListeningReporter?>((
  ref,
) {
  ref.watch(
    platformAccountProvider.select((a) => (a.value?.ownerId, a.value?.token)),
  );
  final account = ref.read(platformAccountProvider).value;
  if (!ref.watch(usesNeteaseProvider) ||
      account == null ||
      !ref.watch(neteaseListeningEnabledProvider)) {
    return null;
  }
  ref.watch(neteaseMusicRepositoryProvider.select((m) => m.credential));
  final music = ref.read(neteaseMusicRepositoryProvider);
  final reporter = NeteaseListeningReporter(
    feed: HandlerListeningAudioFeed(ref.watch(audioHandlerProvider)),
    music: music,
    store: ref.watch(platformListeningSyncStoreProvider),
    current: () =>
        ref.mounted &&
        ref.read(neteaseListeningEnabledProvider) &&
        ref.read(platformAccountProvider).value?.ownerId == account.ownerId &&
        ref.read(platformAccountProvider).value?.token == account.token,
  );
  ref.onDispose(reporter.dispose);
  return reporter;
});

final neteaseListeningJournalProvider =
    StreamProvider<List<ListeningSyncEntry>>((ref) {
      final account = ref.watch(platformAccountProvider).value;
      if (!ref.watch(usesNeteaseProvider) || account == null) {
        return Stream.value([]);
      }
      return ref
          .watch(platformListeningSyncStoreProvider)
          .watch(account.ownerId)
          .map(
            (rows) => rows
                .where(
                  (r) =>
                      r.kind == 'netease-scrobble' ||
                      r.kind == 'netease-startplay',
                )
                .toList(),
          );
    });
