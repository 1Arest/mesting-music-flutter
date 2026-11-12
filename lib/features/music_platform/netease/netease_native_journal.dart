import '../listening_sync/listening_sync_models.dart';
import '../listening_sync/listening_sync_store.dart';

/// Reserve a native sequence and claim exactly one unsent row atomically.
/// No schema change, network call or rewriting of previously dispatched rows.
Future<ListeningSyncEntry?> claimNeteaseNativeLog(
  ListeningSyncStore store,
  ListeningSyncEntry candidate,
  DateTime now,
) => store.database.transaction(() async {
  final row = await store.entry(candidate.ownerId, candidate.id);
  if (row == null || row.state != ListeningSyncState.queued) return null;
  const id = 'netease-native-sequence:v1';
  final counter = await store.entry(row.ownerId, id);
  final sequence = (counter?.number('next') ?? 0) & 0xffffffff;
  final payload = {...row.payload, 'nativeSequence': sequence};
  if (!await store.change(
    row,
    ListeningSyncState.dispatched,
    now,
    expected: ListeningSyncState.queued,
    payload: payload,
  )) {
    return null;
  }
  final next = {'next': (sequence + 1) & 0xffffffff};
  if (counter == null) {
    await store.put(
      owner: row.ownerId,
      id: id,
      kind: 'control',
      payload: next,
      now: now,
      state: ListeningSyncState.verified,
    );
  } else {
    await store.change(
      counter,
      ListeningSyncState.verified,
      now,
      payload: next,
    );
  }
  return store.entry(row.ownerId, row.id);
});
