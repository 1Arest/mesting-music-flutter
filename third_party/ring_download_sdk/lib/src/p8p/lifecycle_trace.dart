/// Local observation only. No wire IDs, addresses, SDP or content enter traces.
enum P8PLifecycleCode {
  helloReady('hello_ready'),
  requestAllocated('piece_request_allocated'),
  requestEnqueued('piece_request_enqueued'),
  firstHeader('first_piece_header'),
  rescueSlot('rescue_slot');

  const P8PLifecycleCode(this.code);
  final String code;
}

class P8PLifecycleEvent {
  P8PLifecycleEvent(
    this.code, {
    String? alias,
    Map<String, int> metrics = const {},
  }) : alias =
           const {
             'peer1',
             'peer2',
             'peer3',
             'peer4',
             'seed',
             'https',
           }.contains(alias)
           ? alias
           : null,
       metrics = Map.unmodifiable({
         for (final entry in metrics.entries)
           if (_bounds.containsKey(entry.key) &&
               entry.value >= 0 &&
               entry.value <= _bounds[entry.key]!)
             entry.key: entry.value,
       });

  final P8PLifecycleCode code;
  final String? alias;
  final Map<String, int> metrics;
  static const _bounds = {
    'request_timeout_us': 300000000,
    'reserved_slots': 4,
    'snapshot_sequence': 6,
    'slot_position': 4,
    // 1=active, 2=cancelling, 3=verified ready, 4=writing.
    'slot_phase': 4,
    'piece_ahead': 3,
    'body_bytes': 1048576,
    'body_expected_bytes': 1048576,
    'request_age_us': 300000000,
    'request_remaining_us': 300000000,
    'owner_closed': 1,
  };
}

typedef P8PLifecycleObserver = void Function(P8PLifecycleEvent event);

void observeP8PLifecycle(
  P8PLifecycleObserver? observer,
  P8PLifecycleEvent event,
) {
  try {
    observer?.call(event);
  } catch (_) {
    // A logger cannot turn a queued request into a transport error.
  }
}
