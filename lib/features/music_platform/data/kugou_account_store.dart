import '../../../core/security/retained_secure_read.dart';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/security/retained_secure_storage.dart';
import '../domain/platform_session.dart';
import 'platform_session_store.dart';

/// 账号列表仅暴露展示资料。凭据只能由存储/切换协调层取出，不能写入偏好或导出。
class KugouSavedAccount {
  const KugouSavedAccount({
    required this.userId,
    required this.nickname,
    required this.avatarUrl,
    this.loginMethod = '',
    this.standardAuthorized = false,
  });
  final String userId, nickname, avatarUrl, loginMethod;
  final bool standardAuthorized;

  String get methodLabel => switch (loginMethod) {
    'phone' => '手机号登录',
    'kugouQr' => '酷狗扫码登录',
    'wechatQr' => '微信扫码登录',
    'qqQr' => 'QQ 扫码登录',
    _ => '酷狗账号',
  };
}

/// 同一快照保存当前 UID 和多个加密登录，避免凭据列表与当前账号分两次提交。
/// 快照只用于本机事务回滚，不提供 JSON 导出接口。
class KugouAccountSnapshot {
  KugouAccountSnapshot._(this._accounts, this._selectedId);
  final List<_KugouCredential> _accounts;
  final String? _selectedId;

  PlatformSession? get selected => _accounts
      .where((row) => row.session.userId == _selectedId)
      .firstOrNull
      ?.session;
  List<KugouSavedAccount> get accounts => List.unmodifiable(
    _accounts.map(
      (row) => KugouSavedAccount(
        userId: row.session.userId,
        nickname: row.session.nickname,
        avatarUrl: row.session.avatarUrl,
        loginMethod: row.loginMethod,
        standardAuthorized: row.session.kugouStandardToken.isNotEmpty,
      ),
    ),
  );
}

abstract interface class KugouAccountStore implements PlatformSessionStore {
  Future<KugouAccountSnapshot> snapshot();
  Future<PlatformSession?> account(String userId);
  Future<void> select(PlatformSession session, {String? loginMethod});
  Future<void> remove(String userId);
  Future<void> restore(KugouAccountSnapshot snapshot);
}

class _KugouCredential {
  const _KugouCredential(this.session, this.loginMethod);
  final PlatformSession session;
  final String loginMethod;
}

/// 旧版单账号仅作为迁移来源。新快照写入且逐字节回读成功之后，才删除旧槽。
/// 空列表仍写成有效快照，不能因退出/移除最后一个账号而再次恢复旧登录。
class SecureKugouAccountStore implements KugouAccountStore {
  SecureKugouAccountStore({
    FlutterSecureStorage storage = retainedSecureStorage,
    PlatformSessionStore? legacy,
  }) : _storage = storage,
       _legacy = legacy ?? SecurePlatformSessionStore(storage: storage);

  static const key = 'mesting_music_platform_kugou_accounts_v2';
  final FlutterSecureStorage _storage;
  final PlatformSessionStore _legacy;
  Future<void> _pending = Future<void>.value();

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  static String _method(Object? value) =>
      const {'phone', 'kugouQr', 'wechatQr', 'qqQr'}.contains(value)
      ? value as String
      : '';

  static KugouAccountSnapshot _decode(String raw) {
    final value = jsonDecode(raw);
    if (value is! Map || value['version'] != 2 || value['accounts'] is! List) {
      throw const FormatException('本机酷狗账号资料暂时无法读取，请重试');
    }
    final rows = <_KugouCredential>[];
    final ids = <String>{};
    for (final item in value['accounts'] as List) {
      if (item is! Map || item['session'] is! Map) {
        throw const FormatException('本机酷狗账号资料暂时无法读取，请重试');
      }
      final session = PlatformSession.fromJson(
        Map<String, dynamic>.from(item['session'] as Map),
      );
      if (!ids.add(session.userId)) {
        throw const FormatException('本机酷狗账号资料重复，请重试');
      }
      rows.add(_KugouCredential(session, _method(item['method'])));
    }
    final selected = value['selected'];
    if (selected != null && (selected is! String || !ids.contains(selected))) {
      throw const FormatException('本机酷狗账号选择暂时无法读取，请重试');
    }
    return KugouAccountSnapshot._(List.unmodifiable(rows), selected as String?);
  }

  static String _encode(KugouAccountSnapshot value) => jsonEncode({
    'version': 2,
    'selected': value._selectedId,
    'accounts': [
      for (final row in value._accounts)
        {'session': row.session.toJson(), 'method': row.loginMethod},
    ],
  });

  Future<String?> _readRaw() async {
    // 沿用旧存储的短暂 KeyStore 挂载重试；读取失败绝不当成空列表覆盖。
    for (var attempt = 0; ; attempt++) {
      try {
        final value = await readRetainedSecureValue(_storage, key);
        if (value != null || attempt >= 2) return value;
      } on PlatformException {
        if (attempt >= 2) rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 100 * (attempt + 1)));
    }
  }

  Future<void> _writeRaw(String raw, {String? previous}) async {
    try {
      await _storage.write(key: key, value: raw);
      if (await _storage.read(key: key) != raw) {
        throw StateError('酷狗账号保存未完成，请重试');
      }
    } on Object {
      // 写入回执不明确时恢复旧快照；UI 在此之前不会发布目标账号。
      // 首次迁移没有旧快照，保留旧单账号槽，下一次可继续读取/迁移。
      if (previous != null) {
        try {
          await _storage.write(key: key, value: previous);
        } on Object {
          // 账号仍不发布；安全存储恢复后由显式重试重新核对。
        }
      }
      rethrow;
    }
  }

  Future<KugouAccountSnapshot> _load() async {
    final raw = await _readRaw();
    if (raw != null) return _decode(raw);
    final legacy = await _legacy.read();
    final migrated = KugouAccountSnapshot._(
      legacy == null ? const [] : [_KugouCredential(legacy, '')],
      legacy?.userId,
    );
    await _writeRaw(_encode(migrated));
    if (legacy != null) await _legacy.clear();
    return migrated;
  }

  Future<void> _save(
    KugouAccountSnapshot next,
    KugouAccountSnapshot previous,
  ) => _writeRaw(_encode(next), previous: _encode(previous));

  @override
  Future<KugouAccountSnapshot> snapshot() => _serialize(_load);

  @override
  Future<PlatformSession?> read() =>
      _serialize(() async => (await _load()).selected);

  @override
  Future<PlatformSession?> account(String userId) => _serialize(() async {
    final saved = await _load();
    return saved._accounts
        .where((row) => row.session.userId == userId)
        .firstOrNull
        ?.session;
  });

  @override
  Future<void> write(PlatformSession session) => select(session);

  @override
  Future<void> select(PlatformSession session, {String? loginMethod}) =>
      _serialize(() async {
        if (session.platform != MusicPlatform.kugou) {
          throw ArgumentError('仅可保存酷狗账号');
        }
        final previous = await _load();
        final existing = previous._accounts
            .where((row) => row.session.userId == session.userId)
            .firstOrNull;
        // Lite重新登录只更新它自己的token，不能丢掉同UID已验证的标准授权。
        // 账号移除/退出会删除整份凭据；重新添加时不会跨UID继承授权。
        final combined =
            session.kugouStandardToken.isNotEmpty || existing == null
            ? session
            : PlatformSession(
                userId: session.userId,
                token: session.token,
                vipToken: session.vipToken,
                nickname: session.nickname,
                avatarUrl: session.avatarUrl,
                kugouStandardToken: existing.session.kugouStandardToken,
                kugouStandardVipToken: existing.session.kugouStandardVipToken,
              );
        final next = KugouAccountSnapshot._([
          // 同 UID 的重新登录只替换凭据，不新增重复账号。
          for (final row in previous._accounts)
            if (row.session.userId != session.userId) row,
          _KugouCredential(
            combined,
            loginMethod == null
                ? existing?.loginMethod ?? ''
                : _method(loginMethod),
          ),
        ], session.userId);
        await _save(next, previous);
      });

  @override
  Future<void> remove(String userId) => _serialize(() async {
    final previous = await _load();
    final next = KugouAccountSnapshot._([
      for (final row in previous._accounts)
        if (row.session.userId != userId) row,
    ], previous._selectedId == userId ? null : previous._selectedId);
    // 只改加密登录。音乐库、队列、历史、末播和置顶均由原 owner 仓库保留。
    await _save(next, previous);
  });

  @override
  Future<void> clear() => _serialize(() async {
    final previous = await _load();
    final id = previous._selectedId;
    if (id == null) return;
    await _save(
      KugouAccountSnapshot._([
        for (final row in previous._accounts)
          if (row.session.userId != id) row,
      ], null),
      previous,
    );
  });

  @override
  Future<void> restore(KugouAccountSnapshot snapshot) => _serialize(() async {
    final previous = await _load();
    await _save(snapshot, previous);
  });
}
