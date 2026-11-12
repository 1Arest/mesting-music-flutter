import 'dart:convert';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/platform_backend_providers.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_models.dart';
import 'package:mesting_music/features/music_platform/listening_sync/listening_sync_store.dart';
import 'package:mesting_music/features/music_platform/netease/diagnostics/netease_listening_audit.dart';
import 'package:mesting_music/features/music_platform/netease/diagnostics/netease_listening_audit_provider.dart';

const auditOwner = 'netease:987654';
ListeningSyncEntry event(
  String id, {
  String owner = auditOwner,
  Map<String, Object?> payload = const {},
  ListeningSyncState state = ListeningSyncState.accepted,
  String kind = 'netease-scrobble',
  DateTime? created,
}) => ListeningSyncEntry(
  ownerId: owner,
  id: id,
  kind: kind,
  payload: {'id': '9988776655', ...payload},
  state: state,
  createdAt: created ?? DateTime(2026, 10, 15),
  updatedAt: DateTime(2026, 11, 1),
);
ListeningAuditDay day({
  String owner = auditOwner,
  String date = '2026-10-15',
  int ms = 683 * 60000,
  bool song = true,
}) => ListeningAuditDay(
  owner: owner,
  day: date,
  songId: 'netease_9988776655',
  milliseconds: ms,
  neteaseSong: song,
);
NeteaseListeningAudit report({
  Iterable<ListeningSyncEntry> events = const [],
  Iterable<ListeningAuditDay> days = const [],
  int limit = 5000,
}) => NeteaseListeningAudit.build(
  owner: auditOwner,
  month: '2026-10',
  days: days,
  entries: events,
  now: DateTime(2026, 11, 1),
  detailLimit: limit,
);

class _Account extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => const PlatformSession(
    platform: MusicPlatform.netease,
    userId: '987654',
    token: 'fixture-token',
  );
}

void main() {
  test(
    'local 683 minutes does not become fabricated or supposedly cloud-confirmed plays',
    () {
      final value = report(days: [day()]);
      expect(value.local['neteaseSongsActualMs'], 683 * 60000);
      expect(value.duration['events'], 0);
      expect(value.data['entries'], isEmpty);
      expect(value.data['cloudFootprintInclusionVerified'], isFalse);
      expect(value.months, containsAll(['2026-10', '2026-11']));
    },
  );
  test(
    'start receipts, recent matches and duration states remain independent',
    () {
      final value = report(
        events: [
          event(
            'start',
            kind: 'netease-startplay',
            payload: {'cloudConfirmed': true},
          ),
          event('old', payload: {'time': 120, 'heardMs': 120000}),
          event(
            'unknown',
            state: ListeningSyncState.unknown,
            payload: {'time': 30, 'realtime': 30},
          ),
          event(
            'queued',
            state: ListeningSyncState.queued,
            payload: {'time': 90},
          ),
        ],
      );
      expect(value.duration['events'], 3);
      expect(value.duration['knownActualMs'], 150000);
      expect(value.duration['unknownActualEvents'], 1);
      expect(value.starts['events'], 1);
      expect(value.starts['recentPlayConfirmed'], 1);
      final states = value.duration['states'] as Map;
      expect(states['accepted']['knownActualMs'], 120000);
      expect(states['queued']['unknownActualEvents'], 1);
      expect(value.fields['durationMissingRealtime'], 2);
      expect(value.fields['durationMissingStartlogtime'], 3);
    },
  );
  test(
    'original start month wins over retry/created date; fallback source is explicit',
    () {
      final start = DateTime(2026, 10, 31, 23, 59);
      final value = report(
        events: [
          event(
            'payload',
            created: DateTime(2026, 11, 1),
            payload: {
              'startlogtime': start.millisecondsSinceEpoch ~/ 1000,
              'heardMs': 60000,
              'realtime': 60,
              'time': 120,
              'protocolVersion': 2,
            },
          ),
          event(
            'netease-play:${start.microsecondsSinceEpoch}:9988776655',
            created: DateTime(2026, 11, 1),
            payload: {'heardMs': 10000},
          ),
          event('created', payload: {'heardMs': 5000}),
          event(
            'november',
            payload: {
              'startlogtime':
                  DateTime(2026, 11, 1).millisecondsSinceEpoch ~/ 1000,
              'heardMs': 90000,
            },
          ),
        ],
      );
      final rows = (value.data['entries'] as List).cast<Map>();
      expect(
        rows.map((e) => e['dateSource']),
        unorderedEquals([
          'startlogtime',
          'event_timestamp',
          'created_at_fallback',
        ]),
      );
      expect(value.duration['knownActualMs'], 75000);
      expect(value.fields['durationMissingStartlogtime'], 2);
    },
  );
  test(
    'account filtering, source filtering and duplicate input cannot inflate the report',
    () {
      final duplicate = event('same', payload: {'heardMs': 2000});
      final value = report(
        days: [
          day(),
          day(owner: 'netease:another'),
          day(song: false, ms: 5000),
        ],
        events: [
          duplicate,
          duplicate,
          event(
            'foreign',
            owner: 'netease:another',
            payload: {'heardMs': 900000},
          ),
        ],
      );
      expect(value.local['allTracksActualMs'], 683 * 60000 + 5000);
      expect(value.local['otherTracksActualMs'], 5000);
      expect(value.duration['events'], 1);
      expect(value.duration['knownActualMs'], 2000);
      expect(value.belongsTo(auditOwner), isTrue);
      expect(value.belongsTo('netease:another'), isFalse);
    },
  );
  test(
    'export whitelist excludes identity, timestamps, song content, cookies and arbitrary fields',
    () {
      final value = report(
        days: [day()],
        events: [
          event(
            'private-event-id',
            payload: {
              'heardMs': 90000,
              'time': 90,
              'title': 'private-title',
              'cookie': 'MUSIC_U=private-cookie',
              'url': 'https://private.example/song',
              'unknown-private-key': 'private-value',
              'startlogtime':
                  DateTime(2026, 10, 15, 8, 35).millisecondsSinceEpoch ~/ 1000,
            },
          ),
        ],
      );
      final text = value.json;
      for (final secret in [
        auditOwner,
        '987654',
        '9988776655',
        'private-event-id',
        'private-title',
        'private-cookie',
        'private.example',
        'private-value',
        'unknown-private-key',
        '08:35',
      ]) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
      expect(jsonDecode(text)['entries'][0]['songGroup'], 'song-1');
      expect(jsonDecode(text)['entries'][0]['day'], '2026-10-15');
    },
  );
  test(
    'detail cap is disclosed and does not truncate totals; media time never substitutes real time',
    () {
      final value = report(
        limit: 1,
        events: [
          event('one', payload: {'time': 200}),
          event('two', payload: {'heardMs': 5000}),
        ],
      );
      expect(value.data['detailTruncated'], isTrue);
      expect(value.data['totalDetailEntries'], 2);
      expect(value.duration['events'], 2);
      expect(value.duration['knownActualMs'], 5000);
      expect(value.duration['unknownActualEvents'], 1);
    },
  );
  test(
    'database snapshot is read-only and does not change journal states',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final store = ListeningSyncStore(database);
      await store.put(
        owner: auditOwner,
        id: 'pending-original',
        kind: 'netease-scrobble',
        payload: {'id': '17', 'heardMs': 60000, 'time': 60},
        now: DateTime(2026, 10, 20),
      );
      await database
          .into(database.playbackDailyHistories)
          .insert(
            PlaybackDailyHistoriesCompanion.insert(
              ownerId: const Value(auditOwner),
              dayKey: '2026-10-20',
              trackId: 'netease_17',
              trackSnapshot: '{}',
              totalPlayedMs: const Value(60000),
              lastPlayedAt: DateTime(2026, 10, 20),
            ),
          );
      final before = await store.entry(auditOwner, 'pending-original');
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          usesNeteaseProvider.overrideWithValue(true),
          platformAccountProvider.overrideWith(_Account.new),
        ],
      );
      addTearDown(container.dispose);
      await container.read(platformAccountProvider.future);
      final value = await container.read(
        neteaseListeningAuditProvider('2026-10').future,
      );
      expect(value.duration['events'], 1);
      expect(value.local['neteaseSongsActualMs'], 60000);
      final after = await store.entry(auditOwner, 'pending-original');
      expect(after!.state, before!.state);
      expect(after.payload, before.payload);
      expect(after.updatedAt, before.updatedAt);
    },
  );
}
