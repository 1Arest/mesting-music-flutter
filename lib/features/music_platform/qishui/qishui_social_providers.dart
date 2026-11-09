import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'qishui_providers.dart';
import 'qishui_social_models.dart';
import 'qishui_social_repository.dart';
import 'qishui_write_journal.dart';

final qishuiSocialRepositoryProvider = Provider<QishuiSocialRepository>(
  (ref) => QishuiSocialRepository(
    ref.watch(qishuiRepositoryProvider),
    journal: QishuiWriteJournal(persistent: true),
  ),
);

/// Only a visible consumer starts this read. Binding changes dispose its
/// cancellation owner and cannot publish the outgoing account's statistics.
final qishuiSocialStatsProvider = FutureProvider<QishuiSocialStats>((ref) {
  final abort = Completer<void>();
  ref.onDispose(() {
    if (!abort.isCompleted) abort.complete();
  });
  return ref
      .watch(qishuiSocialRepositoryProvider)
      .fetchStats(abortTrigger: abort.future);
}, retry: (count, error) => null);
