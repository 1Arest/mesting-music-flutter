import 'dart:convert';
import '../performance/track_snapshots.dart';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../shared/models/track.dart';
import '../sync/library_sync_models.dart';

part 'app_database.g.dart';

const legacyLibraryOwnerId = '__legacy_local__';

class FavoriteTracks extends Table {
  TextColumn get ownerId =>
      text().withDefault(const Constant(legacyLibraryOwnerId))();
  TextColumn get trackId => text()();
  TextColumn get trackSnapshot => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {ownerId, trackId};
}

class UserPlaylists extends Table {
  TextColumn get ownerId =>
      text().withDefault(const Constant(legacyLibraryOwnerId))();
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get coverAsset => text().nullable()();
  TextColumn get coverCloudId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {ownerId, id};
}

class UserPlaylistTracks extends Table {
  TextColumn get ownerId =>
      text().withDefault(const Constant(legacyLibraryOwnerId))();
  TextColumn get playlistId => text()();
  TextColumn get trackId => text()();
  TextColumn get trackSnapshot => text()();
  IntColumn get sortOrder => integer()();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {ownerId, playlistId, trackId};
}

/// Per-account local Outbox.
///
/// Library edits are first committed to the device database so the UI can
/// update immediately. The synchronizer later sends these compact mutations
/// to the backend and acknowledges them only after the server accepts them.
class SyncMutations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get ownerId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  TextColumn get payload => text().withDefault(const Constant('{}'))();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

class PlaybackSessions extends Table {
  TextColumn get ownerId =>
      text().withDefault(const Constant(legacyLibraryOwnerId))();
  IntColumn get id => integer()();
  TextColumn get queueSnapshot => text()();
  IntColumn get currentIndex => integer()();
  IntColumn get positionMs => integer()();
  TextColumn get playbackMode => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {ownerId, id};
}

class PlaybackHistories extends Table {
  TextColumn get ownerId =>
      text().withDefault(const Constant(legacyLibraryOwnerId))();
  TextColumn get trackId => text()();
  TextColumn get trackSnapshot => text()();
  IntColumn get playCount => integer().withDefault(const Constant(0))();
  IntColumn get completedPlayCount =>
      integer().withDefault(const Constant(0))();
  IntColumn get totalPlayedMs => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastPlayedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {ownerId, trackId};
}

class PlaybackDailyHistories extends Table {
  TextColumn get ownerId =>
      text().withDefault(const Constant(legacyLibraryOwnerId))();
  TextColumn get dayKey => text()();
  TextColumn get trackId => text()();
  TextColumn get trackSnapshot => text()();
  IntColumn get playCount => integer().withDefault(const Constant(0))();
  IntColumn get totalPlayedMs => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastPlayedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {ownerId, dayKey, trackId};
}

/// Durable platform reporting journal, separate from Mesting's cloud outbox.
/// A dispatched write is never made eligible for a blind retry after a crash.
/// Only compact facts are stored here; tokens and device identifiers stay out.
@DataClassName('PlatformListeningOutbox')
class PlatformListeningOutboxes extends Table {
  TextColumn get ownerId => text()();
  TextColumn get eventId => text()();
  TextColumn get kind => text()();
  TextColumn get payload => text()();
  TextColumn get state => text().withDefault(const Constant('queued'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {ownerId, eventId};
}

@DriftDatabase(
  tables: [
    FavoriteTracks,
    UserPlaylists,
    UserPlaylistTracks,
    SyncMutations,
    PlaybackSessions,
    PlaybackHistories,
    PlaybackDailyHistories,
    PlatformListeningOutboxes,
  ],
)
/// Device-local source of truth for the music library and playback state.
///
/// Every user-owned row carries an [ownerId]. That isolation is essential when
/// accounts switch on the same device: a cached playlist, listening history or
/// pending cloud mutation must never become visible to the next account.
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'mesting_music'));

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await _createListeningJournalIndexes();
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.alterTable(
          // Existing pinned audio/cache or schema migration API; covered by regression tests.
          // ignore: experimental_member_use
          TableMigration(
            favoriteTracks,
            newColumns: [
              favoriteTracks.ownerId,
              favoriteTracks.updatedAt,
              favoriteTracks.deletedAt,
            ],
            columnTransformer: {
              favoriteTracks.updatedAt: favoriteTracks.createdAt,
            },
          ),
        );
        await migrator.alterTable(
          // Existing pinned audio/cache or schema migration API; covered by regression tests.
          // ignore: experimental_member_use
          TableMigration(userPlaylists, newColumns: [userPlaylists.ownerId]),
        );
        await migrator.alterTable(
          // Existing pinned audio/cache or schema migration API; covered by regression tests.
          // ignore: experimental_member_use
          TableMigration(
            userPlaylistTracks,
            newColumns: [userPlaylistTracks.ownerId],
          ),
        );
        await migrator.createTable(syncMutations);
      }
      if (from < 3) {
        await migrator.createTable(playbackDailyHistories);
      }
      if (from < 4) {
        await migrator.addColumn(
          playbackHistories,
          playbackHistories.completedPlayCount,
        );
      }
      if (from < 5) {
        await migrator.alterTable(
          // Existing pinned audio/cache or schema migration API; covered by regression tests.
          // ignore: experimental_member_use
          TableMigration(
            playbackSessions,
            newColumns: [playbackSessions.ownerId],
          ),
        );
        await migrator.alterTable(
          // Existing pinned audio/cache or schema migration API; covered by regression tests.
          // ignore: experimental_member_use
          TableMigration(
            playbackHistories,
            newColumns: [playbackHistories.ownerId],
          ),
        );
        await migrator.alterTable(
          // Existing pinned audio/cache or schema migration API; covered by regression tests.
          // ignore: experimental_member_use
          TableMigration(
            playbackDailyHistories,
            newColumns: [playbackDailyHistories.ownerId],
          ),
        );
      }
      if (from < 6) {
        await migrator.addColumn(userPlaylists, userPlaylists.coverCloudId);
      }
      if (from < 7) {
        await migrator.createTable(platformListeningOutboxes);
        await _createListeningJournalIndexes();
      }
    },
  );

  /// A long-lived journal must drain pending work without rescanning months
  /// of confirmed facts on each playback edge. The primary key still owns
  /// event identity; these indexes serve state and chronological queries only.
  Future<void> _createListeningJournalIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS platform_listening_pending '
      'ON platform_listening_outboxes (owner_id, kind, state, created_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS platform_listening_timeline '
      'ON platform_listening_outboxes (owner_id, created_at)',
    );
  }

  /// SQL does ordering/filtering before LIMIT: a visible window never needs to
  /// decode every saved track. JSON keys are fixed and search terms are bound
  /// variables, including quotes, percent signs and non-ASCII song names.
  String _favoriteWhere(String query) {
    final count = query
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .length;
    return 'owner_id = ? AND deleted_at IS NULL${List.filled(count, " AND instr(lower(CASE WHEN json_valid(track_snapshot) THEN coalesce(json_extract(track_snapshot, '\$.title'),'') || ' ' || coalesce(json_extract(track_snapshot, '\$.artist'),'') || ' ' || coalesce(json_extract(track_snapshot, '\$.album'),'') ELSE '' END), ?) > 0").join()}';
  }

  List<Variable> _favoriteVariables(String ownerId, String query) => [
    Variable(ownerId),
    for (final word in query.trim().toLowerCase().split(RegExp(r'\s+')))
      if (word.isNotEmpty) Variable(word),
  ];

  Stream<List<FavoriteTrack>> watchFavoriteSlice(
    String ownerId, {
    int offset = 0,
    int limit = 30,
    String query = '',
  }) => customSelect(
    'SELECT * FROM favorite_tracks WHERE ${_favoriteWhere(query)} ORDER BY created_at DESC, track_id ASC LIMIT ? OFFSET ?',
    variables: [
      ..._favoriteVariables(ownerId, query),
      Variable(limit),
      Variable(offset),
    ],
    readsFrom: {favoriteTracks},
  ).watch().map((rows) => rows.map((row) => favoriteTracks.map(row.data)).toList());

  Future<List<FavoriteTrack>> favoriteSlice(
    String ownerId, {
    int offset = 0,
    int limit = 30,
    String query = '',
  }) => customSelect(
    'SELECT * FROM favorite_tracks WHERE ${_favoriteWhere(query)} ORDER BY created_at DESC, track_id ASC LIMIT ? OFFSET ?',
    variables: [
      ..._favoriteVariables(ownerId, query),
      Variable(limit),
      Variable(offset),
    ],
    readsFrom: {favoriteTracks},
  ).get().then((rows) => rows.map((row) => favoriteTracks.map(row.data)).toList());

  Future<int> favoriteCount(
    String ownerId, {
    String query = '',
  }) async => (await customSelect(
    'SELECT count(*) AS n FROM favorite_tracks WHERE ${_favoriteWhere(query)}',
    variables: _favoriteVariables(ownerId, query),
    readsFrom: {favoriteTracks},
  ).getSingle()).read<int>('n');

  Future<Set<String>> favoriteIds(String ownerId) async => {
    for (final row in await customSelect(
      'SELECT track_id FROM favorite_tracks WHERE owner_id = ? AND deleted_at IS NULL',
      variables: [Variable(ownerId)],
      readsFrom: {favoriteTracks},
    ).get())
      row.read<String>('track_id'),
  };

  Future<List<UserPlaylistTrack>> playlistTrackSlice(
    String ownerId,
    String playlistId, {
    int offset = 0,
    int limit = 30,
  }) =>
      (select(userPlaylistTracks)
            ..where(
              (row) =>
                  row.ownerId.equals(ownerId) &
                  row.playlistId.equals(playlistId),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)])
            ..limit(limit, offset: offset))
          .get();

  Future<int> playlistTrackCount(String ownerId, String playlistId) async {
    final count = userPlaylistTracks.trackId.count();
    final query = selectOnly(userPlaylistTracks)
      ..addColumns([count])
      ..where(
        userPlaylistTracks.ownerId.equals(ownerId) &
            userPlaylistTracks.playlistId.equals(playlistId),
      );
    return (await query.getSingle()).read(count) ?? 0;
  }

  Stream<List<FavoriteTrack>> watchFavorites(String ownerId) {
    return (select(favoriteTracks)
          ..where((row) => row.ownerId.equals(ownerId) & row.deletedAt.isNull())
          ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
        .watch();
  }

  Future<bool> isFavorite(String ownerId, String trackId) async {
    final row =
        await (select(favoriteTracks)..where(
              (entry) =>
                  entry.ownerId.equals(ownerId) &
                  entry.trackId.equals(trackId) &
                  entry.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    return row != null;
  }

  Future<void> setFavorite(
    String ownerId,
    Track track, {
    required bool favorite,
  }) async {
    final now = DateTime.now();
    await transaction(() async {
      final existing =
          await (select(favoriteTracks)..where(
                (entry) =>
                    entry.ownerId.equals(ownerId) &
                    entry.trackId.equals(track.id),
              ))
              .getSingleOrNull();
      await into(favoriteTracks).insertOnConflictUpdate(
        FavoriteTracksCompanion.insert(
          ownerId: Value(ownerId),
          trackId: track.id,
          trackSnapshot: jsonEncode(track.toJson()),
          createdAt: existing?.createdAt ?? now,
          updatedAt: now,
          deletedAt: Value(favorite ? null : now),
        ),
      );
      await _enqueueSyncMutation(
        ownerId: ownerId,
        entityType: 'favorite',
        entityId: track.id,
        operation: favorite ? 'upsert' : 'delete',
        payload: jsonEncode(track.toJson()),
      );
    });
  }

  Future<bool> toggleFavorite(String ownerId, Track track) async {
    final now = DateTime.now();
    var favorite = false;
    await transaction(() async {
      final existing =
          await (select(favoriteTracks)..where(
                (entry) =>
                    entry.ownerId.equals(ownerId) &
                    entry.trackId.equals(track.id),
              ))
              .getSingleOrNull();
      favorite = existing == null || existing.deletedAt != null;
      await into(favoriteTracks).insertOnConflictUpdate(
        FavoriteTracksCompanion.insert(
          ownerId: Value(ownerId),
          trackId: track.id,
          trackSnapshot: jsonEncode(track.toJson()),
          createdAt: existing?.createdAt ?? now,
          updatedAt: now,
          deletedAt: Value(favorite ? null : now),
        ),
      );
      await _enqueueSyncMutation(
        ownerId: ownerId,
        entityType: 'favorite',
        entityId: track.id,
        operation: favorite ? 'upsert' : 'delete',
        payload: jsonEncode(track.toJson()),
      );
    });
    return favorite;
  }

  Stream<List<UserPlaylist>> watchPlaylists(String ownerId) {
    return (select(userPlaylists)
          ..where((row) => row.ownerId.equals(ownerId))
          ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
        .watch();
  }

  Future<UserPlaylist?> getPlaylist(String ownerId, String id) {
    return (select(userPlaylists)
          ..where((row) => row.ownerId.equals(ownerId) & row.id.equals(id)))
        .getSingleOrNull();
  }

  Stream<List<UserPlaylistTrack>> watchPlaylistTracks(
    String ownerId,
    String playlistId,
  ) {
    return (select(userPlaylistTracks)
          ..where(
            (row) =>
                row.ownerId.equals(ownerId) & row.playlistId.equals(playlistId),
          )
          ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]))
        .watch();
  }

  Future<void> createPlaylist({
    required String ownerId,
    required String id,
    required String name,
    String description = '',
    String? coverAsset,
    String? coverCloudId,
  }) async {
    final now = DateTime.now();
    await into(userPlaylists).insert(
      UserPlaylistsCompanion.insert(
        ownerId: Value(ownerId),
        id: id,
        name: name,
        description: Value(description),
        coverAsset: Value(coverAsset),
        coverCloudId: Value(coverCloudId),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await _enqueueSyncMutation(
      ownerId: ownerId,
      entityType: 'playlist',
      entityId: id,
      operation: 'upsert',
      payload: jsonEncode({
        'id': id,
        'name': name,
        'description': description,
        'cover_asset': coverAsset,
        'cover_cloud_id': coverCloudId,
      }),
    );
  }

  Future<void> updatePlaylist({
    required String ownerId,
    required String id,
    required String name,
    required String description,
    required String? coverAsset,
    String? coverCloudId,
  }) async {
    await (update(
      userPlaylists,
    )..where((row) => row.ownerId.equals(ownerId) & row.id.equals(id))).write(
      UserPlaylistsCompanion(
        name: Value(name),
        description: Value(description),
        coverAsset: Value(coverAsset),
        coverCloudId: Value(coverCloudId),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _enqueueSyncMutation(
      ownerId: ownerId,
      entityType: 'playlist',
      entityId: id,
      operation: 'upsert',
      payload: jsonEncode({
        'id': id,
        'name': name,
        'description': description,
        'cover_asset': coverAsset,
        'cover_cloud_id': coverCloudId,
      }),
    );
  }

  Future<void> deletePlaylist(String ownerId, String id) async {
    await transaction(() async {
      await (delete(userPlaylistTracks)..where(
            (row) => row.ownerId.equals(ownerId) & row.playlistId.equals(id),
          ))
          .go();
      await (delete(
        userPlaylists,
      )..where((row) => row.ownerId.equals(ownerId) & row.id.equals(id))).go();
      await _enqueueSyncMutation(
        ownerId: ownerId,
        entityType: 'playlist',
        entityId: id,
        operation: 'delete',
      );
    });
  }

  Future<void> addTrackToPlaylist(
    String ownerId,
    String playlistId,
    Track track,
  ) async {
    final maximum = userPlaylistTracks.sortOrder.max();
    final query = selectOnly(userPlaylistTracks)
      ..addColumns([maximum])
      ..where(
        userPlaylistTracks.ownerId.equals(ownerId) &
            userPlaylistTracks.playlistId.equals(playlistId),
      );
    final currentMaximum = await query
        .map((row) => row.read(maximum))
        .getSingle();
    await transaction(() async {
      await into(userPlaylistTracks).insertOnConflictUpdate(
        UserPlaylistTracksCompanion.insert(
          ownerId: Value(ownerId),
          playlistId: playlistId,
          trackId: track.id,
          trackSnapshot: jsonEncode(track.toJson()),
          sortOrder: (currentMaximum ?? -1) + 1,
          addedAt: DateTime.now(),
        ),
      );
      await (update(userPlaylists)..where(
            (row) => row.ownerId.equals(ownerId) & row.id.equals(playlistId),
          ))
          .write(UserPlaylistsCompanion(updatedAt: Value(DateTime.now())));
      await _enqueueSyncMutation(
        ownerId: ownerId,
        entityType: 'playlist_item',
        entityId: '$playlistId:${track.id}',
        operation: 'upsert',
        payload: jsonEncode({
          'playlist_id': playlistId,
          'track': track.toJson(),
        }),
      );
    });
  }

  Future<void> removeTrackFromPlaylist(
    String ownerId,
    String playlistId,
    String trackId,
  ) async {
    await (delete(userPlaylistTracks)..where(
          (row) =>
              row.ownerId.equals(ownerId) &
              row.playlistId.equals(playlistId) &
              row.trackId.equals(trackId),
        ))
        .go();
    await _normalizePlaylistOrder(ownerId, playlistId);
    await _enqueueSyncMutation(
      ownerId: ownerId,
      entityType: 'playlist_item',
      entityId: '$playlistId:$trackId',
      operation: 'delete',
      payload: jsonEncode({'playlist_id': playlistId, 'track_id': trackId}),
    );
  }

  Future<void> reorderPlaylistTracks(
    String ownerId,
    String playlistId,
    List<String> orderedTrackIds,
  ) async {
    await transaction(() async {
      for (var index = 0; index < orderedTrackIds.length; index += 1) {
        await (update(userPlaylistTracks)..where(
              (row) =>
                  row.ownerId.equals(ownerId) &
                  row.playlistId.equals(playlistId) &
                  row.trackId.equals(orderedTrackIds[index]),
            ))
            .write(UserPlaylistTracksCompanion(sortOrder: Value(index)));
      }
      await (update(userPlaylists)..where(
            (row) => row.ownerId.equals(ownerId) & row.id.equals(playlistId),
          ))
          .write(UserPlaylistsCompanion(updatedAt: Value(DateTime.now())));
      await _enqueueSyncMutation(
        ownerId: ownerId,
        entityType: 'playlist_order',
        entityId: playlistId,
        operation: 'upsert',
        payload: jsonEncode({'track_ids': orderedTrackIds}),
      );
    });
  }

  Future<void> _normalizePlaylistOrder(
    String ownerId,
    String playlistId,
  ) async {
    final rows =
        await (select(userPlaylistTracks)
              ..where(
                (row) =>
                    row.ownerId.equals(ownerId) &
                    row.playlistId.equals(playlistId),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]))
            .get();
    await reorderPlaylistTracks(
      ownerId,
      playlistId,
      rows.map((row) => row.trackId).toList(),
    );
  }

  Future<int> countLegacyFavorites() async {
    final count = favoriteTracks.trackId.count();
    final query = selectOnly(favoriteTracks)
      ..addColumns([count])
      ..where(
        favoriteTracks.ownerId.equals(legacyLibraryOwnerId) &
            favoriteTracks.deletedAt.isNull(),
      );
    return await query.map((row) => row.read(count) ?? 0).getSingle();
  }

  /// Copies pre-account local-library data into [ownerId]'s namespace.
  ///
  /// The legacy rows are deliberately retained. They are a migration source,
  /// while the account copy receives its own Outbox mutations for cloud sync.
  Future<void> importLegacyLibraryTo(String ownerId) async {
    if (ownerId == legacyLibraryOwnerId) return;
    await transaction(() async {
      final now = DateTime.now();
      final favorites =
          await (select(favoriteTracks)..where(
                (row) =>
                    row.ownerId.equals(legacyLibraryOwnerId) &
                    row.deletedAt.isNull(),
              ))
              .get();
      for (final row in favorites) {
        await into(favoriteTracks).insertOnConflictUpdate(
          FavoriteTracksCompanion.insert(
            ownerId: Value(ownerId),
            trackId: row.trackId,
            trackSnapshot: row.trackSnapshot,
            createdAt: row.createdAt,
            updatedAt: now,
            deletedAt: const Value(null),
          ),
        );
        await _enqueueSyncMutation(
          ownerId: ownerId,
          entityType: 'favorite',
          entityId: row.trackId,
          operation: 'upsert',
          payload: row.trackSnapshot,
        );
      }

      final playlists = await (select(
        userPlaylists,
      )..where((row) => row.ownerId.equals(legacyLibraryOwnerId))).get();
      for (final row in playlists) {
        await into(userPlaylists).insertOnConflictUpdate(
          UserPlaylistsCompanion.insert(
            ownerId: Value(ownerId),
            id: row.id,
            name: row.name,
            description: Value(row.description),
            coverAsset: Value(row.coverAsset),
            coverCloudId: Value(row.coverCloudId),
            createdAt: row.createdAt,
            updatedAt: now,
          ),
        );
        await _enqueueSyncMutation(
          ownerId: ownerId,
          entityType: 'playlist',
          entityId: row.id,
          operation: 'upsert',
          payload: jsonEncode({
            'id': row.id,
            'name': row.name,
            'description': row.description,
            'cover_asset': row.coverAsset,
            'cover_cloud_id': row.coverCloudId,
          }),
        );
      }

      final items = await (select(
        userPlaylistTracks,
      )..where((row) => row.ownerId.equals(legacyLibraryOwnerId))).get();
      for (final row in items) {
        await into(userPlaylistTracks).insertOnConflictUpdate(
          UserPlaylistTracksCompanion.insert(
            ownerId: Value(ownerId),
            playlistId: row.playlistId,
            trackId: row.trackId,
            trackSnapshot: row.trackSnapshot,
            sortOrder: row.sortOrder,
            addedAt: row.addedAt,
          ),
        );
        await _enqueueSyncMutation(
          ownerId: ownerId,
          entityType: 'playlist_item',
          entityId: '${row.playlistId}:${row.trackId}',
          operation: 'upsert',
          payload: jsonEncode({
            'playlist_id': row.playlistId,
            'track': jsonDecode(row.trackSnapshot),
            'sort_order': row.sortOrder,
          }),
        );
      }
    });
  }

  /// Returns the oldest unacknowledged Outbox entries first.
  ///
  /// Sending in insertion order preserves the user's edit intent when several
  /// different library entities are changed while the device is offline.
  Future<List<LibrarySyncMutation>> pendingLibraryMutations(
    String ownerId, {
    int limit = 100,
  }) async {
    final rows =
        await (select(syncMutations)
              ..where((row) => row.ownerId.equals(ownerId))
              ..orderBy([(row) => OrderingTerm.asc(row.id)])
              ..limit(limit))
            .get();
    return rows
        .map((row) {
          Map<String, Object?> payload;
          try {
            final decoded = jsonDecode(row.payload);
            payload = decoded is Map
                ? Map<String, Object?>.from(decoded)
                : const <String, Object?>{};
          } on Object {
            payload = const <String, Object?>{};
          }
          return LibrarySyncMutation(
            localId: row.id,
            entityType: row.entityType,
            entityId: row.entityId,
            operation: row.operation,
            payload: payload,
            createdAt: row.createdAt,
          );
        })
        .toList(growable: false);
  }

  /// Rebuilds an Outbox snapshot when an account needs a first cloud upload.
  ///
  /// History rows use replacement mutations because only their newest totals
  /// matter; favorites and playlist rows retain the normal entity mutation
  /// semantics used by later incremental edits.
  Future<void> enqueueLibraryCloudBootstrap(String ownerId) async {
    await transaction(() async {
      final favorites =
          await (select(favoriteTracks)..where(
                (row) => row.ownerId.equals(ownerId) & row.deletedAt.isNull(),
              ))
              .get();
      for (final row in favorites) {
        await _enqueueSyncMutation(
          ownerId: ownerId,
          entityType: 'favorite',
          entityId: row.trackId,
          operation: 'upsert',
          payload: row.trackSnapshot,
        );
      }

      final playlists = await (select(
        userPlaylists,
      )..where((row) => row.ownerId.equals(ownerId))).get();
      for (final row in playlists) {
        await _enqueueSyncMutation(
          ownerId: ownerId,
          entityType: 'playlist',
          entityId: row.id,
          operation: 'upsert',
          payload: jsonEncode({
            'id': row.id,
            'name': row.name,
            'description': row.description,
            'cover_asset': row.coverAsset,
            'cover_cloud_id': row.coverCloudId,
          }),
        );
      }

      final items = await (select(
        userPlaylistTracks,
      )..where((row) => row.ownerId.equals(ownerId))).get();
      for (final row in items) {
        await _enqueueSyncMutation(
          ownerId: ownerId,
          entityType: 'playlist_item',
          entityId: '${row.playlistId}:${row.trackId}',
          operation: 'upsert',
          payload: jsonEncode({
            'playlist_id': row.playlistId,
            'track': jsonDecode(row.trackSnapshot),
            'sort_order': row.sortOrder,
          }),
        );
      }

      final histories = await (select(
        playbackHistories,
      )..where((row) => row.ownerId.equals(ownerId))).get();
      for (final row in histories) {
        await _replacePendingSyncMutation(
          ownerId: ownerId,
          entityType: 'playback_history',
          entityId: row.trackId,
          payload: jsonEncode(_playbackHistoryPayload(row)),
        );
      }

      final dailyHistories = await (select(
        playbackDailyHistories,
      )..where((row) => row.ownerId.equals(ownerId))).get();
      for (final row in dailyHistories) {
        await _replacePendingSyncMutation(
          ownerId: ownerId,
          entityType: 'playback_daily_history',
          entityId: '${row.dayKey}:${row.trackId}',
          payload: jsonEncode(_playbackDailyHistoryPayload(row)),
        );
      }
    });
  }

  Future<void> acknowledgeLibraryMutations(
    String ownerId,
    Iterable<int> mutationIds,
  ) async {
    final ids = mutationIds.toList(growable: false);
    if (ids.isEmpty) return;
    await (delete(
      syncMutations,
    )..where((row) => row.ownerId.equals(ownerId) & row.id.isIn(ids))).go();
  }

  Future<int> countPendingLibraryMutations(String ownerId) async {
    final count = syncMutations.id.count();
    final query = selectOnly(syncMutations)
      ..addColumns([count])
      ..where(syncMutations.ownerId.equals(ownerId));
    return query.map((row) => row.read(count) ?? 0).getSingle();
  }

  Future<void> replaceLibraryFromCloud(
    String ownerId,
    CloudLibrarySnapshot snapshot,
  ) async {
    await transaction(() => _replaceLibraryRows(ownerId, snapshot));
  }

  /// Atomically acknowledges uploaded mutations and applies a cloud snapshot.
  ///
  /// A snapshot is authoritative only when no newer local mutation remains.
  /// Returning `false` tells the caller to upload the newly queued edits first
  /// instead of accidentally overwriting them with an older server response.
  Future<bool> completeLibrarySync(
    String ownerId, {
    required Iterable<int> acknowledgedMutationIds,
    required CloudLibrarySnapshot snapshot,
  }) async {
    return transaction(() async {
      final ids = acknowledgedMutationIds.toList(growable: false);
      if (ids.isNotEmpty) {
        await (delete(
          syncMutations,
        )..where((row) => row.ownerId.equals(ownerId) & row.id.isIn(ids))).go();
      }
      final remaining = await countPendingLibraryMutations(ownerId);
      if (remaining > 0) return false;
      await _replaceLibraryRows(ownerId, snapshot);
      return true;
    });
  }

  /// Removes all device-local library and playback rows owned by an account
  /// after the backend has confirmed irreversible account deletion.
  Future<void> deleteOwnerData(String ownerId) async {
    await transaction(() async {
      await (delete(
        syncMutations,
      )..where((row) => row.ownerId.equals(ownerId))).go();
      await (delete(
        favoriteTracks,
      )..where((row) => row.ownerId.equals(ownerId))).go();
      await (delete(
        userPlaylistTracks,
      )..where((row) => row.ownerId.equals(ownerId))).go();
      await (delete(
        userPlaylists,
      )..where((row) => row.ownerId.equals(ownerId))).go();
      await (delete(
        playbackSessions,
      )..where((row) => row.ownerId.equals(ownerId))).go();
      await (delete(
        playbackHistories,
      )..where((row) => row.ownerId.equals(ownerId))).go();
      await (delete(
        playbackDailyHistories,
      )..where((row) => row.ownerId.equals(ownerId))).go();
    });
  }

  /// Replaces one account's materialized local library from a trusted snapshot.
  ///
  /// Callers must run this inside the same transaction that establishes there
  /// are no newer pending mutations for [ownerId].
  Future<void> _replaceLibraryRows(
    String ownerId,
    CloudLibrarySnapshot snapshot,
  ) async {
    await (delete(
      favoriteTracks,
    )..where((row) => row.ownerId.equals(ownerId))).go();
    await (delete(
      userPlaylistTracks,
    )..where((row) => row.ownerId.equals(ownerId))).go();
    await (delete(
      userPlaylists,
    )..where((row) => row.ownerId.equals(ownerId))).go();
    if (snapshot.includesPlaybackHistories) {
      await (delete(
        playbackHistories,
      )..where((row) => row.ownerId.equals(ownerId))).go();
    }
    if (snapshot.includesPlaybackDailyHistories) {
      await (delete(
        playbackDailyHistories,
      )..where((row) => row.ownerId.equals(ownerId))).go();
    }

    for (final favorite in snapshot.favorites) {
      await into(favoriteTracks).insert(
        FavoriteTracksCompanion.insert(
          ownerId: Value(ownerId),
          trackId: favorite.track.id,
          trackSnapshot: jsonEncode(favorite.track.toJson()),
          createdAt: favorite.createdAt,
          updatedAt: favorite.updatedAt,
          deletedAt: const Value(null),
        ),
      );
    }

    for (final playlist in snapshot.playlists) {
      await into(userPlaylists).insert(
        UserPlaylistsCompanion.insert(
          ownerId: Value(ownerId),
          id: playlist.id,
          name: playlist.name,
          description: Value(playlist.description),
          coverAsset: Value(playlist.coverAsset),
          coverCloudId: Value(playlist.coverCloudId),
          createdAt: playlist.createdAt,
          updatedAt: playlist.updatedAt,
        ),
      );
      for (final item in playlist.tracks) {
        await into(userPlaylistTracks).insert(
          UserPlaylistTracksCompanion.insert(
            ownerId: Value(ownerId),
            playlistId: playlist.id,
            trackId: item.track.id,
            trackSnapshot: jsonEncode(item.track.toJson()),
            sortOrder: item.sortOrder,
            addedAt: item.addedAt,
          ),
        );
      }
    }

    if (snapshot.includesPlaybackHistories) {
      for (final history in snapshot.playbackHistories) {
        await into(playbackHistories).insert(
          PlaybackHistoriesCompanion.insert(
            ownerId: Value(ownerId),
            trackId: history.track.id,
            trackSnapshot: jsonEncode(history.track.toJson()),
            playCount: Value(history.playCount),
            completedPlayCount: Value(history.completedPlayCount),
            totalPlayedMs: Value(history.totalPlayedMs),
            lastPlayedAt: history.lastPlayedAt,
          ),
        );
      }
    }
    if (snapshot.includesPlaybackDailyHistories) {
      for (final history in snapshot.playbackDailyHistories) {
        await into(playbackDailyHistories).insert(
          PlaybackDailyHistoriesCompanion.insert(
            ownerId: Value(ownerId),
            dayKey: history.dayKey,
            trackId: history.track.id,
            trackSnapshot: jsonEncode(history.track.toJson()),
            playCount: Value(history.playCount),
            totalPlayedMs: Value(history.totalPlayedMs),
            lastPlayedAt: history.lastPlayedAt,
          ),
        );
      }
    }
  }

  Future<void> _enqueueSyncMutation({
    required String ownerId,
    required String entityType,
    required String entityId,
    required String operation,
    String payload = '{}',
  }) async {
    // Only the newest pending state for an entity needs to cross the network.
    // This also collapses rapid favorite toggles and playlist edits into one
    // CloudBase mutation while preserving the local-first UI response.
    await (delete(syncMutations)..where(
          (row) =>
              row.ownerId.equals(ownerId) &
              row.entityType.equals(entityType) &
              row.entityId.equals(entityId),
        ))
        .go();
    await into(syncMutations).insert(
      SyncMutationsCompanion.insert(
        ownerId: ownerId,
        entityType: entityType,
        entityId: entityId,
        operation: operation,
        payload: Value(payload),
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> _replacePendingSyncMutation({
    required String ownerId,
    required String entityType,
    required String entityId,
    required String payload,
  }) async {
    await (delete(syncMutations)..where(
          (row) =>
              row.ownerId.equals(ownerId) &
              row.entityType.equals(entityType) &
              row.entityId.equals(entityId),
        ))
        .go();
    await _enqueueSyncMutation(
      ownerId: ownerId,
      entityType: entityType,
      entityId: entityId,
      operation: 'upsert',
      payload: payload,
    );
  }

  /// Stores one resumable playback snapshot per account (`id == 1`).
  ///
  /// The queue is stored as track JSON rather than audio-source state so a
  /// later app version can safely rebuild the audio engine during restoration.
  Future<void> savePlaybackSession({
    required String ownerId,
    required List<Track> queue,
    required int currentIndex,
    required Duration position,
    required String playbackMode,
  }) async {
    await into(playbackSessions).insertOnConflictUpdate(
      PlaybackSessionsCompanion.insert(
        ownerId: Value(ownerId),
        id: 1,
        queueSnapshot: await encodeTrackQueue(queue),
        currentIndex: currentIndex,
        positionMs: position.inMilliseconds,
        playbackMode: playbackMode,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<PlaybackSession?> loadPlaybackSession(String ownerId) {
    return (select(playbackSessions)
          ..where((row) => row.ownerId.equals(ownerId) & row.id.equals(1)))
        .getSingleOrNull();
  }

  Future<void> recordPlayback(
    String ownerId,
    Track track,
    Duration listened,
  ) async {
    final now = DateTime.now();
    final dayKey = _playbackDayKey(now);
    final snapshot = jsonEncode(track.toJson());
    await transaction(() async {
      final existing =
          await (select(playbackHistories)..where(
                (row) =>
                    row.ownerId.equals(ownerId) & row.trackId.equals(track.id),
              ))
              .getSingleOrNull();
      await into(playbackHistories).insertOnConflictUpdate(
        PlaybackHistoriesCompanion.insert(
          ownerId: Value(ownerId),
          trackId: track.id,
          trackSnapshot: snapshot,
          playCount: Value((existing?.playCount ?? 0) + 1),
          totalPlayedMs: Value(
            (existing?.totalPlayedMs ?? 0) + listened.inMilliseconds,
          ),
          lastPlayedAt: now,
        ),
      );

      final daily =
          await (select(playbackDailyHistories)..where(
                (row) =>
                    row.ownerId.equals(ownerId) &
                    row.dayKey.equals(dayKey) &
                    row.trackId.equals(track.id),
              ))
              .getSingleOrNull();
      await into(playbackDailyHistories).insertOnConflictUpdate(
        PlaybackDailyHistoriesCompanion.insert(
          ownerId: Value(ownerId),
          dayKey: dayKey,
          trackId: track.id,
          trackSnapshot: snapshot,
          playCount: Value((daily?.playCount ?? 0) + 1),
          totalPlayedMs: Value(
            (daily?.totalPlayedMs ?? 0) + listened.inMilliseconds,
          ),
          lastPlayedAt: now,
        ),
      );
      final aggregate = PlaybackHistory(
        ownerId: ownerId,
        trackId: track.id,
        trackSnapshot: snapshot,
        playCount: (existing?.playCount ?? 0) + 1,
        completedPlayCount: existing?.completedPlayCount ?? 0,
        totalPlayedMs: (existing?.totalPlayedMs ?? 0) + listened.inMilliseconds,
        lastPlayedAt: now,
      );
      final dailyAggregate = PlaybackDailyHistory(
        ownerId: ownerId,
        dayKey: dayKey,
        trackId: track.id,
        trackSnapshot: snapshot,
        playCount: (daily?.playCount ?? 0) + 1,
        totalPlayedMs: (daily?.totalPlayedMs ?? 0) + listened.inMilliseconds,
        lastPlayedAt: now,
      );
      await _replacePendingSyncMutation(
        ownerId: ownerId,
        entityType: 'playback_history',
        entityId: track.id,
        payload: jsonEncode(_playbackHistoryPayload(aggregate)),
      );
      await _replacePendingSyncMutation(
        ownerId: ownerId,
        entityType: 'playback_daily_history',
        entityId: '$dayKey:${track.id}',
        payload: jsonEncode(_playbackDailyHistoryPayload(dailyAggregate)),
      );
    });
  }

  Future<void> addPlaybackDuration(
    String ownerId,
    String trackId,
    Duration listened,
  ) async {
    if (listened <= Duration.zero) return;
    final now = DateTime.now();
    final dayKey = _playbackDayKey(now);
    await transaction(() async {
      final existing =
          await (select(playbackHistories)..where(
                (row) =>
                    row.ownerId.equals(ownerId) & row.trackId.equals(trackId),
              ))
              .getSingleOrNull();
      if (existing == null) return;
      await (update(playbackHistories)..where(
            (row) => row.ownerId.equals(ownerId) & row.trackId.equals(trackId),
          ))
          .write(
            PlaybackHistoriesCompanion(
              totalPlayedMs: Value(
                existing.totalPlayedMs + listened.inMilliseconds,
              ),
              lastPlayedAt: Value(now),
            ),
          );

      final daily =
          await (select(playbackDailyHistories)..where(
                (row) =>
                    row.ownerId.equals(ownerId) &
                    row.dayKey.equals(dayKey) &
                    row.trackId.equals(trackId),
              ))
              .getSingleOrNull();
      if (daily == null) {
        await into(playbackDailyHistories).insert(
          PlaybackDailyHistoriesCompanion.insert(
            ownerId: Value(ownerId),
            dayKey: dayKey,
            trackId: trackId,
            trackSnapshot: existing.trackSnapshot,
            playCount: const Value(1),
            totalPlayedMs: Value(listened.inMilliseconds),
            lastPlayedAt: now,
          ),
        );
      } else {
        await (update(playbackDailyHistories)..where(
              (row) =>
                  row.ownerId.equals(ownerId) &
                  row.dayKey.equals(dayKey) &
                  row.trackId.equals(trackId),
            ))
            .write(
              PlaybackDailyHistoriesCompanion(
                totalPlayedMs: Value(
                  daily.totalPlayedMs + listened.inMilliseconds,
                ),
                lastPlayedAt: Value(now),
              ),
            );
      }
      final aggregate = existing.copyWith(
        totalPlayedMs: existing.totalPlayedMs + listened.inMilliseconds,
        lastPlayedAt: now,
      );
      final dailyAggregate = daily == null
          ? PlaybackDailyHistory(
              ownerId: ownerId,
              dayKey: dayKey,
              trackId: trackId,
              trackSnapshot: existing.trackSnapshot,
              playCount: 1,
              totalPlayedMs: listened.inMilliseconds,
              lastPlayedAt: now,
            )
          : daily.copyWith(
              totalPlayedMs: daily.totalPlayedMs + listened.inMilliseconds,
              lastPlayedAt: now,
            );
      await _replacePendingSyncMutation(
        ownerId: ownerId,
        entityType: 'playback_history',
        entityId: trackId,
        payload: jsonEncode(_playbackHistoryPayload(aggregate)),
      );
      await _replacePendingSyncMutation(
        ownerId: ownerId,
        entityType: 'playback_daily_history',
        entityId: '$dayKey:$trackId',
        payload: jsonEncode(_playbackDailyHistoryPayload(dailyAggregate)),
      );
    });
  }

  /// Records a natural end-of-track event. Loading, pausing, seeking, or
  /// manually skipping a track must never call this method.
  Future<void> recordCompletedPlayback(String ownerId, Track track) async {
    final now = DateTime.now();
    final snapshot = jsonEncode(track.toJson());
    await transaction(() async {
      final existing =
          await (select(playbackHistories)..where(
                (row) =>
                    row.ownerId.equals(ownerId) & row.trackId.equals(track.id),
              ))
              .getSingleOrNull();
      await into(playbackHistories).insertOnConflictUpdate(
        PlaybackHistoriesCompanion.insert(
          ownerId: Value(ownerId),
          trackId: track.id,
          trackSnapshot: snapshot,
          playCount: Value(existing?.playCount ?? 1),
          completedPlayCount: Value((existing?.completedPlayCount ?? 0) + 1),
          totalPlayedMs: Value(existing?.totalPlayedMs ?? 0),
          lastPlayedAt: now,
        ),
      );
      final aggregate = PlaybackHistory(
        ownerId: ownerId,
        trackId: track.id,
        trackSnapshot: snapshot,
        playCount: existing?.playCount ?? 1,
        completedPlayCount: (existing?.completedPlayCount ?? 0) + 1,
        totalPlayedMs: existing?.totalPlayedMs ?? 0,
        lastPlayedAt: now,
      );
      await _replacePendingSyncMutation(
        ownerId: ownerId,
        entityType: 'playback_history',
        entityId: track.id,
        payload: jsonEncode(_playbackHistoryPayload(aggregate)),
      );
    });
  }

  Stream<List<PlaybackHistory>> watchPlaybackHistory(String ownerId) {
    return (select(playbackHistories)
          ..where((row) => row.ownerId.equals(ownerId))
          ..orderBy([(row) => OrderingTerm.desc(row.lastPlayedAt)]))
        .watch();
  }

  SimpleSelectStatement<$PlaybackHistoriesTable, PlaybackHistory>
  _historyPageQuery(
    String ownerId, {
    bool ranking = false,
    int offset = 0,
    int limit = 30,
  }) => select(playbackHistories)
    ..where((row) => row.ownerId.equals(ownerId))
    ..orderBy([
      if (ranking) (row) => OrderingTerm.desc(row.completedPlayCount),
      (row) => OrderingTerm.desc(row.lastPlayedAt),
      (row) => OrderingTerm.asc(row.trackId),
    ])
    ..limit(limit, offset: offset);

  Future<List<PlaybackHistory>> playbackHistoryPage(
    String ownerId, {
    bool ranking = false,
    int offset = 0,
    int limit = 30,
  }) => _historyPageQuery(
    ownerId,
    ranking: ranking,
    offset: offset,
    limit: limit,
  ).get();
  Stream<List<PlaybackHistory>> watchPlaybackHistoryPreview(
    String ownerId, {
    bool ranking = false,
  }) => _historyPageQuery(ownerId, ranking: ranking).watch();
  Future<int> playbackHistoryCount(String ownerId) async => (await customSelect(
    'SELECT count(*) AS total FROM playback_histories WHERE owner_id = ?',
    variables: [Variable<String>(ownerId)],
    readsFrom: {playbackHistories},
  ).getSingle()).read<int>('total');

  Stream<List<PlaybackHistory>> watchListeningRanking(String ownerId) {
    return (select(playbackHistories)
          ..where((row) => row.ownerId.equals(ownerId))
          ..orderBy([
            (row) => OrderingTerm.desc(row.completedPlayCount),
            (row) => OrderingTerm.desc(row.lastPlayedAt),
          ]))
        .watch();
  }

  /// Replay reads durable daily facts for one owner. Aggregation stays outside
  /// the database so calendar selection does not create a second history store.
  Stream<List<PlaybackDailyHistory>> watchPlaybackDays(String ownerId) =>
      (select(playbackDailyHistories)
            ..where((row) => row.ownerId.equals(ownerId))
            ..orderBy([(row) => OrderingTerm.desc(row.dayKey)]))
          .watch();

  Stream<List<PlaybackDailyHistory>> watchPlaybackHistoryForDay(
    String ownerId,
    DateTime day,
  ) {
    final dayKey = _playbackDayKey(day);
    return (select(playbackDailyHistories)
          ..where(
            (row) => row.ownerId.equals(ownerId) & row.dayKey.equals(dayKey),
          )
          ..orderBy([(row) => OrderingTerm.desc(row.lastPlayedAt)]))
        .watch();
  }
}

Map<String, Object?> _playbackHistoryPayload(PlaybackHistory row) => {
  'track': jsonDecode(row.trackSnapshot),
  'play_count': row.playCount,
  'completed_play_count': row.completedPlayCount,
  'total_played_ms': row.totalPlayedMs,
  'last_played_at': row.lastPlayedAt.toUtc().toIso8601String(),
};

Map<String, Object?> _playbackDailyHistoryPayload(PlaybackDailyHistory row) => {
  'day_key': row.dayKey,
  'track': jsonDecode(row.trackSnapshot),
  'play_count': row.playCount,
  'total_played_ms': row.totalPlayedMs,
  'last_played_at': row.lastPlayedAt.toUtc().toIso8601String(),
};

String _playbackDayKey(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}
