import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../platform_backend_providers.dart';
import 'netease_messages_repository.dart';

/// One account-scoped read per poll, shared by every entry badge. Disposing the
/// consumer or backgrounding the app stops requests; failures retain the last
/// known count rather than inventing zero or a successful read acknowledgement.
final neteaseUnreadCountsProvider =
    StreamProvider.autoDispose<Map<String, int>>((ref) async* {
      if (!ref.watch(usesNeteaseProvider)) {
        yield const {};
        return;
      }
      final repository = ref.watch(neteaseMessagesRepositoryProvider);
      Map<String, int>? last;
      var stopped = false;
      Timer? timer;
      Completer<void>? wake;
      final observer = _UnreadResumeObserver(() {
        timer?.cancel();
        if (wake?.isCompleted == false) wake!.complete();
      });
      WidgetsBinding.instance.addObserver(observer);
      ref.onDispose(() {
        stopped = true;
        timer?.cancel();
        WidgetsBinding.instance.removeObserver(observer);
        if (wake?.isCompleted == false) wake!.complete();
      });
      while (!stopped) {
        if (WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed) {
          var conversationsRead = false;
          Object? failure;
          try {
            // Reconcile current peer timestamps before subtracting local read
            // cursors: an old conversation must not hide newly arrived mail.
            try {
              await repository.conversations();
              conversationsRead = true;
            } catch (_) {
              /* Counts remain independently readable. */
            }
            last = await repository.counts();
          } catch (error) {
            failure = error;
          }
          if (stopped) return;
          if (last != null) {
            yield last;
          } else if (conversationsRead) {
            yield {'privateMsgCount': repository.knownRawPrivateUnread};
          } else if (failure != null) {
            // Retain an error/unknown state instead of manufacturing zero.
            yield* Stream<Map<String, int>>.error(failure);
          }
        }
        wake = Completer<void>();
        timer = Timer(const Duration(seconds: 30), () => wake?.complete());
        await wake.future;
      }
    });

final neteaseUnreadTotalProvider = Provider.autoDispose<int>((ref) {
  ref.watch(neteaseMessageReadRevisionProvider);
  final state = ref.watch(neteaseUnreadCountsProvider);
  // Riverpod can retain the previous stream value while a dependency reloads.
  // A new account must never briefly inherit that old account's unread badge.
  final raw = state.isLoading
      ? const <String, int>{}
      : state.value ?? const <String, int>{};
  final counts = ref
      .watch(neteaseMessagesRepositoryProvider)
      .visibleCounts(raw);
  return counts.values.fold(0, (sum, count) => sum + (count < 0 ? 0 : count));
});

class _UnreadResumeObserver extends WidgetsBindingObserver {
  _UnreadResumeObserver(this.resume);
  final VoidCallback resume;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) resume();
  }
}

/// Notification red is independent of Material's error palette: that palette
/// intentionally becomes pale red in dark mode. White text on this red remains
/// legible at badge sizes and matches every NetEase unread entry.
abstract final class NeteaseUnreadColors {
  static const background = Color(0xFFD92436);
  static const foreground = Colors.white;
}

class NeteaseUnreadBadge extends StatelessWidget {
  const NeteaseUnreadBadge(this.count, {super.key});
  final int count;
  @override
  Widget build(BuildContext context) => count <= 0
      ? const SizedBox.shrink()
      : Semantics(
          label: '$count 条未读消息',
          child: Container(
            key: const ValueKey('netease-unread-badge'),
            constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: NeteaseUnreadColors.background,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              count > 99 ? '99+' : '$count',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: NeteaseUnreadColors.foreground,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
}
