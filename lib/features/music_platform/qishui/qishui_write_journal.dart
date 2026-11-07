import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Only opaque operation digests are persisted. An interrupted write remains
/// pending until a readback confirms it; a fresh page/process never replays it.
class QishuiWriteJournal {
  QishuiWriteJournal({this.persistent = false});
  final bool persistent;
  static final _memory = <String>{};
  static const _prefix = 'mesting_qishui_write167_';
  String key(String owner, String operation) =>
      _prefix + sha256.convert(utf8.encode('$owner\n$operation')).toString();
  Future<bool> pending(String key) async => persistent
      ? (await SharedPreferences.getInstance()).getBool(key) == true
      : _memory.contains(key);
  Future<void> begin(String key) async {
    if (persistent) {
      if (!await (await SharedPreferences.getInstance()).setBool(key, true)) {
        throw StateError('无法保存本次汽水操作状态，请稍后重试');
      }
    } else {
      _memory.add(key);
    }
  }

  Future<void> finish(String key) async {
    if (persistent) {
      await (await SharedPreferences.getInstance()).remove(key);
    } else {
      _memory.remove(key);
    }
  }
}
