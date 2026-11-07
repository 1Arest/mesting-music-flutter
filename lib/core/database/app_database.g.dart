// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $FavoriteTracksTable extends FavoriteTracks
    with TableInfo<$FavoriteTracksTable, FavoriteTrack> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FavoriteTracksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(legacyLibraryOwnerId),
  );
  static const VerificationMeta _trackIdMeta = const VerificationMeta(
    'trackId',
  );
  @override
  late final GeneratedColumn<String> trackId = GeneratedColumn<String>(
    'track_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _trackSnapshotMeta = const VerificationMeta(
    'trackSnapshot',
  );
  @override
  late final GeneratedColumn<String> trackSnapshot = GeneratedColumn<String>(
    'track_snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerId,
    trackId,
    trackSnapshot,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'favorite_tracks';
  @override
  VerificationContext validateIntegrity(
    Insertable<FavoriteTrack> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    }
    if (data.containsKey('track_id')) {
      context.handle(
        _trackIdMeta,
        trackId.isAcceptableOrUnknown(data['track_id']!, _trackIdMeta),
      );
    } else if (isInserting) {
      context.missing(_trackIdMeta);
    }
    if (data.containsKey('track_snapshot')) {
      context.handle(
        _trackSnapshotMeta,
        trackSnapshot.isAcceptableOrUnknown(
          data['track_snapshot']!,
          _trackSnapshotMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_trackSnapshotMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerId, trackId};
  @override
  FavoriteTrack map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FavoriteTrack(
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      trackId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_id'],
      )!,
      trackSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_snapshot'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $FavoriteTracksTable createAlias(String alias) {
    return $FavoriteTracksTable(attachedDatabase, alias);
  }
}

class FavoriteTrack extends DataClass implements Insertable<FavoriteTrack> {
  final String ownerId;
  final String trackId;
  final String trackSnapshot;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const FavoriteTrack({
    required this.ownerId,
    required this.trackId,
    required this.trackSnapshot,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_id'] = Variable<String>(ownerId);
    map['track_id'] = Variable<String>(trackId);
    map['track_snapshot'] = Variable<String>(trackSnapshot);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  FavoriteTracksCompanion toCompanion(bool nullToAbsent) {
    return FavoriteTracksCompanion(
      ownerId: Value(ownerId),
      trackId: Value(trackId),
      trackSnapshot: Value(trackSnapshot),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory FavoriteTrack.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FavoriteTrack(
      ownerId: serializer.fromJson<String>(json['ownerId']),
      trackId: serializer.fromJson<String>(json['trackId']),
      trackSnapshot: serializer.fromJson<String>(json['trackSnapshot']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerId': serializer.toJson<String>(ownerId),
      'trackId': serializer.toJson<String>(trackId),
      'trackSnapshot': serializer.toJson<String>(trackSnapshot),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  FavoriteTrack copyWith({
    String? ownerId,
    String? trackId,
    String? trackSnapshot,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => FavoriteTrack(
    ownerId: ownerId ?? this.ownerId,
    trackId: trackId ?? this.trackId,
    trackSnapshot: trackSnapshot ?? this.trackSnapshot,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  FavoriteTrack copyWithCompanion(FavoriteTracksCompanion data) {
    return FavoriteTrack(
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      trackId: data.trackId.present ? data.trackId.value : this.trackId,
      trackSnapshot: data.trackSnapshot.present
          ? data.trackSnapshot.value
          : this.trackSnapshot,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteTrack(')
          ..write('ownerId: $ownerId, ')
          ..write('trackId: $trackId, ')
          ..write('trackSnapshot: $trackSnapshot, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerId,
    trackId,
    trackSnapshot,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FavoriteTrack &&
          other.ownerId == this.ownerId &&
          other.trackId == this.trackId &&
          other.trackSnapshot == this.trackSnapshot &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class FavoriteTracksCompanion extends UpdateCompanion<FavoriteTrack> {
  final Value<String> ownerId;
  final Value<String> trackId;
  final Value<String> trackSnapshot;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const FavoriteTracksCompanion({
    this.ownerId = const Value.absent(),
    this.trackId = const Value.absent(),
    this.trackSnapshot = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FavoriteTracksCompanion.insert({
    this.ownerId = const Value.absent(),
    required String trackId,
    required String trackSnapshot,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : trackId = Value(trackId),
       trackSnapshot = Value(trackSnapshot),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<FavoriteTrack> custom({
    Expression<String>? ownerId,
    Expression<String>? trackId,
    Expression<String>? trackSnapshot,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerId != null) 'owner_id': ownerId,
      if (trackId != null) 'track_id': trackId,
      if (trackSnapshot != null) 'track_snapshot': trackSnapshot,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FavoriteTracksCompanion copyWith({
    Value<String>? ownerId,
    Value<String>? trackId,
    Value<String>? trackSnapshot,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return FavoriteTracksCompanion(
      ownerId: ownerId ?? this.ownerId,
      trackId: trackId ?? this.trackId,
      trackSnapshot: trackSnapshot ?? this.trackSnapshot,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (trackId.present) {
      map['track_id'] = Variable<String>(trackId.value);
    }
    if (trackSnapshot.present) {
      map['track_snapshot'] = Variable<String>(trackSnapshot.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteTracksCompanion(')
          ..write('ownerId: $ownerId, ')
          ..write('trackId: $trackId, ')
          ..write('trackSnapshot: $trackSnapshot, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UserPlaylistsTable extends UserPlaylists
    with TableInfo<$UserPlaylistsTable, UserPlaylist> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserPlaylistsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(legacyLibraryOwnerId),
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _coverAssetMeta = const VerificationMeta(
    'coverAsset',
  );
  @override
  late final GeneratedColumn<String> coverAsset = GeneratedColumn<String>(
    'cover_asset',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverCloudIdMeta = const VerificationMeta(
    'coverCloudId',
  );
  @override
  late final GeneratedColumn<String> coverCloudId = GeneratedColumn<String>(
    'cover_cloud_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerId,
    id,
    name,
    description,
    coverAsset,
    coverCloudId,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'user_playlists';
  @override
  VerificationContext validateIntegrity(
    Insertable<UserPlaylist> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('cover_asset')) {
      context.handle(
        _coverAssetMeta,
        coverAsset.isAcceptableOrUnknown(data['cover_asset']!, _coverAssetMeta),
      );
    }
    if (data.containsKey('cover_cloud_id')) {
      context.handle(
        _coverCloudIdMeta,
        coverCloudId.isAcceptableOrUnknown(
          data['cover_cloud_id']!,
          _coverCloudIdMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerId, id};
  @override
  UserPlaylist map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UserPlaylist(
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      coverAsset: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_asset'],
      ),
      coverCloudId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_cloud_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $UserPlaylistsTable createAlias(String alias) {
    return $UserPlaylistsTable(attachedDatabase, alias);
  }
}

class UserPlaylist extends DataClass implements Insertable<UserPlaylist> {
  final String ownerId;
  final String id;
  final String name;
  final String description;
  final String? coverAsset;
  final String? coverCloudId;
  final DateTime createdAt;
  final DateTime updatedAt;
  const UserPlaylist({
    required this.ownerId,
    required this.id,
    required this.name,
    required this.description,
    this.coverAsset,
    this.coverCloudId,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_id'] = Variable<String>(ownerId);
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['description'] = Variable<String>(description);
    if (!nullToAbsent || coverAsset != null) {
      map['cover_asset'] = Variable<String>(coverAsset);
    }
    if (!nullToAbsent || coverCloudId != null) {
      map['cover_cloud_id'] = Variable<String>(coverCloudId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  UserPlaylistsCompanion toCompanion(bool nullToAbsent) {
    return UserPlaylistsCompanion(
      ownerId: Value(ownerId),
      id: Value(id),
      name: Value(name),
      description: Value(description),
      coverAsset: coverAsset == null && nullToAbsent
          ? const Value.absent()
          : Value(coverAsset),
      coverCloudId: coverCloudId == null && nullToAbsent
          ? const Value.absent()
          : Value(coverCloudId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory UserPlaylist.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UserPlaylist(
      ownerId: serializer.fromJson<String>(json['ownerId']),
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String>(json['description']),
      coverAsset: serializer.fromJson<String?>(json['coverAsset']),
      coverCloudId: serializer.fromJson<String?>(json['coverCloudId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerId': serializer.toJson<String>(ownerId),
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String>(description),
      'coverAsset': serializer.toJson<String?>(coverAsset),
      'coverCloudId': serializer.toJson<String?>(coverCloudId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  UserPlaylist copyWith({
    String? ownerId,
    String? id,
    String? name,
    String? description,
    Value<String?> coverAsset = const Value.absent(),
    Value<String?> coverCloudId = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => UserPlaylist(
    ownerId: ownerId ?? this.ownerId,
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    coverAsset: coverAsset.present ? coverAsset.value : this.coverAsset,
    coverCloudId: coverCloudId.present ? coverCloudId.value : this.coverCloudId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  UserPlaylist copyWithCompanion(UserPlaylistsCompanion data) {
    return UserPlaylist(
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      coverAsset: data.coverAsset.present
          ? data.coverAsset.value
          : this.coverAsset,
      coverCloudId: data.coverCloudId.present
          ? data.coverCloudId.value
          : this.coverCloudId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UserPlaylist(')
          ..write('ownerId: $ownerId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('coverAsset: $coverAsset, ')
          ..write('coverCloudId: $coverCloudId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerId,
    id,
    name,
    description,
    coverAsset,
    coverCloudId,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserPlaylist &&
          other.ownerId == this.ownerId &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.coverAsset == this.coverAsset &&
          other.coverCloudId == this.coverCloudId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class UserPlaylistsCompanion extends UpdateCompanion<UserPlaylist> {
  final Value<String> ownerId;
  final Value<String> id;
  final Value<String> name;
  final Value<String> description;
  final Value<String?> coverAsset;
  final Value<String?> coverCloudId;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const UserPlaylistsCompanion({
    this.ownerId = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.coverAsset = const Value.absent(),
    this.coverCloudId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UserPlaylistsCompanion.insert({
    this.ownerId = const Value.absent(),
    required String id,
    required String name,
    this.description = const Value.absent(),
    this.coverAsset = const Value.absent(),
    this.coverCloudId = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<UserPlaylist> custom({
    Expression<String>? ownerId,
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? coverAsset,
    Expression<String>? coverCloudId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerId != null) 'owner_id': ownerId,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (coverAsset != null) 'cover_asset': coverAsset,
      if (coverCloudId != null) 'cover_cloud_id': coverCloudId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UserPlaylistsCompanion copyWith({
    Value<String>? ownerId,
    Value<String>? id,
    Value<String>? name,
    Value<String>? description,
    Value<String?>? coverAsset,
    Value<String?>? coverCloudId,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return UserPlaylistsCompanion(
      ownerId: ownerId ?? this.ownerId,
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      coverAsset: coverAsset ?? this.coverAsset,
      coverCloudId: coverCloudId ?? this.coverCloudId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (coverAsset.present) {
      map['cover_asset'] = Variable<String>(coverAsset.value);
    }
    if (coverCloudId.present) {
      map['cover_cloud_id'] = Variable<String>(coverCloudId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UserPlaylistsCompanion(')
          ..write('ownerId: $ownerId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('coverAsset: $coverAsset, ')
          ..write('coverCloudId: $coverCloudId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UserPlaylistTracksTable extends UserPlaylistTracks
    with TableInfo<$UserPlaylistTracksTable, UserPlaylistTrack> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserPlaylistTracksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(legacyLibraryOwnerId),
  );
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<String> playlistId = GeneratedColumn<String>(
    'playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _trackIdMeta = const VerificationMeta(
    'trackId',
  );
  @override
  late final GeneratedColumn<String> trackId = GeneratedColumn<String>(
    'track_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _trackSnapshotMeta = const VerificationMeta(
    'trackSnapshot',
  );
  @override
  late final GeneratedColumn<String> trackSnapshot = GeneratedColumn<String>(
    'track_snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerId,
    playlistId,
    trackId,
    trackSnapshot,
    sortOrder,
    addedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'user_playlist_tracks';
  @override
  VerificationContext validateIntegrity(
    Insertable<UserPlaylistTrack> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    }
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    if (data.containsKey('track_id')) {
      context.handle(
        _trackIdMeta,
        trackId.isAcceptableOrUnknown(data['track_id']!, _trackIdMeta),
      );
    } else if (isInserting) {
      context.missing(_trackIdMeta);
    }
    if (data.containsKey('track_snapshot')) {
      context.handle(
        _trackSnapshotMeta,
        trackSnapshot.isAcceptableOrUnknown(
          data['track_snapshot']!,
          _trackSnapshotMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_trackSnapshotMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerId, playlistId, trackId};
  @override
  UserPlaylistTrack map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UserPlaylistTrack(
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}playlist_id'],
      )!,
      trackId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_id'],
      )!,
      trackSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_snapshot'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $UserPlaylistTracksTable createAlias(String alias) {
    return $UserPlaylistTracksTable(attachedDatabase, alias);
  }
}

class UserPlaylistTrack extends DataClass
    implements Insertable<UserPlaylistTrack> {
  final String ownerId;
  final String playlistId;
  final String trackId;
  final String trackSnapshot;
  final int sortOrder;
  final DateTime addedAt;
  const UserPlaylistTrack({
    required this.ownerId,
    required this.playlistId,
    required this.trackId,
    required this.trackSnapshot,
    required this.sortOrder,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_id'] = Variable<String>(ownerId);
    map['playlist_id'] = Variable<String>(playlistId);
    map['track_id'] = Variable<String>(trackId);
    map['track_snapshot'] = Variable<String>(trackSnapshot);
    map['sort_order'] = Variable<int>(sortOrder);
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  UserPlaylistTracksCompanion toCompanion(bool nullToAbsent) {
    return UserPlaylistTracksCompanion(
      ownerId: Value(ownerId),
      playlistId: Value(playlistId),
      trackId: Value(trackId),
      trackSnapshot: Value(trackSnapshot),
      sortOrder: Value(sortOrder),
      addedAt: Value(addedAt),
    );
  }

  factory UserPlaylistTrack.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UserPlaylistTrack(
      ownerId: serializer.fromJson<String>(json['ownerId']),
      playlistId: serializer.fromJson<String>(json['playlistId']),
      trackId: serializer.fromJson<String>(json['trackId']),
      trackSnapshot: serializer.fromJson<String>(json['trackSnapshot']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerId': serializer.toJson<String>(ownerId),
      'playlistId': serializer.toJson<String>(playlistId),
      'trackId': serializer.toJson<String>(trackId),
      'trackSnapshot': serializer.toJson<String>(trackSnapshot),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  UserPlaylistTrack copyWith({
    String? ownerId,
    String? playlistId,
    String? trackId,
    String? trackSnapshot,
    int? sortOrder,
    DateTime? addedAt,
  }) => UserPlaylistTrack(
    ownerId: ownerId ?? this.ownerId,
    playlistId: playlistId ?? this.playlistId,
    trackId: trackId ?? this.trackId,
    trackSnapshot: trackSnapshot ?? this.trackSnapshot,
    sortOrder: sortOrder ?? this.sortOrder,
    addedAt: addedAt ?? this.addedAt,
  );
  UserPlaylistTrack copyWithCompanion(UserPlaylistTracksCompanion data) {
    return UserPlaylistTrack(
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
      trackId: data.trackId.present ? data.trackId.value : this.trackId,
      trackSnapshot: data.trackSnapshot.present
          ? data.trackSnapshot.value
          : this.trackSnapshot,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UserPlaylistTrack(')
          ..write('ownerId: $ownerId, ')
          ..write('playlistId: $playlistId, ')
          ..write('trackId: $trackId, ')
          ..write('trackSnapshot: $trackSnapshot, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerId,
    playlistId,
    trackId,
    trackSnapshot,
    sortOrder,
    addedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserPlaylistTrack &&
          other.ownerId == this.ownerId &&
          other.playlistId == this.playlistId &&
          other.trackId == this.trackId &&
          other.trackSnapshot == this.trackSnapshot &&
          other.sortOrder == this.sortOrder &&
          other.addedAt == this.addedAt);
}

class UserPlaylistTracksCompanion extends UpdateCompanion<UserPlaylistTrack> {
  final Value<String> ownerId;
  final Value<String> playlistId;
  final Value<String> trackId;
  final Value<String> trackSnapshot;
  final Value<int> sortOrder;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const UserPlaylistTracksCompanion({
    this.ownerId = const Value.absent(),
    this.playlistId = const Value.absent(),
    this.trackId = const Value.absent(),
    this.trackSnapshot = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UserPlaylistTracksCompanion.insert({
    this.ownerId = const Value.absent(),
    required String playlistId,
    required String trackId,
    required String trackSnapshot,
    required int sortOrder,
    required DateTime addedAt,
    this.rowid = const Value.absent(),
  }) : playlistId = Value(playlistId),
       trackId = Value(trackId),
       trackSnapshot = Value(trackSnapshot),
       sortOrder = Value(sortOrder),
       addedAt = Value(addedAt);
  static Insertable<UserPlaylistTrack> custom({
    Expression<String>? ownerId,
    Expression<String>? playlistId,
    Expression<String>? trackId,
    Expression<String>? trackSnapshot,
    Expression<int>? sortOrder,
    Expression<DateTime>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerId != null) 'owner_id': ownerId,
      if (playlistId != null) 'playlist_id': playlistId,
      if (trackId != null) 'track_id': trackId,
      if (trackSnapshot != null) 'track_snapshot': trackSnapshot,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UserPlaylistTracksCompanion copyWith({
    Value<String>? ownerId,
    Value<String>? playlistId,
    Value<String>? trackId,
    Value<String>? trackSnapshot,
    Value<int>? sortOrder,
    Value<DateTime>? addedAt,
    Value<int>? rowid,
  }) {
    return UserPlaylistTracksCompanion(
      ownerId: ownerId ?? this.ownerId,
      playlistId: playlistId ?? this.playlistId,
      trackId: trackId ?? this.trackId,
      trackSnapshot: trackSnapshot ?? this.trackSnapshot,
      sortOrder: sortOrder ?? this.sortOrder,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (playlistId.present) {
      map['playlist_id'] = Variable<String>(playlistId.value);
    }
    if (trackId.present) {
      map['track_id'] = Variable<String>(trackId.value);
    }
    if (trackSnapshot.present) {
      map['track_snapshot'] = Variable<String>(trackSnapshot.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UserPlaylistTracksCompanion(')
          ..write('ownerId: $ownerId, ')
          ..write('playlistId: $playlistId, ')
          ..write('trackId: $trackId, ')
          ..write('trackSnapshot: $trackSnapshot, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncMutationsTable extends SyncMutations
    with TableInfo<$SyncMutationsTable, SyncMutation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncMutationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationMeta = const VerificationMeta(
    'operation',
  );
  @override
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
    'operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerId,
    entityType,
    entityId,
    operation,
    payload,
    attemptCount,
    lastError,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_mutations';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncMutation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(
        _operationMeta,
        operation.isAcceptableOrUnknown(data['operation']!, _operationMeta),
      );
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncMutation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncMutation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      operation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SyncMutationsTable createAlias(String alias) {
    return $SyncMutationsTable(attachedDatabase, alias);
  }
}

class SyncMutation extends DataClass implements Insertable<SyncMutation> {
  final int id;
  final String ownerId;
  final String entityType;
  final String entityId;
  final String operation;
  final String payload;
  final int attemptCount;
  final String? lastError;
  final DateTime createdAt;
  const SyncMutation({
    required this.id,
    required this.ownerId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.attemptCount,
    this.lastError,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['owner_id'] = Variable<String>(ownerId);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['operation'] = Variable<String>(operation);
    map['payload'] = Variable<String>(payload);
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SyncMutationsCompanion toCompanion(bool nullToAbsent) {
    return SyncMutationsCompanion(
      id: Value(id),
      ownerId: Value(ownerId),
      entityType: Value(entityType),
      entityId: Value(entityId),
      operation: Value(operation),
      payload: Value(payload),
      attemptCount: Value(attemptCount),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      createdAt: Value(createdAt),
    );
  }

  factory SyncMutation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncMutation(
      id: serializer.fromJson<int>(json['id']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      operation: serializer.fromJson<String>(json['operation']),
      payload: serializer.fromJson<String>(json['payload']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'ownerId': serializer.toJson<String>(ownerId),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'operation': serializer.toJson<String>(operation),
      'payload': serializer.toJson<String>(payload),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'lastError': serializer.toJson<String?>(lastError),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SyncMutation copyWith({
    int? id,
    String? ownerId,
    String? entityType,
    String? entityId,
    String? operation,
    String? payload,
    int? attemptCount,
    Value<String?> lastError = const Value.absent(),
    DateTime? createdAt,
  }) => SyncMutation(
    id: id ?? this.id,
    ownerId: ownerId ?? this.ownerId,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    operation: operation ?? this.operation,
    payload: payload ?? this.payload,
    attemptCount: attemptCount ?? this.attemptCount,
    lastError: lastError.present ? lastError.value : this.lastError,
    createdAt: createdAt ?? this.createdAt,
  );
  SyncMutation copyWithCompanion(SyncMutationsCompanion data) {
    return SyncMutation(
      id: data.id.present ? data.id.value : this.id,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      operation: data.operation.present ? data.operation.value : this.operation,
      payload: data.payload.present ? data.payload.value : this.payload,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncMutation(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('payload: $payload, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    entityType,
    entityId,
    operation,
    payload,
    attemptCount,
    lastError,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncMutation &&
          other.id == this.id &&
          other.ownerId == this.ownerId &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.operation == this.operation &&
          other.payload == this.payload &&
          other.attemptCount == this.attemptCount &&
          other.lastError == this.lastError &&
          other.createdAt == this.createdAt);
}

class SyncMutationsCompanion extends UpdateCompanion<SyncMutation> {
  final Value<int> id;
  final Value<String> ownerId;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> operation;
  final Value<String> payload;
  final Value<int> attemptCount;
  final Value<String?> lastError;
  final Value<DateTime> createdAt;
  const SyncMutationsCompanion({
    this.id = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.operation = const Value.absent(),
    this.payload = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  SyncMutationsCompanion.insert({
    this.id = const Value.absent(),
    required String ownerId,
    required String entityType,
    required String entityId,
    required String operation,
    this.payload = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.lastError = const Value.absent(),
    required DateTime createdAt,
  }) : ownerId = Value(ownerId),
       entityType = Value(entityType),
       entityId = Value(entityId),
       operation = Value(operation),
       createdAt = Value(createdAt);
  static Insertable<SyncMutation> custom({
    Expression<int>? id,
    Expression<String>? ownerId,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? operation,
    Expression<String>? payload,
    Expression<int>? attemptCount,
    Expression<String>? lastError,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerId != null) 'owner_id': ownerId,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (operation != null) 'operation': operation,
      if (payload != null) 'payload': payload,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (lastError != null) 'last_error': lastError,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  SyncMutationsCompanion copyWith({
    Value<int>? id,
    Value<String>? ownerId,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? operation,
    Value<String>? payload,
    Value<int>? attemptCount,
    Value<String?>? lastError,
    Value<DateTime>? createdAt,
  }) {
    return SyncMutationsCompanion(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      operation: operation ?? this.operation,
      payload: payload ?? this.payload,
      attemptCount: attemptCount ?? this.attemptCount,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncMutationsCompanion(')
          ..write('id: $id, ')
          ..write('ownerId: $ownerId, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('payload: $payload, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $PlaybackSessionsTable extends PlaybackSessions
    with TableInfo<$PlaybackSessionsTable, PlaybackSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaybackSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(legacyLibraryOwnerId),
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _queueSnapshotMeta = const VerificationMeta(
    'queueSnapshot',
  );
  @override
  late final GeneratedColumn<String> queueSnapshot = GeneratedColumn<String>(
    'queue_snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currentIndexMeta = const VerificationMeta(
    'currentIndex',
  );
  @override
  late final GeneratedColumn<int> currentIndex = GeneratedColumn<int>(
    'current_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMsMeta = const VerificationMeta(
    'positionMs',
  );
  @override
  late final GeneratedColumn<int> positionMs = GeneratedColumn<int>(
    'position_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _playbackModeMeta = const VerificationMeta(
    'playbackMode',
  );
  @override
  late final GeneratedColumn<String> playbackMode = GeneratedColumn<String>(
    'playback_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerId,
    id,
    queueSnapshot,
    currentIndex,
    positionMs,
    playbackMode,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playback_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaybackSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('queue_snapshot')) {
      context.handle(
        _queueSnapshotMeta,
        queueSnapshot.isAcceptableOrUnknown(
          data['queue_snapshot']!,
          _queueSnapshotMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_queueSnapshotMeta);
    }
    if (data.containsKey('current_index')) {
      context.handle(
        _currentIndexMeta,
        currentIndex.isAcceptableOrUnknown(
          data['current_index']!,
          _currentIndexMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentIndexMeta);
    }
    if (data.containsKey('position_ms')) {
      context.handle(
        _positionMsMeta,
        positionMs.isAcceptableOrUnknown(data['position_ms']!, _positionMsMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMsMeta);
    }
    if (data.containsKey('playback_mode')) {
      context.handle(
        _playbackModeMeta,
        playbackMode.isAcceptableOrUnknown(
          data['playback_mode']!,
          _playbackModeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_playbackModeMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerId, id};
  @override
  PlaybackSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaybackSession(
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      queueSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}queue_snapshot'],
      )!,
      currentIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}current_index'],
      )!,
      positionMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position_ms'],
      )!,
      playbackMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}playback_mode'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PlaybackSessionsTable createAlias(String alias) {
    return $PlaybackSessionsTable(attachedDatabase, alias);
  }
}

class PlaybackSession extends DataClass implements Insertable<PlaybackSession> {
  final String ownerId;
  final int id;
  final String queueSnapshot;
  final int currentIndex;
  final int positionMs;
  final String playbackMode;
  final DateTime updatedAt;
  const PlaybackSession({
    required this.ownerId,
    required this.id,
    required this.queueSnapshot,
    required this.currentIndex,
    required this.positionMs,
    required this.playbackMode,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_id'] = Variable<String>(ownerId);
    map['id'] = Variable<int>(id);
    map['queue_snapshot'] = Variable<String>(queueSnapshot);
    map['current_index'] = Variable<int>(currentIndex);
    map['position_ms'] = Variable<int>(positionMs);
    map['playback_mode'] = Variable<String>(playbackMode);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  PlaybackSessionsCompanion toCompanion(bool nullToAbsent) {
    return PlaybackSessionsCompanion(
      ownerId: Value(ownerId),
      id: Value(id),
      queueSnapshot: Value(queueSnapshot),
      currentIndex: Value(currentIndex),
      positionMs: Value(positionMs),
      playbackMode: Value(playbackMode),
      updatedAt: Value(updatedAt),
    );
  }

  factory PlaybackSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaybackSession(
      ownerId: serializer.fromJson<String>(json['ownerId']),
      id: serializer.fromJson<int>(json['id']),
      queueSnapshot: serializer.fromJson<String>(json['queueSnapshot']),
      currentIndex: serializer.fromJson<int>(json['currentIndex']),
      positionMs: serializer.fromJson<int>(json['positionMs']),
      playbackMode: serializer.fromJson<String>(json['playbackMode']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerId': serializer.toJson<String>(ownerId),
      'id': serializer.toJson<int>(id),
      'queueSnapshot': serializer.toJson<String>(queueSnapshot),
      'currentIndex': serializer.toJson<int>(currentIndex),
      'positionMs': serializer.toJson<int>(positionMs),
      'playbackMode': serializer.toJson<String>(playbackMode),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  PlaybackSession copyWith({
    String? ownerId,
    int? id,
    String? queueSnapshot,
    int? currentIndex,
    int? positionMs,
    String? playbackMode,
    DateTime? updatedAt,
  }) => PlaybackSession(
    ownerId: ownerId ?? this.ownerId,
    id: id ?? this.id,
    queueSnapshot: queueSnapshot ?? this.queueSnapshot,
    currentIndex: currentIndex ?? this.currentIndex,
    positionMs: positionMs ?? this.positionMs,
    playbackMode: playbackMode ?? this.playbackMode,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  PlaybackSession copyWithCompanion(PlaybackSessionsCompanion data) {
    return PlaybackSession(
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      id: data.id.present ? data.id.value : this.id,
      queueSnapshot: data.queueSnapshot.present
          ? data.queueSnapshot.value
          : this.queueSnapshot,
      currentIndex: data.currentIndex.present
          ? data.currentIndex.value
          : this.currentIndex,
      positionMs: data.positionMs.present
          ? data.positionMs.value
          : this.positionMs,
      playbackMode: data.playbackMode.present
          ? data.playbackMode.value
          : this.playbackMode,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaybackSession(')
          ..write('ownerId: $ownerId, ')
          ..write('id: $id, ')
          ..write('queueSnapshot: $queueSnapshot, ')
          ..write('currentIndex: $currentIndex, ')
          ..write('positionMs: $positionMs, ')
          ..write('playbackMode: $playbackMode, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerId,
    id,
    queueSnapshot,
    currentIndex,
    positionMs,
    playbackMode,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaybackSession &&
          other.ownerId == this.ownerId &&
          other.id == this.id &&
          other.queueSnapshot == this.queueSnapshot &&
          other.currentIndex == this.currentIndex &&
          other.positionMs == this.positionMs &&
          other.playbackMode == this.playbackMode &&
          other.updatedAt == this.updatedAt);
}

class PlaybackSessionsCompanion extends UpdateCompanion<PlaybackSession> {
  final Value<String> ownerId;
  final Value<int> id;
  final Value<String> queueSnapshot;
  final Value<int> currentIndex;
  final Value<int> positionMs;
  final Value<String> playbackMode;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const PlaybackSessionsCompanion({
    this.ownerId = const Value.absent(),
    this.id = const Value.absent(),
    this.queueSnapshot = const Value.absent(),
    this.currentIndex = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.playbackMode = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaybackSessionsCompanion.insert({
    this.ownerId = const Value.absent(),
    required int id,
    required String queueSnapshot,
    required int currentIndex,
    required int positionMs,
    required String playbackMode,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       queueSnapshot = Value(queueSnapshot),
       currentIndex = Value(currentIndex),
       positionMs = Value(positionMs),
       playbackMode = Value(playbackMode),
       updatedAt = Value(updatedAt);
  static Insertable<PlaybackSession> custom({
    Expression<String>? ownerId,
    Expression<int>? id,
    Expression<String>? queueSnapshot,
    Expression<int>? currentIndex,
    Expression<int>? positionMs,
    Expression<String>? playbackMode,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerId != null) 'owner_id': ownerId,
      if (id != null) 'id': id,
      if (queueSnapshot != null) 'queue_snapshot': queueSnapshot,
      if (currentIndex != null) 'current_index': currentIndex,
      if (positionMs != null) 'position_ms': positionMs,
      if (playbackMode != null) 'playback_mode': playbackMode,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaybackSessionsCompanion copyWith({
    Value<String>? ownerId,
    Value<int>? id,
    Value<String>? queueSnapshot,
    Value<int>? currentIndex,
    Value<int>? positionMs,
    Value<String>? playbackMode,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return PlaybackSessionsCompanion(
      ownerId: ownerId ?? this.ownerId,
      id: id ?? this.id,
      queueSnapshot: queueSnapshot ?? this.queueSnapshot,
      currentIndex: currentIndex ?? this.currentIndex,
      positionMs: positionMs ?? this.positionMs,
      playbackMode: playbackMode ?? this.playbackMode,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (queueSnapshot.present) {
      map['queue_snapshot'] = Variable<String>(queueSnapshot.value);
    }
    if (currentIndex.present) {
      map['current_index'] = Variable<int>(currentIndex.value);
    }
    if (positionMs.present) {
      map['position_ms'] = Variable<int>(positionMs.value);
    }
    if (playbackMode.present) {
      map['playback_mode'] = Variable<String>(playbackMode.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaybackSessionsCompanion(')
          ..write('ownerId: $ownerId, ')
          ..write('id: $id, ')
          ..write('queueSnapshot: $queueSnapshot, ')
          ..write('currentIndex: $currentIndex, ')
          ..write('positionMs: $positionMs, ')
          ..write('playbackMode: $playbackMode, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlaybackHistoriesTable extends PlaybackHistories
    with TableInfo<$PlaybackHistoriesTable, PlaybackHistory> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaybackHistoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(legacyLibraryOwnerId),
  );
  static const VerificationMeta _trackIdMeta = const VerificationMeta(
    'trackId',
  );
  @override
  late final GeneratedColumn<String> trackId = GeneratedColumn<String>(
    'track_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _trackSnapshotMeta = const VerificationMeta(
    'trackSnapshot',
  );
  @override
  late final GeneratedColumn<String> trackSnapshot = GeneratedColumn<String>(
    'track_snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _playCountMeta = const VerificationMeta(
    'playCount',
  );
  @override
  late final GeneratedColumn<int> playCount = GeneratedColumn<int>(
    'play_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _completedPlayCountMeta =
      const VerificationMeta('completedPlayCount');
  @override
  late final GeneratedColumn<int> completedPlayCount = GeneratedColumn<int>(
    'completed_play_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _totalPlayedMsMeta = const VerificationMeta(
    'totalPlayedMs',
  );
  @override
  late final GeneratedColumn<int> totalPlayedMs = GeneratedColumn<int>(
    'total_played_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastPlayedAtMeta = const VerificationMeta(
    'lastPlayedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastPlayedAt = GeneratedColumn<DateTime>(
    'last_played_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerId,
    trackId,
    trackSnapshot,
    playCount,
    completedPlayCount,
    totalPlayedMs,
    lastPlayedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playback_histories';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaybackHistory> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    }
    if (data.containsKey('track_id')) {
      context.handle(
        _trackIdMeta,
        trackId.isAcceptableOrUnknown(data['track_id']!, _trackIdMeta),
      );
    } else if (isInserting) {
      context.missing(_trackIdMeta);
    }
    if (data.containsKey('track_snapshot')) {
      context.handle(
        _trackSnapshotMeta,
        trackSnapshot.isAcceptableOrUnknown(
          data['track_snapshot']!,
          _trackSnapshotMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_trackSnapshotMeta);
    }
    if (data.containsKey('play_count')) {
      context.handle(
        _playCountMeta,
        playCount.isAcceptableOrUnknown(data['play_count']!, _playCountMeta),
      );
    }
    if (data.containsKey('completed_play_count')) {
      context.handle(
        _completedPlayCountMeta,
        completedPlayCount.isAcceptableOrUnknown(
          data['completed_play_count']!,
          _completedPlayCountMeta,
        ),
      );
    }
    if (data.containsKey('total_played_ms')) {
      context.handle(
        _totalPlayedMsMeta,
        totalPlayedMs.isAcceptableOrUnknown(
          data['total_played_ms']!,
          _totalPlayedMsMeta,
        ),
      );
    }
    if (data.containsKey('last_played_at')) {
      context.handle(
        _lastPlayedAtMeta,
        lastPlayedAt.isAcceptableOrUnknown(
          data['last_played_at']!,
          _lastPlayedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastPlayedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerId, trackId};
  @override
  PlaybackHistory map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaybackHistory(
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      trackId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_id'],
      )!,
      trackSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_snapshot'],
      )!,
      playCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}play_count'],
      )!,
      completedPlayCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed_play_count'],
      )!,
      totalPlayedMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_played_ms'],
      )!,
      lastPlayedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_played_at'],
      )!,
    );
  }

  @override
  $PlaybackHistoriesTable createAlias(String alias) {
    return $PlaybackHistoriesTable(attachedDatabase, alias);
  }
}

class PlaybackHistory extends DataClass implements Insertable<PlaybackHistory> {
  final String ownerId;
  final String trackId;
  final String trackSnapshot;
  final int playCount;
  final int completedPlayCount;
  final int totalPlayedMs;
  final DateTime lastPlayedAt;
  const PlaybackHistory({
    required this.ownerId,
    required this.trackId,
    required this.trackSnapshot,
    required this.playCount,
    required this.completedPlayCount,
    required this.totalPlayedMs,
    required this.lastPlayedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_id'] = Variable<String>(ownerId);
    map['track_id'] = Variable<String>(trackId);
    map['track_snapshot'] = Variable<String>(trackSnapshot);
    map['play_count'] = Variable<int>(playCount);
    map['completed_play_count'] = Variable<int>(completedPlayCount);
    map['total_played_ms'] = Variable<int>(totalPlayedMs);
    map['last_played_at'] = Variable<DateTime>(lastPlayedAt);
    return map;
  }

  PlaybackHistoriesCompanion toCompanion(bool nullToAbsent) {
    return PlaybackHistoriesCompanion(
      ownerId: Value(ownerId),
      trackId: Value(trackId),
      trackSnapshot: Value(trackSnapshot),
      playCount: Value(playCount),
      completedPlayCount: Value(completedPlayCount),
      totalPlayedMs: Value(totalPlayedMs),
      lastPlayedAt: Value(lastPlayedAt),
    );
  }

  factory PlaybackHistory.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaybackHistory(
      ownerId: serializer.fromJson<String>(json['ownerId']),
      trackId: serializer.fromJson<String>(json['trackId']),
      trackSnapshot: serializer.fromJson<String>(json['trackSnapshot']),
      playCount: serializer.fromJson<int>(json['playCount']),
      completedPlayCount: serializer.fromJson<int>(json['completedPlayCount']),
      totalPlayedMs: serializer.fromJson<int>(json['totalPlayedMs']),
      lastPlayedAt: serializer.fromJson<DateTime>(json['lastPlayedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerId': serializer.toJson<String>(ownerId),
      'trackId': serializer.toJson<String>(trackId),
      'trackSnapshot': serializer.toJson<String>(trackSnapshot),
      'playCount': serializer.toJson<int>(playCount),
      'completedPlayCount': serializer.toJson<int>(completedPlayCount),
      'totalPlayedMs': serializer.toJson<int>(totalPlayedMs),
      'lastPlayedAt': serializer.toJson<DateTime>(lastPlayedAt),
    };
  }

  PlaybackHistory copyWith({
    String? ownerId,
    String? trackId,
    String? trackSnapshot,
    int? playCount,
    int? completedPlayCount,
    int? totalPlayedMs,
    DateTime? lastPlayedAt,
  }) => PlaybackHistory(
    ownerId: ownerId ?? this.ownerId,
    trackId: trackId ?? this.trackId,
    trackSnapshot: trackSnapshot ?? this.trackSnapshot,
    playCount: playCount ?? this.playCount,
    completedPlayCount: completedPlayCount ?? this.completedPlayCount,
    totalPlayedMs: totalPlayedMs ?? this.totalPlayedMs,
    lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
  );
  PlaybackHistory copyWithCompanion(PlaybackHistoriesCompanion data) {
    return PlaybackHistory(
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      trackId: data.trackId.present ? data.trackId.value : this.trackId,
      trackSnapshot: data.trackSnapshot.present
          ? data.trackSnapshot.value
          : this.trackSnapshot,
      playCount: data.playCount.present ? data.playCount.value : this.playCount,
      completedPlayCount: data.completedPlayCount.present
          ? data.completedPlayCount.value
          : this.completedPlayCount,
      totalPlayedMs: data.totalPlayedMs.present
          ? data.totalPlayedMs.value
          : this.totalPlayedMs,
      lastPlayedAt: data.lastPlayedAt.present
          ? data.lastPlayedAt.value
          : this.lastPlayedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaybackHistory(')
          ..write('ownerId: $ownerId, ')
          ..write('trackId: $trackId, ')
          ..write('trackSnapshot: $trackSnapshot, ')
          ..write('playCount: $playCount, ')
          ..write('completedPlayCount: $completedPlayCount, ')
          ..write('totalPlayedMs: $totalPlayedMs, ')
          ..write('lastPlayedAt: $lastPlayedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerId,
    trackId,
    trackSnapshot,
    playCount,
    completedPlayCount,
    totalPlayedMs,
    lastPlayedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaybackHistory &&
          other.ownerId == this.ownerId &&
          other.trackId == this.trackId &&
          other.trackSnapshot == this.trackSnapshot &&
          other.playCount == this.playCount &&
          other.completedPlayCount == this.completedPlayCount &&
          other.totalPlayedMs == this.totalPlayedMs &&
          other.lastPlayedAt == this.lastPlayedAt);
}

class PlaybackHistoriesCompanion extends UpdateCompanion<PlaybackHistory> {
  final Value<String> ownerId;
  final Value<String> trackId;
  final Value<String> trackSnapshot;
  final Value<int> playCount;
  final Value<int> completedPlayCount;
  final Value<int> totalPlayedMs;
  final Value<DateTime> lastPlayedAt;
  final Value<int> rowid;
  const PlaybackHistoriesCompanion({
    this.ownerId = const Value.absent(),
    this.trackId = const Value.absent(),
    this.trackSnapshot = const Value.absent(),
    this.playCount = const Value.absent(),
    this.completedPlayCount = const Value.absent(),
    this.totalPlayedMs = const Value.absent(),
    this.lastPlayedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaybackHistoriesCompanion.insert({
    this.ownerId = const Value.absent(),
    required String trackId,
    required String trackSnapshot,
    this.playCount = const Value.absent(),
    this.completedPlayCount = const Value.absent(),
    this.totalPlayedMs = const Value.absent(),
    required DateTime lastPlayedAt,
    this.rowid = const Value.absent(),
  }) : trackId = Value(trackId),
       trackSnapshot = Value(trackSnapshot),
       lastPlayedAt = Value(lastPlayedAt);
  static Insertable<PlaybackHistory> custom({
    Expression<String>? ownerId,
    Expression<String>? trackId,
    Expression<String>? trackSnapshot,
    Expression<int>? playCount,
    Expression<int>? completedPlayCount,
    Expression<int>? totalPlayedMs,
    Expression<DateTime>? lastPlayedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerId != null) 'owner_id': ownerId,
      if (trackId != null) 'track_id': trackId,
      if (trackSnapshot != null) 'track_snapshot': trackSnapshot,
      if (playCount != null) 'play_count': playCount,
      if (completedPlayCount != null)
        'completed_play_count': completedPlayCount,
      if (totalPlayedMs != null) 'total_played_ms': totalPlayedMs,
      if (lastPlayedAt != null) 'last_played_at': lastPlayedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaybackHistoriesCompanion copyWith({
    Value<String>? ownerId,
    Value<String>? trackId,
    Value<String>? trackSnapshot,
    Value<int>? playCount,
    Value<int>? completedPlayCount,
    Value<int>? totalPlayedMs,
    Value<DateTime>? lastPlayedAt,
    Value<int>? rowid,
  }) {
    return PlaybackHistoriesCompanion(
      ownerId: ownerId ?? this.ownerId,
      trackId: trackId ?? this.trackId,
      trackSnapshot: trackSnapshot ?? this.trackSnapshot,
      playCount: playCount ?? this.playCount,
      completedPlayCount: completedPlayCount ?? this.completedPlayCount,
      totalPlayedMs: totalPlayedMs ?? this.totalPlayedMs,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (trackId.present) {
      map['track_id'] = Variable<String>(trackId.value);
    }
    if (trackSnapshot.present) {
      map['track_snapshot'] = Variable<String>(trackSnapshot.value);
    }
    if (playCount.present) {
      map['play_count'] = Variable<int>(playCount.value);
    }
    if (completedPlayCount.present) {
      map['completed_play_count'] = Variable<int>(completedPlayCount.value);
    }
    if (totalPlayedMs.present) {
      map['total_played_ms'] = Variable<int>(totalPlayedMs.value);
    }
    if (lastPlayedAt.present) {
      map['last_played_at'] = Variable<DateTime>(lastPlayedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaybackHistoriesCompanion(')
          ..write('ownerId: $ownerId, ')
          ..write('trackId: $trackId, ')
          ..write('trackSnapshot: $trackSnapshot, ')
          ..write('playCount: $playCount, ')
          ..write('completedPlayCount: $completedPlayCount, ')
          ..write('totalPlayedMs: $totalPlayedMs, ')
          ..write('lastPlayedAt: $lastPlayedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlaybackDailyHistoriesTable extends PlaybackDailyHistories
    with TableInfo<$PlaybackDailyHistoriesTable, PlaybackDailyHistory> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaybackDailyHistoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(legacyLibraryOwnerId),
  );
  static const VerificationMeta _dayKeyMeta = const VerificationMeta('dayKey');
  @override
  late final GeneratedColumn<String> dayKey = GeneratedColumn<String>(
    'day_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _trackIdMeta = const VerificationMeta(
    'trackId',
  );
  @override
  late final GeneratedColumn<String> trackId = GeneratedColumn<String>(
    'track_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _trackSnapshotMeta = const VerificationMeta(
    'trackSnapshot',
  );
  @override
  late final GeneratedColumn<String> trackSnapshot = GeneratedColumn<String>(
    'track_snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _playCountMeta = const VerificationMeta(
    'playCount',
  );
  @override
  late final GeneratedColumn<int> playCount = GeneratedColumn<int>(
    'play_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _totalPlayedMsMeta = const VerificationMeta(
    'totalPlayedMs',
  );
  @override
  late final GeneratedColumn<int> totalPlayedMs = GeneratedColumn<int>(
    'total_played_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastPlayedAtMeta = const VerificationMeta(
    'lastPlayedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastPlayedAt = GeneratedColumn<DateTime>(
    'last_played_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerId,
    dayKey,
    trackId,
    trackSnapshot,
    playCount,
    totalPlayedMs,
    lastPlayedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playback_daily_histories';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaybackDailyHistory> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    }
    if (data.containsKey('day_key')) {
      context.handle(
        _dayKeyMeta,
        dayKey.isAcceptableOrUnknown(data['day_key']!, _dayKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_dayKeyMeta);
    }
    if (data.containsKey('track_id')) {
      context.handle(
        _trackIdMeta,
        trackId.isAcceptableOrUnknown(data['track_id']!, _trackIdMeta),
      );
    } else if (isInserting) {
      context.missing(_trackIdMeta);
    }
    if (data.containsKey('track_snapshot')) {
      context.handle(
        _trackSnapshotMeta,
        trackSnapshot.isAcceptableOrUnknown(
          data['track_snapshot']!,
          _trackSnapshotMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_trackSnapshotMeta);
    }
    if (data.containsKey('play_count')) {
      context.handle(
        _playCountMeta,
        playCount.isAcceptableOrUnknown(data['play_count']!, _playCountMeta),
      );
    }
    if (data.containsKey('total_played_ms')) {
      context.handle(
        _totalPlayedMsMeta,
        totalPlayedMs.isAcceptableOrUnknown(
          data['total_played_ms']!,
          _totalPlayedMsMeta,
        ),
      );
    }
    if (data.containsKey('last_played_at')) {
      context.handle(
        _lastPlayedAtMeta,
        lastPlayedAt.isAcceptableOrUnknown(
          data['last_played_at']!,
          _lastPlayedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastPlayedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerId, dayKey, trackId};
  @override
  PlaybackDailyHistory map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaybackDailyHistory(
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      dayKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}day_key'],
      )!,
      trackId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_id'],
      )!,
      trackSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_snapshot'],
      )!,
      playCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}play_count'],
      )!,
      totalPlayedMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_played_ms'],
      )!,
      lastPlayedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_played_at'],
      )!,
    );
  }

  @override
  $PlaybackDailyHistoriesTable createAlias(String alias) {
    return $PlaybackDailyHistoriesTable(attachedDatabase, alias);
  }
}

class PlaybackDailyHistory extends DataClass
    implements Insertable<PlaybackDailyHistory> {
  final String ownerId;
  final String dayKey;
  final String trackId;
  final String trackSnapshot;
  final int playCount;
  final int totalPlayedMs;
  final DateTime lastPlayedAt;
  const PlaybackDailyHistory({
    required this.ownerId,
    required this.dayKey,
    required this.trackId,
    required this.trackSnapshot,
    required this.playCount,
    required this.totalPlayedMs,
    required this.lastPlayedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_id'] = Variable<String>(ownerId);
    map['day_key'] = Variable<String>(dayKey);
    map['track_id'] = Variable<String>(trackId);
    map['track_snapshot'] = Variable<String>(trackSnapshot);
    map['play_count'] = Variable<int>(playCount);
    map['total_played_ms'] = Variable<int>(totalPlayedMs);
    map['last_played_at'] = Variable<DateTime>(lastPlayedAt);
    return map;
  }

  PlaybackDailyHistoriesCompanion toCompanion(bool nullToAbsent) {
    return PlaybackDailyHistoriesCompanion(
      ownerId: Value(ownerId),
      dayKey: Value(dayKey),
      trackId: Value(trackId),
      trackSnapshot: Value(trackSnapshot),
      playCount: Value(playCount),
      totalPlayedMs: Value(totalPlayedMs),
      lastPlayedAt: Value(lastPlayedAt),
    );
  }

  factory PlaybackDailyHistory.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaybackDailyHistory(
      ownerId: serializer.fromJson<String>(json['ownerId']),
      dayKey: serializer.fromJson<String>(json['dayKey']),
      trackId: serializer.fromJson<String>(json['trackId']),
      trackSnapshot: serializer.fromJson<String>(json['trackSnapshot']),
      playCount: serializer.fromJson<int>(json['playCount']),
      totalPlayedMs: serializer.fromJson<int>(json['totalPlayedMs']),
      lastPlayedAt: serializer.fromJson<DateTime>(json['lastPlayedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerId': serializer.toJson<String>(ownerId),
      'dayKey': serializer.toJson<String>(dayKey),
      'trackId': serializer.toJson<String>(trackId),
      'trackSnapshot': serializer.toJson<String>(trackSnapshot),
      'playCount': serializer.toJson<int>(playCount),
      'totalPlayedMs': serializer.toJson<int>(totalPlayedMs),
      'lastPlayedAt': serializer.toJson<DateTime>(lastPlayedAt),
    };
  }

  PlaybackDailyHistory copyWith({
    String? ownerId,
    String? dayKey,
    String? trackId,
    String? trackSnapshot,
    int? playCount,
    int? totalPlayedMs,
    DateTime? lastPlayedAt,
  }) => PlaybackDailyHistory(
    ownerId: ownerId ?? this.ownerId,
    dayKey: dayKey ?? this.dayKey,
    trackId: trackId ?? this.trackId,
    trackSnapshot: trackSnapshot ?? this.trackSnapshot,
    playCount: playCount ?? this.playCount,
    totalPlayedMs: totalPlayedMs ?? this.totalPlayedMs,
    lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
  );
  PlaybackDailyHistory copyWithCompanion(PlaybackDailyHistoriesCompanion data) {
    return PlaybackDailyHistory(
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      dayKey: data.dayKey.present ? data.dayKey.value : this.dayKey,
      trackId: data.trackId.present ? data.trackId.value : this.trackId,
      trackSnapshot: data.trackSnapshot.present
          ? data.trackSnapshot.value
          : this.trackSnapshot,
      playCount: data.playCount.present ? data.playCount.value : this.playCount,
      totalPlayedMs: data.totalPlayedMs.present
          ? data.totalPlayedMs.value
          : this.totalPlayedMs,
      lastPlayedAt: data.lastPlayedAt.present
          ? data.lastPlayedAt.value
          : this.lastPlayedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaybackDailyHistory(')
          ..write('ownerId: $ownerId, ')
          ..write('dayKey: $dayKey, ')
          ..write('trackId: $trackId, ')
          ..write('trackSnapshot: $trackSnapshot, ')
          ..write('playCount: $playCount, ')
          ..write('totalPlayedMs: $totalPlayedMs, ')
          ..write('lastPlayedAt: $lastPlayedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    ownerId,
    dayKey,
    trackId,
    trackSnapshot,
    playCount,
    totalPlayedMs,
    lastPlayedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaybackDailyHistory &&
          other.ownerId == this.ownerId &&
          other.dayKey == this.dayKey &&
          other.trackId == this.trackId &&
          other.trackSnapshot == this.trackSnapshot &&
          other.playCount == this.playCount &&
          other.totalPlayedMs == this.totalPlayedMs &&
          other.lastPlayedAt == this.lastPlayedAt);
}

class PlaybackDailyHistoriesCompanion
    extends UpdateCompanion<PlaybackDailyHistory> {
  final Value<String> ownerId;
  final Value<String> dayKey;
  final Value<String> trackId;
  final Value<String> trackSnapshot;
  final Value<int> playCount;
  final Value<int> totalPlayedMs;
  final Value<DateTime> lastPlayedAt;
  final Value<int> rowid;
  const PlaybackDailyHistoriesCompanion({
    this.ownerId = const Value.absent(),
    this.dayKey = const Value.absent(),
    this.trackId = const Value.absent(),
    this.trackSnapshot = const Value.absent(),
    this.playCount = const Value.absent(),
    this.totalPlayedMs = const Value.absent(),
    this.lastPlayedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaybackDailyHistoriesCompanion.insert({
    this.ownerId = const Value.absent(),
    required String dayKey,
    required String trackId,
    required String trackSnapshot,
    this.playCount = const Value.absent(),
    this.totalPlayedMs = const Value.absent(),
    required DateTime lastPlayedAt,
    this.rowid = const Value.absent(),
  }) : dayKey = Value(dayKey),
       trackId = Value(trackId),
       trackSnapshot = Value(trackSnapshot),
       lastPlayedAt = Value(lastPlayedAt);
  static Insertable<PlaybackDailyHistory> custom({
    Expression<String>? ownerId,
    Expression<String>? dayKey,
    Expression<String>? trackId,
    Expression<String>? trackSnapshot,
    Expression<int>? playCount,
    Expression<int>? totalPlayedMs,
    Expression<DateTime>? lastPlayedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerId != null) 'owner_id': ownerId,
      if (dayKey != null) 'day_key': dayKey,
      if (trackId != null) 'track_id': trackId,
      if (trackSnapshot != null) 'track_snapshot': trackSnapshot,
      if (playCount != null) 'play_count': playCount,
      if (totalPlayedMs != null) 'total_played_ms': totalPlayedMs,
      if (lastPlayedAt != null) 'last_played_at': lastPlayedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaybackDailyHistoriesCompanion copyWith({
    Value<String>? ownerId,
    Value<String>? dayKey,
    Value<String>? trackId,
    Value<String>? trackSnapshot,
    Value<int>? playCount,
    Value<int>? totalPlayedMs,
    Value<DateTime>? lastPlayedAt,
    Value<int>? rowid,
  }) {
    return PlaybackDailyHistoriesCompanion(
      ownerId: ownerId ?? this.ownerId,
      dayKey: dayKey ?? this.dayKey,
      trackId: trackId ?? this.trackId,
      trackSnapshot: trackSnapshot ?? this.trackSnapshot,
      playCount: playCount ?? this.playCount,
      totalPlayedMs: totalPlayedMs ?? this.totalPlayedMs,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (dayKey.present) {
      map['day_key'] = Variable<String>(dayKey.value);
    }
    if (trackId.present) {
      map['track_id'] = Variable<String>(trackId.value);
    }
    if (trackSnapshot.present) {
      map['track_snapshot'] = Variable<String>(trackSnapshot.value);
    }
    if (playCount.present) {
      map['play_count'] = Variable<int>(playCount.value);
    }
    if (totalPlayedMs.present) {
      map['total_played_ms'] = Variable<int>(totalPlayedMs.value);
    }
    if (lastPlayedAt.present) {
      map['last_played_at'] = Variable<DateTime>(lastPlayedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaybackDailyHistoriesCompanion(')
          ..write('ownerId: $ownerId, ')
          ..write('dayKey: $dayKey, ')
          ..write('trackId: $trackId, ')
          ..write('trackSnapshot: $trackSnapshot, ')
          ..write('playCount: $playCount, ')
          ..write('totalPlayedMs: $totalPlayedMs, ')
          ..write('lastPlayedAt: $lastPlayedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlatformListeningOutboxesTable extends PlatformListeningOutboxes
    with TableInfo<$PlatformListeningOutboxesTable, PlatformListeningOutbox> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlatformListeningOutboxesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('queued'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    ownerId,
    eventId,
    kind,
    payload,
    state,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'platform_listening_outboxes';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlatformListeningOutbox> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {ownerId, eventId};
  @override
  PlatformListeningOutbox map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlatformListeningOutbox(
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PlatformListeningOutboxesTable createAlias(String alias) {
    return $PlatformListeningOutboxesTable(attachedDatabase, alias);
  }
}

class PlatformListeningOutbox extends DataClass
    implements Insertable<PlatformListeningOutbox> {
  final String ownerId;
  final String eventId;
  final String kind;
  final String payload;
  final String state;
  final DateTime createdAt;
  final DateTime updatedAt;
  const PlatformListeningOutbox({
    required this.ownerId,
    required this.eventId,
    required this.kind,
    required this.payload,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner_id'] = Variable<String>(ownerId);
    map['event_id'] = Variable<String>(eventId);
    map['kind'] = Variable<String>(kind);
    map['payload'] = Variable<String>(payload);
    map['state'] = Variable<String>(state);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  PlatformListeningOutboxesCompanion toCompanion(bool nullToAbsent) {
    return PlatformListeningOutboxesCompanion(
      ownerId: Value(ownerId),
      eventId: Value(eventId),
      kind: Value(kind),
      payload: Value(payload),
      state: Value(state),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory PlatformListeningOutbox.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlatformListeningOutbox(
      ownerId: serializer.fromJson<String>(json['ownerId']),
      eventId: serializer.fromJson<String>(json['eventId']),
      kind: serializer.fromJson<String>(json['kind']),
      payload: serializer.fromJson<String>(json['payload']),
      state: serializer.fromJson<String>(json['state']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'ownerId': serializer.toJson<String>(ownerId),
      'eventId': serializer.toJson<String>(eventId),
      'kind': serializer.toJson<String>(kind),
      'payload': serializer.toJson<String>(payload),
      'state': serializer.toJson<String>(state),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  PlatformListeningOutbox copyWith({
    String? ownerId,
    String? eventId,
    String? kind,
    String? payload,
    String? state,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => PlatformListeningOutbox(
    ownerId: ownerId ?? this.ownerId,
    eventId: eventId ?? this.eventId,
    kind: kind ?? this.kind,
    payload: payload ?? this.payload,
    state: state ?? this.state,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  PlatformListeningOutbox copyWithCompanion(
    PlatformListeningOutboxesCompanion data,
  ) {
    return PlatformListeningOutbox(
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      kind: data.kind.present ? data.kind.value : this.kind,
      payload: data.payload.present ? data.payload.value : this.payload,
      state: data.state.present ? data.state.value : this.state,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlatformListeningOutbox(')
          ..write('ownerId: $ownerId, ')
          ..write('eventId: $eventId, ')
          ..write('kind: $kind, ')
          ..write('payload: $payload, ')
          ..write('state: $state, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(ownerId, eventId, kind, payload, state, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlatformListeningOutbox &&
          other.ownerId == this.ownerId &&
          other.eventId == this.eventId &&
          other.kind == this.kind &&
          other.payload == this.payload &&
          other.state == this.state &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class PlatformListeningOutboxesCompanion
    extends UpdateCompanion<PlatformListeningOutbox> {
  final Value<String> ownerId;
  final Value<String> eventId;
  final Value<String> kind;
  final Value<String> payload;
  final Value<String> state;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const PlatformListeningOutboxesCompanion({
    this.ownerId = const Value.absent(),
    this.eventId = const Value.absent(),
    this.kind = const Value.absent(),
    this.payload = const Value.absent(),
    this.state = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlatformListeningOutboxesCompanion.insert({
    required String ownerId,
    required String eventId,
    required String kind,
    required String payload,
    this.state = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : ownerId = Value(ownerId),
       eventId = Value(eventId),
       kind = Value(kind),
       payload = Value(payload),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<PlatformListeningOutbox> custom({
    Expression<String>? ownerId,
    Expression<String>? eventId,
    Expression<String>? kind,
    Expression<String>? payload,
    Expression<String>? state,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (ownerId != null) 'owner_id': ownerId,
      if (eventId != null) 'event_id': eventId,
      if (kind != null) 'kind': kind,
      if (payload != null) 'payload': payload,
      if (state != null) 'state': state,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlatformListeningOutboxesCompanion copyWith({
    Value<String>? ownerId,
    Value<String>? eventId,
    Value<String>? kind,
    Value<String>? payload,
    Value<String>? state,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return PlatformListeningOutboxesCompanion(
      ownerId: ownerId ?? this.ownerId,
      eventId: eventId ?? this.eventId,
      kind: kind ?? this.kind,
      payload: payload ?? this.payload,
      state: state ?? this.state,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlatformListeningOutboxesCompanion(')
          ..write('ownerId: $ownerId, ')
          ..write('eventId: $eventId, ')
          ..write('kind: $kind, ')
          ..write('payload: $payload, ')
          ..write('state: $state, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $FavoriteTracksTable favoriteTracks = $FavoriteTracksTable(this);
  late final $UserPlaylistsTable userPlaylists = $UserPlaylistsTable(this);
  late final $UserPlaylistTracksTable userPlaylistTracks =
      $UserPlaylistTracksTable(this);
  late final $SyncMutationsTable syncMutations = $SyncMutationsTable(this);
  late final $PlaybackSessionsTable playbackSessions = $PlaybackSessionsTable(
    this,
  );
  late final $PlaybackHistoriesTable playbackHistories =
      $PlaybackHistoriesTable(this);
  late final $PlaybackDailyHistoriesTable playbackDailyHistories =
      $PlaybackDailyHistoriesTable(this);
  late final $PlatformListeningOutboxesTable platformListeningOutboxes =
      $PlatformListeningOutboxesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    favoriteTracks,
    userPlaylists,
    userPlaylistTracks,
    syncMutations,
    playbackSessions,
    playbackHistories,
    playbackDailyHistories,
    platformListeningOutboxes,
  ];
}

typedef $$FavoriteTracksTableCreateCompanionBuilder =
    FavoriteTracksCompanion Function({
      Value<String> ownerId,
      required String trackId,
      required String trackSnapshot,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$FavoriteTracksTableUpdateCompanionBuilder =
    FavoriteTracksCompanion Function({
      Value<String> ownerId,
      Value<String> trackId,
      Value<String> trackSnapshot,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

class $$FavoriteTracksTableFilterComposer
    extends Composer<_$AppDatabase, $FavoriteTracksTable> {
  $$FavoriteTracksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trackSnapshot => $composableBuilder(
    column: $table.trackSnapshot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FavoriteTracksTableOrderingComposer
    extends Composer<_$AppDatabase, $FavoriteTracksTable> {
  $$FavoriteTracksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trackSnapshot => $composableBuilder(
    column: $table.trackSnapshot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FavoriteTracksTableAnnotationComposer
    extends Composer<_$AppDatabase, $FavoriteTracksTable> {
  $$FavoriteTracksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get trackId =>
      $composableBuilder(column: $table.trackId, builder: (column) => column);

  GeneratedColumn<String> get trackSnapshot => $composableBuilder(
    column: $table.trackSnapshot,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$FavoriteTracksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FavoriteTracksTable,
          FavoriteTrack,
          $$FavoriteTracksTableFilterComposer,
          $$FavoriteTracksTableOrderingComposer,
          $$FavoriteTracksTableAnnotationComposer,
          $$FavoriteTracksTableCreateCompanionBuilder,
          $$FavoriteTracksTableUpdateCompanionBuilder,
          (
            FavoriteTrack,
            BaseReferences<_$AppDatabase, $FavoriteTracksTable, FavoriteTrack>,
          ),
          FavoriteTrack,
          PrefetchHooks Function()
        > {
  $$FavoriteTracksTableTableManager(
    _$AppDatabase db,
    $FavoriteTracksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FavoriteTracksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FavoriteTracksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FavoriteTracksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ownerId = const Value.absent(),
                Value<String> trackId = const Value.absent(),
                Value<String> trackSnapshot = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FavoriteTracksCompanion(
                ownerId: ownerId,
                trackId: trackId,
                trackSnapshot: trackSnapshot,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> ownerId = const Value.absent(),
                required String trackId,
                required String trackSnapshot,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FavoriteTracksCompanion.insert(
                ownerId: ownerId,
                trackId: trackId,
                trackSnapshot: trackSnapshot,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FavoriteTracksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FavoriteTracksTable,
      FavoriteTrack,
      $$FavoriteTracksTableFilterComposer,
      $$FavoriteTracksTableOrderingComposer,
      $$FavoriteTracksTableAnnotationComposer,
      $$FavoriteTracksTableCreateCompanionBuilder,
      $$FavoriteTracksTableUpdateCompanionBuilder,
      (
        FavoriteTrack,
        BaseReferences<_$AppDatabase, $FavoriteTracksTable, FavoriteTrack>,
      ),
      FavoriteTrack,
      PrefetchHooks Function()
    >;
typedef $$UserPlaylistsTableCreateCompanionBuilder =
    UserPlaylistsCompanion Function({
      Value<String> ownerId,
      required String id,
      required String name,
      Value<String> description,
      Value<String?> coverAsset,
      Value<String?> coverCloudId,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$UserPlaylistsTableUpdateCompanionBuilder =
    UserPlaylistsCompanion Function({
      Value<String> ownerId,
      Value<String> id,
      Value<String> name,
      Value<String> description,
      Value<String?> coverAsset,
      Value<String?> coverCloudId,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$UserPlaylistsTableFilterComposer
    extends Composer<_$AppDatabase, $UserPlaylistsTable> {
  $$UserPlaylistsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverAsset => $composableBuilder(
    column: $table.coverAsset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverCloudId => $composableBuilder(
    column: $table.coverCloudId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UserPlaylistsTableOrderingComposer
    extends Composer<_$AppDatabase, $UserPlaylistsTable> {
  $$UserPlaylistsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverAsset => $composableBuilder(
    column: $table.coverAsset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverCloudId => $composableBuilder(
    column: $table.coverCloudId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UserPlaylistsTableAnnotationComposer
    extends Composer<_$AppDatabase, $UserPlaylistsTable> {
  $$UserPlaylistsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get coverAsset => $composableBuilder(
    column: $table.coverAsset,
    builder: (column) => column,
  );

  GeneratedColumn<String> get coverCloudId => $composableBuilder(
    column: $table.coverCloudId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$UserPlaylistsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UserPlaylistsTable,
          UserPlaylist,
          $$UserPlaylistsTableFilterComposer,
          $$UserPlaylistsTableOrderingComposer,
          $$UserPlaylistsTableAnnotationComposer,
          $$UserPlaylistsTableCreateCompanionBuilder,
          $$UserPlaylistsTableUpdateCompanionBuilder,
          (
            UserPlaylist,
            BaseReferences<_$AppDatabase, $UserPlaylistsTable, UserPlaylist>,
          ),
          UserPlaylist,
          PrefetchHooks Function()
        > {
  $$UserPlaylistsTableTableManager(_$AppDatabase db, $UserPlaylistsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UserPlaylistsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UserPlaylistsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UserPlaylistsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ownerId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String?> coverAsset = const Value.absent(),
                Value<String?> coverCloudId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UserPlaylistsCompanion(
                ownerId: ownerId,
                id: id,
                name: name,
                description: description,
                coverAsset: coverAsset,
                coverCloudId: coverCloudId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> ownerId = const Value.absent(),
                required String id,
                required String name,
                Value<String> description = const Value.absent(),
                Value<String?> coverAsset = const Value.absent(),
                Value<String?> coverCloudId = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => UserPlaylistsCompanion.insert(
                ownerId: ownerId,
                id: id,
                name: name,
                description: description,
                coverAsset: coverAsset,
                coverCloudId: coverCloudId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UserPlaylistsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UserPlaylistsTable,
      UserPlaylist,
      $$UserPlaylistsTableFilterComposer,
      $$UserPlaylistsTableOrderingComposer,
      $$UserPlaylistsTableAnnotationComposer,
      $$UserPlaylistsTableCreateCompanionBuilder,
      $$UserPlaylistsTableUpdateCompanionBuilder,
      (
        UserPlaylist,
        BaseReferences<_$AppDatabase, $UserPlaylistsTable, UserPlaylist>,
      ),
      UserPlaylist,
      PrefetchHooks Function()
    >;
typedef $$UserPlaylistTracksTableCreateCompanionBuilder =
    UserPlaylistTracksCompanion Function({
      Value<String> ownerId,
      required String playlistId,
      required String trackId,
      required String trackSnapshot,
      required int sortOrder,
      required DateTime addedAt,
      Value<int> rowid,
    });
typedef $$UserPlaylistTracksTableUpdateCompanionBuilder =
    UserPlaylistTracksCompanion Function({
      Value<String> ownerId,
      Value<String> playlistId,
      Value<String> trackId,
      Value<String> trackSnapshot,
      Value<int> sortOrder,
      Value<DateTime> addedAt,
      Value<int> rowid,
    });

class $$UserPlaylistTracksTableFilterComposer
    extends Composer<_$AppDatabase, $UserPlaylistTracksTable> {
  $$UserPlaylistTracksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trackSnapshot => $composableBuilder(
    column: $table.trackSnapshot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UserPlaylistTracksTableOrderingComposer
    extends Composer<_$AppDatabase, $UserPlaylistTracksTable> {
  $$UserPlaylistTracksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trackSnapshot => $composableBuilder(
    column: $table.trackSnapshot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UserPlaylistTracksTableAnnotationComposer
    extends Composer<_$AppDatabase, $UserPlaylistTracksTable> {
  $$UserPlaylistTracksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get trackId =>
      $composableBuilder(column: $table.trackId, builder: (column) => column);

  GeneratedColumn<String> get trackSnapshot => $composableBuilder(
    column: $table.trackSnapshot,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$UserPlaylistTracksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UserPlaylistTracksTable,
          UserPlaylistTrack,
          $$UserPlaylistTracksTableFilterComposer,
          $$UserPlaylistTracksTableOrderingComposer,
          $$UserPlaylistTracksTableAnnotationComposer,
          $$UserPlaylistTracksTableCreateCompanionBuilder,
          $$UserPlaylistTracksTableUpdateCompanionBuilder,
          (
            UserPlaylistTrack,
            BaseReferences<
              _$AppDatabase,
              $UserPlaylistTracksTable,
              UserPlaylistTrack
            >,
          ),
          UserPlaylistTrack,
          PrefetchHooks Function()
        > {
  $$UserPlaylistTracksTableTableManager(
    _$AppDatabase db,
    $UserPlaylistTracksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UserPlaylistTracksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UserPlaylistTracksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UserPlaylistTracksTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> ownerId = const Value.absent(),
                Value<String> playlistId = const Value.absent(),
                Value<String> trackId = const Value.absent(),
                Value<String> trackSnapshot = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UserPlaylistTracksCompanion(
                ownerId: ownerId,
                playlistId: playlistId,
                trackId: trackId,
                trackSnapshot: trackSnapshot,
                sortOrder: sortOrder,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> ownerId = const Value.absent(),
                required String playlistId,
                required String trackId,
                required String trackSnapshot,
                required int sortOrder,
                required DateTime addedAt,
                Value<int> rowid = const Value.absent(),
              }) => UserPlaylistTracksCompanion.insert(
                ownerId: ownerId,
                playlistId: playlistId,
                trackId: trackId,
                trackSnapshot: trackSnapshot,
                sortOrder: sortOrder,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UserPlaylistTracksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UserPlaylistTracksTable,
      UserPlaylistTrack,
      $$UserPlaylistTracksTableFilterComposer,
      $$UserPlaylistTracksTableOrderingComposer,
      $$UserPlaylistTracksTableAnnotationComposer,
      $$UserPlaylistTracksTableCreateCompanionBuilder,
      $$UserPlaylistTracksTableUpdateCompanionBuilder,
      (
        UserPlaylistTrack,
        BaseReferences<
          _$AppDatabase,
          $UserPlaylistTracksTable,
          UserPlaylistTrack
        >,
      ),
      UserPlaylistTrack,
      PrefetchHooks Function()
    >;
typedef $$SyncMutationsTableCreateCompanionBuilder =
    SyncMutationsCompanion Function({
      Value<int> id,
      required String ownerId,
      required String entityType,
      required String entityId,
      required String operation,
      Value<String> payload,
      Value<int> attemptCount,
      Value<String?> lastError,
      required DateTime createdAt,
    });
typedef $$SyncMutationsTableUpdateCompanionBuilder =
    SyncMutationsCompanion Function({
      Value<int> id,
      Value<String> ownerId,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> operation,
      Value<String> payload,
      Value<int> attemptCount,
      Value<String?> lastError,
      Value<DateTime> createdAt,
    });

class $$SyncMutationsTableFilterComposer
    extends Composer<_$AppDatabase, $SyncMutationsTable> {
  $$SyncMutationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncMutationsTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncMutationsTable> {
  $$SyncMutationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncMutationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncMutationsTable> {
  $$SyncMutationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$SyncMutationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncMutationsTable,
          SyncMutation,
          $$SyncMutationsTableFilterComposer,
          $$SyncMutationsTableOrderingComposer,
          $$SyncMutationsTableAnnotationComposer,
          $$SyncMutationsTableCreateCompanionBuilder,
          $$SyncMutationsTableUpdateCompanionBuilder,
          (
            SyncMutation,
            BaseReferences<_$AppDatabase, $SyncMutationsTable, SyncMutation>,
          ),
          SyncMutation,
          PrefetchHooks Function()
        > {
  $$SyncMutationsTableTableManager(_$AppDatabase db, $SyncMutationsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncMutationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncMutationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncMutationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> operation = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => SyncMutationsCompanion(
                id: id,
                ownerId: ownerId,
                entityType: entityType,
                entityId: entityId,
                operation: operation,
                payload: payload,
                attemptCount: attemptCount,
                lastError: lastError,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String ownerId,
                required String entityType,
                required String entityId,
                required String operation,
                Value<String> payload = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                required DateTime createdAt,
              }) => SyncMutationsCompanion.insert(
                id: id,
                ownerId: ownerId,
                entityType: entityType,
                entityId: entityId,
                operation: operation,
                payload: payload,
                attemptCount: attemptCount,
                lastError: lastError,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncMutationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncMutationsTable,
      SyncMutation,
      $$SyncMutationsTableFilterComposer,
      $$SyncMutationsTableOrderingComposer,
      $$SyncMutationsTableAnnotationComposer,
      $$SyncMutationsTableCreateCompanionBuilder,
      $$SyncMutationsTableUpdateCompanionBuilder,
      (
        SyncMutation,
        BaseReferences<_$AppDatabase, $SyncMutationsTable, SyncMutation>,
      ),
      SyncMutation,
      PrefetchHooks Function()
    >;
typedef $$PlaybackSessionsTableCreateCompanionBuilder =
    PlaybackSessionsCompanion Function({
      Value<String> ownerId,
      required int id,
      required String queueSnapshot,
      required int currentIndex,
      required int positionMs,
      required String playbackMode,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$PlaybackSessionsTableUpdateCompanionBuilder =
    PlaybackSessionsCompanion Function({
      Value<String> ownerId,
      Value<int> id,
      Value<String> queueSnapshot,
      Value<int> currentIndex,
      Value<int> positionMs,
      Value<String> playbackMode,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$PlaybackSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $PlaybackSessionsTable> {
  $$PlaybackSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get queueSnapshot => $composableBuilder(
    column: $table.queueSnapshot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get currentIndex => $composableBuilder(
    column: $table.currentIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get playbackMode => $composableBuilder(
    column: $table.playbackMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlaybackSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaybackSessionsTable> {
  $$PlaybackSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get queueSnapshot => $composableBuilder(
    column: $table.queueSnapshot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get currentIndex => $composableBuilder(
    column: $table.currentIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get playbackMode => $composableBuilder(
    column: $table.playbackMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlaybackSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaybackSessionsTable> {
  $$PlaybackSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get queueSnapshot => $composableBuilder(
    column: $table.queueSnapshot,
    builder: (column) => column,
  );

  GeneratedColumn<int> get currentIndex => $composableBuilder(
    column: $table.currentIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get playbackMode => $composableBuilder(
    column: $table.playbackMode,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$PlaybackSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaybackSessionsTable,
          PlaybackSession,
          $$PlaybackSessionsTableFilterComposer,
          $$PlaybackSessionsTableOrderingComposer,
          $$PlaybackSessionsTableAnnotationComposer,
          $$PlaybackSessionsTableCreateCompanionBuilder,
          $$PlaybackSessionsTableUpdateCompanionBuilder,
          (
            PlaybackSession,
            BaseReferences<
              _$AppDatabase,
              $PlaybackSessionsTable,
              PlaybackSession
            >,
          ),
          PlaybackSession,
          PrefetchHooks Function()
        > {
  $$PlaybackSessionsTableTableManager(
    _$AppDatabase db,
    $PlaybackSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaybackSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaybackSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaybackSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> ownerId = const Value.absent(),
                Value<int> id = const Value.absent(),
                Value<String> queueSnapshot = const Value.absent(),
                Value<int> currentIndex = const Value.absent(),
                Value<int> positionMs = const Value.absent(),
                Value<String> playbackMode = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlaybackSessionsCompanion(
                ownerId: ownerId,
                id: id,
                queueSnapshot: queueSnapshot,
                currentIndex: currentIndex,
                positionMs: positionMs,
                playbackMode: playbackMode,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> ownerId = const Value.absent(),
                required int id,
                required String queueSnapshot,
                required int currentIndex,
                required int positionMs,
                required String playbackMode,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => PlaybackSessionsCompanion.insert(
                ownerId: ownerId,
                id: id,
                queueSnapshot: queueSnapshot,
                currentIndex: currentIndex,
                positionMs: positionMs,
                playbackMode: playbackMode,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlaybackSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaybackSessionsTable,
      PlaybackSession,
      $$PlaybackSessionsTableFilterComposer,
      $$PlaybackSessionsTableOrderingComposer,
      $$PlaybackSessionsTableAnnotationComposer,
      $$PlaybackSessionsTableCreateCompanionBuilder,
      $$PlaybackSessionsTableUpdateCompanionBuilder,
      (
        PlaybackSession,
        BaseReferences<_$AppDatabase, $PlaybackSessionsTable, PlaybackSession>,
      ),
      PlaybackSession,
      PrefetchHooks Function()
    >;
typedef $$PlaybackHistoriesTableCreateCompanionBuilder =
    PlaybackHistoriesCompanion Function({
      Value<String> ownerId,
      required String trackId,
      required String trackSnapshot,
      Value<int> playCount,
      Value<int> completedPlayCount,
      Value<int> totalPlayedMs,
      required DateTime lastPlayedAt,
      Value<int> rowid,
    });
typedef $$PlaybackHistoriesTableUpdateCompanionBuilder =
    PlaybackHistoriesCompanion Function({
      Value<String> ownerId,
      Value<String> trackId,
      Value<String> trackSnapshot,
      Value<int> playCount,
      Value<int> completedPlayCount,
      Value<int> totalPlayedMs,
      Value<DateTime> lastPlayedAt,
      Value<int> rowid,
    });

class $$PlaybackHistoriesTableFilterComposer
    extends Composer<_$AppDatabase, $PlaybackHistoriesTable> {
  $$PlaybackHistoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trackSnapshot => $composableBuilder(
    column: $table.trackSnapshot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get playCount => $composableBuilder(
    column: $table.playCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completedPlayCount => $composableBuilder(
    column: $table.completedPlayCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalPlayedMs => $composableBuilder(
    column: $table.totalPlayedMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlaybackHistoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaybackHistoriesTable> {
  $$PlaybackHistoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trackSnapshot => $composableBuilder(
    column: $table.trackSnapshot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get playCount => $composableBuilder(
    column: $table.playCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completedPlayCount => $composableBuilder(
    column: $table.completedPlayCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalPlayedMs => $composableBuilder(
    column: $table.totalPlayedMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlaybackHistoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaybackHistoriesTable> {
  $$PlaybackHistoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get trackId =>
      $composableBuilder(column: $table.trackId, builder: (column) => column);

  GeneratedColumn<String> get trackSnapshot => $composableBuilder(
    column: $table.trackSnapshot,
    builder: (column) => column,
  );

  GeneratedColumn<int> get playCount =>
      $composableBuilder(column: $table.playCount, builder: (column) => column);

  GeneratedColumn<int> get completedPlayCount => $composableBuilder(
    column: $table.completedPlayCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalPlayedMs => $composableBuilder(
    column: $table.totalPlayedMs,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => column,
  );
}

class $$PlaybackHistoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaybackHistoriesTable,
          PlaybackHistory,
          $$PlaybackHistoriesTableFilterComposer,
          $$PlaybackHistoriesTableOrderingComposer,
          $$PlaybackHistoriesTableAnnotationComposer,
          $$PlaybackHistoriesTableCreateCompanionBuilder,
          $$PlaybackHistoriesTableUpdateCompanionBuilder,
          (
            PlaybackHistory,
            BaseReferences<
              _$AppDatabase,
              $PlaybackHistoriesTable,
              PlaybackHistory
            >,
          ),
          PlaybackHistory,
          PrefetchHooks Function()
        > {
  $$PlaybackHistoriesTableTableManager(
    _$AppDatabase db,
    $PlaybackHistoriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaybackHistoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaybackHistoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaybackHistoriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> ownerId = const Value.absent(),
                Value<String> trackId = const Value.absent(),
                Value<String> trackSnapshot = const Value.absent(),
                Value<int> playCount = const Value.absent(),
                Value<int> completedPlayCount = const Value.absent(),
                Value<int> totalPlayedMs = const Value.absent(),
                Value<DateTime> lastPlayedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlaybackHistoriesCompanion(
                ownerId: ownerId,
                trackId: trackId,
                trackSnapshot: trackSnapshot,
                playCount: playCount,
                completedPlayCount: completedPlayCount,
                totalPlayedMs: totalPlayedMs,
                lastPlayedAt: lastPlayedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> ownerId = const Value.absent(),
                required String trackId,
                required String trackSnapshot,
                Value<int> playCount = const Value.absent(),
                Value<int> completedPlayCount = const Value.absent(),
                Value<int> totalPlayedMs = const Value.absent(),
                required DateTime lastPlayedAt,
                Value<int> rowid = const Value.absent(),
              }) => PlaybackHistoriesCompanion.insert(
                ownerId: ownerId,
                trackId: trackId,
                trackSnapshot: trackSnapshot,
                playCount: playCount,
                completedPlayCount: completedPlayCount,
                totalPlayedMs: totalPlayedMs,
                lastPlayedAt: lastPlayedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlaybackHistoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaybackHistoriesTable,
      PlaybackHistory,
      $$PlaybackHistoriesTableFilterComposer,
      $$PlaybackHistoriesTableOrderingComposer,
      $$PlaybackHistoriesTableAnnotationComposer,
      $$PlaybackHistoriesTableCreateCompanionBuilder,
      $$PlaybackHistoriesTableUpdateCompanionBuilder,
      (
        PlaybackHistory,
        BaseReferences<_$AppDatabase, $PlaybackHistoriesTable, PlaybackHistory>,
      ),
      PlaybackHistory,
      PrefetchHooks Function()
    >;
typedef $$PlaybackDailyHistoriesTableCreateCompanionBuilder =
    PlaybackDailyHistoriesCompanion Function({
      Value<String> ownerId,
      required String dayKey,
      required String trackId,
      required String trackSnapshot,
      Value<int> playCount,
      Value<int> totalPlayedMs,
      required DateTime lastPlayedAt,
      Value<int> rowid,
    });
typedef $$PlaybackDailyHistoriesTableUpdateCompanionBuilder =
    PlaybackDailyHistoriesCompanion Function({
      Value<String> ownerId,
      Value<String> dayKey,
      Value<String> trackId,
      Value<String> trackSnapshot,
      Value<int> playCount,
      Value<int> totalPlayedMs,
      Value<DateTime> lastPlayedAt,
      Value<int> rowid,
    });

class $$PlaybackDailyHistoriesTableFilterComposer
    extends Composer<_$AppDatabase, $PlaybackDailyHistoriesTable> {
  $$PlaybackDailyHistoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dayKey => $composableBuilder(
    column: $table.dayKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trackSnapshot => $composableBuilder(
    column: $table.trackSnapshot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get playCount => $composableBuilder(
    column: $table.playCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalPlayedMs => $composableBuilder(
    column: $table.totalPlayedMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlaybackDailyHistoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaybackDailyHistoriesTable> {
  $$PlaybackDailyHistoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dayKey => $composableBuilder(
    column: $table.dayKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trackId => $composableBuilder(
    column: $table.trackId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trackSnapshot => $composableBuilder(
    column: $table.trackSnapshot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get playCount => $composableBuilder(
    column: $table.playCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalPlayedMs => $composableBuilder(
    column: $table.totalPlayedMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlaybackDailyHistoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaybackDailyHistoriesTable> {
  $$PlaybackDailyHistoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get dayKey =>
      $composableBuilder(column: $table.dayKey, builder: (column) => column);

  GeneratedColumn<String> get trackId =>
      $composableBuilder(column: $table.trackId, builder: (column) => column);

  GeneratedColumn<String> get trackSnapshot => $composableBuilder(
    column: $table.trackSnapshot,
    builder: (column) => column,
  );

  GeneratedColumn<int> get playCount =>
      $composableBuilder(column: $table.playCount, builder: (column) => column);

  GeneratedColumn<int> get totalPlayedMs => $composableBuilder(
    column: $table.totalPlayedMs,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => column,
  );
}

class $$PlaybackDailyHistoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaybackDailyHistoriesTable,
          PlaybackDailyHistory,
          $$PlaybackDailyHistoriesTableFilterComposer,
          $$PlaybackDailyHistoriesTableOrderingComposer,
          $$PlaybackDailyHistoriesTableAnnotationComposer,
          $$PlaybackDailyHistoriesTableCreateCompanionBuilder,
          $$PlaybackDailyHistoriesTableUpdateCompanionBuilder,
          (
            PlaybackDailyHistory,
            BaseReferences<
              _$AppDatabase,
              $PlaybackDailyHistoriesTable,
              PlaybackDailyHistory
            >,
          ),
          PlaybackDailyHistory,
          PrefetchHooks Function()
        > {
  $$PlaybackDailyHistoriesTableTableManager(
    _$AppDatabase db,
    $PlaybackDailyHistoriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaybackDailyHistoriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$PlaybackDailyHistoriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$PlaybackDailyHistoriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> ownerId = const Value.absent(),
                Value<String> dayKey = const Value.absent(),
                Value<String> trackId = const Value.absent(),
                Value<String> trackSnapshot = const Value.absent(),
                Value<int> playCount = const Value.absent(),
                Value<int> totalPlayedMs = const Value.absent(),
                Value<DateTime> lastPlayedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlaybackDailyHistoriesCompanion(
                ownerId: ownerId,
                dayKey: dayKey,
                trackId: trackId,
                trackSnapshot: trackSnapshot,
                playCount: playCount,
                totalPlayedMs: totalPlayedMs,
                lastPlayedAt: lastPlayedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> ownerId = const Value.absent(),
                required String dayKey,
                required String trackId,
                required String trackSnapshot,
                Value<int> playCount = const Value.absent(),
                Value<int> totalPlayedMs = const Value.absent(),
                required DateTime lastPlayedAt,
                Value<int> rowid = const Value.absent(),
              }) => PlaybackDailyHistoriesCompanion.insert(
                ownerId: ownerId,
                dayKey: dayKey,
                trackId: trackId,
                trackSnapshot: trackSnapshot,
                playCount: playCount,
                totalPlayedMs: totalPlayedMs,
                lastPlayedAt: lastPlayedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlaybackDailyHistoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaybackDailyHistoriesTable,
      PlaybackDailyHistory,
      $$PlaybackDailyHistoriesTableFilterComposer,
      $$PlaybackDailyHistoriesTableOrderingComposer,
      $$PlaybackDailyHistoriesTableAnnotationComposer,
      $$PlaybackDailyHistoriesTableCreateCompanionBuilder,
      $$PlaybackDailyHistoriesTableUpdateCompanionBuilder,
      (
        PlaybackDailyHistory,
        BaseReferences<
          _$AppDatabase,
          $PlaybackDailyHistoriesTable,
          PlaybackDailyHistory
        >,
      ),
      PlaybackDailyHistory,
      PrefetchHooks Function()
    >;
typedef $$PlatformListeningOutboxesTableCreateCompanionBuilder =
    PlatformListeningOutboxesCompanion Function({
      required String ownerId,
      required String eventId,
      required String kind,
      required String payload,
      Value<String> state,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$PlatformListeningOutboxesTableUpdateCompanionBuilder =
    PlatformListeningOutboxesCompanion Function({
      Value<String> ownerId,
      Value<String> eventId,
      Value<String> kind,
      Value<String> payload,
      Value<String> state,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$PlatformListeningOutboxesTableFilterComposer
    extends Composer<_$AppDatabase, $PlatformListeningOutboxesTable> {
  $$PlatformListeningOutboxesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlatformListeningOutboxesTableOrderingComposer
    extends Composer<_$AppDatabase, $PlatformListeningOutboxesTable> {
  $$PlatformListeningOutboxesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlatformListeningOutboxesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlatformListeningOutboxesTable> {
  $$PlatformListeningOutboxesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$PlatformListeningOutboxesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlatformListeningOutboxesTable,
          PlatformListeningOutbox,
          $$PlatformListeningOutboxesTableFilterComposer,
          $$PlatformListeningOutboxesTableOrderingComposer,
          $$PlatformListeningOutboxesTableAnnotationComposer,
          $$PlatformListeningOutboxesTableCreateCompanionBuilder,
          $$PlatformListeningOutboxesTableUpdateCompanionBuilder,
          (
            PlatformListeningOutbox,
            BaseReferences<
              _$AppDatabase,
              $PlatformListeningOutboxesTable,
              PlatformListeningOutbox
            >,
          ),
          PlatformListeningOutbox,
          PrefetchHooks Function()
        > {
  $$PlatformListeningOutboxesTableTableManager(
    _$AppDatabase db,
    $PlatformListeningOutboxesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlatformListeningOutboxesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$PlatformListeningOutboxesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$PlatformListeningOutboxesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> ownerId = const Value.absent(),
                Value<String> eventId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlatformListeningOutboxesCompanion(
                ownerId: ownerId,
                eventId: eventId,
                kind: kind,
                payload: payload,
                state: state,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String ownerId,
                required String eventId,
                required String kind,
                required String payload,
                Value<String> state = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => PlatformListeningOutboxesCompanion.insert(
                ownerId: ownerId,
                eventId: eventId,
                kind: kind,
                payload: payload,
                state: state,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlatformListeningOutboxesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlatformListeningOutboxesTable,
      PlatformListeningOutbox,
      $$PlatformListeningOutboxesTableFilterComposer,
      $$PlatformListeningOutboxesTableOrderingComposer,
      $$PlatformListeningOutboxesTableAnnotationComposer,
      $$PlatformListeningOutboxesTableCreateCompanionBuilder,
      $$PlatformListeningOutboxesTableUpdateCompanionBuilder,
      (
        PlatformListeningOutbox,
        BaseReferences<
          _$AppDatabase,
          $PlatformListeningOutboxesTable,
          PlatformListeningOutbox
        >,
      ),
      PlatformListeningOutbox,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$FavoriteTracksTableTableManager get favoriteTracks =>
      $$FavoriteTracksTableTableManager(_db, _db.favoriteTracks);
  $$UserPlaylistsTableTableManager get userPlaylists =>
      $$UserPlaylistsTableTableManager(_db, _db.userPlaylists);
  $$UserPlaylistTracksTableTableManager get userPlaylistTracks =>
      $$UserPlaylistTracksTableTableManager(_db, _db.userPlaylistTracks);
  $$SyncMutationsTableTableManager get syncMutations =>
      $$SyncMutationsTableTableManager(_db, _db.syncMutations);
  $$PlaybackSessionsTableTableManager get playbackSessions =>
      $$PlaybackSessionsTableTableManager(_db, _db.playbackSessions);
  $$PlaybackHistoriesTableTableManager get playbackHistories =>
      $$PlaybackHistoriesTableTableManager(_db, _db.playbackHistories);
  $$PlaybackDailyHistoriesTableTableManager get playbackDailyHistories =>
      $$PlaybackDailyHistoriesTableTableManager(
        _db,
        _db.playbackDailyHistories,
      );
  $$PlatformListeningOutboxesTableTableManager get platformListeningOutboxes =>
      $$PlatformListeningOutboxesTableTableManager(
        _db,
        _db.platformListeningOutboxes,
      );
}
