import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/platform_session.dart';
import '../music_platform_providers.dart';
import 'qishui_providers.dart';

/// A pushed private page outlives its root Navigator during a platform switch.
/// Bind it on entry, hide old data on any login change, and cancel owned reads
/// on pop. This is independent from the shared audio player's lifetime.
mixin QishuiOwnedPage<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  late final String? _entryCredential;
  final _pageAbort = Completer<void>();
  Future<void> get pageAbort => _pageAbort.future;
  @override
  void initState() {
    super.initState();
    _entryCredential = ref.read(qishuiApiProvider).credential;
  }

  bool _matches(PlatformSession? account) =>
      _entryCredential != null &&
      account?.platform == MusicPlatform.qishui &&
      account?.token == _entryCredential;
  bool get ownerCurrent =>
      mounted && _matches(ref.read(platformAccountProvider).value);
  bool watchOwner() {
    final current = _matches(ref.watch(platformAccountProvider).value);
    if (!current && !_pageAbort.isCompleted) _pageAbort.complete();
    return current;
  }

  Widget changedAccount() => Scaffold(
    appBar: AppBar(title: const Text('账号已变化')),
    body: const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('请返回当前账号，重新打开此页面。'),
      ),
    ),
  );
  @override
  void dispose() {
    if (!_pageAbort.isCompleted) _pageAbort.complete();
    super.dispose();
  }
}
