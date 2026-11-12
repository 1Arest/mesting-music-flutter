import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../music_platform/music_platform_providers.dart';
import 'audio_downloads.dart';
import 'netease_download_source_picker.dart';

/// Queue work never waits for a dialog. Failed official tasks enter a durable
/// awaitingSource state; this foreground-only coordinator presents one choice
/// at a time. Dismissed choices remain available in 下载管理 across restarts.
class DownloadSourceCoordinator extends ConsumerStatefulWidget {
  const DownloadSourceCoordinator({
    required this.navigatorKey,
    required this.child,
    this.enabled = true,
    super.key,
  });
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  final bool enabled;
  @override
  ConsumerState<DownloadSourceCoordinator> createState() =>
      _DownloadSourceCoordinatorState();
}

class _DownloadSourceCoordinatorState
    extends ConsumerState<DownloadSourceCoordinator>
    with WidgetsBindingObserver {
  AudioDownloadManager? _manager;
  final _shown = <String>{};
  bool _open = false, _scheduled = false;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _manager?.collectionChanges.removeListener(_schedule);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _schedule();
  }

  void _schedule() {
    if (!mounted || _scheduled || _open || !_foreground || !widget.enabled) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted && !_open && _foreground) unawaited(_show());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _show() async {
    final manager = _manager;
    final context = widget.navigatorKey.currentContext;
    final account = ref.read(platformAccountProvider).value;
    if (manager == null ||
        context == null ||
        !context.mounted ||
        account == null) {
      return;
    }
    final task = manager.tasks
        .where(
          (task) =>
              task.owner == account.ownerId &&
              task.phase == AudioDownloadPhase.awaitingSource &&
              !_shown.contains('${task.id}|${task.downloadSource?.name}'),
        )
        .firstOrNull;
    if (task == null) return;
    _open = true;
    _shown.add('${task.id}|${task.downloadSource?.name}');
    try {
      final choice = await chooseNeteaseDownloadSource(context, task);
      if (!mounted ||
          choice == null ||
          !identical(_manager, manager) ||
          ref.read(platformAccountProvider).value?.ownerId != account.ownerId ||
          ref.read(platformAccountProvider).value?.token != account.token) {
        return;
      }
      manager.selectDownloadSource(task.id, choice);
    } finally {
      _open = false;
      _schedule();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.enabled) {
      final manager = ref.watch(audioDownloadManagerProvider);
      ref.watch(platformAccountProvider);
      if (!identical(_manager, manager)) {
        _manager?.collectionChanges.removeListener(_schedule);
        _manager = manager;
        manager.collectionChanges.addListener(_schedule);
      }
      _schedule();
    }
    return widget.child;
  }
}
