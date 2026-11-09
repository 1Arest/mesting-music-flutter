import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/music_http_client.dart';
import '../../../core/network/music_network_diagnostics.dart';
import 'qishui_api.dart';
import 'qishui_models.dart';

/// The music-wall DTO stores seconds. This is independent of the millisecond
/// duration used by playback reporting. Missing fields remain unknown, not 0.
class QishuiListeningSnapshot {
  const QishuiListeningSnapshot({
    required this.fetchedAt,
    this.totalSeconds,
    this.weekSeconds,
    this.weekRank,
    this.likeCount,
  });

  final int? totalSeconds, weekSeconds, weekRank, likeCount;
  final DateTime fetchedAt;

  static QishuiListeningSnapshot parse(
    Map<String, dynamic> response, {
    required DateTime fetchedAt,
  }) {
    final nested = sodaMap(response['data']);
    final payload = nested.containsKey('listen_duration') ? nested : response;
    final duration = sodaMap(payload['listen_duration']);
    if (duration.isEmpty) {
      throw const QishuiException(
        '汽水暂未返回官方听歌时长，请稍后刷新',
        kind: QishuiFailureKind.format,
      );
    }
    int? number(String name) {
      final raw = duration[name];
      if (raw == null) return null;
      final value = raw is int ? raw : int.tryParse(raw is String ? raw : '');
      if (value == null || value < 0) {
        throw const QishuiException(
          '汽水听歌时长格式异常，请稍后刷新',
          kind: QishuiFailureKind.format,
        );
      }
      return value;
    }

    return QishuiListeningSnapshot(
      totalSeconds: number('total_duration'),
      weekSeconds: number('week_duration'),
      weekRank: number('week_rank'),
      likeCount: number('like_count'),
      fetchedAt: fetchedAt,
    );
  }
}

/// Local accounting is deliberately labelled separately from the cloud total.
/// Transport acceptance says that the report endpoint accepted a request; it
/// never proves the official music-wall total has incorporated that duration.
class QishuiListeningLedger {
  const QishuiListeningLedger({
    this.heardMilliseconds = 0,
    this.transportAcceptedMilliseconds = 0,
    this.unconfirmedMilliseconds = 0,
  });

  final int heardMilliseconds;
  final int transportAcceptedMilliseconds;
  final int unconfirmedMilliseconds;

  Map<String, Object> toJson() => {
    'heardMs': heardMilliseconds,
    'acceptedMs': transportAcceptedMilliseconds,
    'unconfirmedMs': unconfirmedMilliseconds,
  };

  static QishuiListeningLedger parse(Object? value) {
    final map = sodaMap(value);
    int read(String name) {
      final value = map[name];
      if (value == null) return 0;
      if (value is! int || value < 0) {
        throw const QishuiException('本机汽水时长记录格式异常，原记录已保留');
      }
      return value;
    }

    return QishuiListeningLedger(
      heardMilliseconds: read('heardMs'),
      transportAcceptedMilliseconds: read('acceptedMs'),
      unconfirmedMilliseconds: read('unconfirmedMs'),
    );
  }
}

abstract interface class QishuiListeningStore {
  Future<QishuiListeningLedger> read(String owner);
  Future<void> write(String owner, QishuiListeningLedger value);
}

/// Stores only aggregate counters under an opaque account key. It is not a
/// durable replay queue: no old events, tracks, cookies or request bodies are
/// restored and no listening is uploaded merely by opening the application.
class PreferencesQishuiListeningStore implements QishuiListeningStore {
  String _key(String owner) =>
      'mesting_qishui_listening177_${sha256.convert(utf8.encode(owner))}';

  @override
  Future<QishuiListeningLedger> read(String owner) async {
    final raw = (await SharedPreferences.getInstance()).getString(_key(owner));
    if (raw == null) return const QishuiListeningLedger();
    try {
      return QishuiListeningLedger.parse(jsonDecode(raw));
    } on FormatException {
      throw const QishuiException('本机汽水时长记录暂不能读取，原记录已保留');
    }
  }

  @override
  Future<void> write(String owner, QishuiListeningLedger value) async {
    if (!await (await SharedPreferences.getInstance()).setString(
      _key(owner),
      jsonEncode(value.toJson()),
    )) {
      throw const QishuiException('本次汽水时长暂未保存，请稍后核对');
    }
  }
}

class QishuiListeningEvent {
  const QishuiListeningEvent(this.name, this.params, this.time);
  final String name;
  final Map<String, Object> params;
  final DateTime time;

  Map<String, Object> toJson() => {
    'event': name,
    'params': jsonEncode(params),
    'time': time.millisecondsSinceEpoch ~/ 1000,
  };
}

enum QishuiListeningDelivery { accepted, unconfirmed, localOnly }

class QishuiListeningRepository {
  QishuiListeningRepository({
    required this.api,
    required bool Function() current,
    QishuiListeningStore? store,
    this.reportEnabled = true,
    DateTime Function()? now,
  }) : _current = current,
       owner = api.session?.userId ?? '',
       credential = api.credential,
       store = store ?? PreferencesQishuiListeningStore(),
       _now = now ?? DateTime.now;

  final QishuiApi api;
  final bool Function() _current;
  final String owner;
  final String? credential;
  final QishuiListeningStore store;
  final bool reportEnabled;
  final DateTime Function() _now;
  final _abort = Completer<void>();
  QishuiListeningLedger? _ledger;
  Future<QishuiListeningLedger>? _loadingLedger;
  Future<void> _tail = Future.value();

  bool get current =>
      !_abort.isCompleted &&
      owner.isNotEmpty &&
      api.session?.userId == owner &&
      api.credential == credential &&
      _current();

  void _guard() {
    if (!current) {
      throw const QishuiException(
        '汽水账号已变化，时长操作已取消',
        kind: QishuiFailureKind.cancelled,
      );
    }
  }

  Future<void> _cancel(Future<void>? other) =>
      other == null ? _abort.future : Future.any<void>([_abort.future, other]);

  Future<QishuiListeningSnapshot> fetch({Future<void>? abortTrigger}) async {
    _guard();
    final response = await api.request(
      '/luna/me/music_wall',
      body: const {'feed_music_wall_extra': <String, Object>{}, 'ab_param': ''},
      expectedCredential: credential,
      abortTrigger: _cancel(abortTrigger),
    );
    _guard();
    return QishuiListeningSnapshot.parse(response, fetchedAt: _now());
  }

  Future<QishuiListeningLedger> ledger() {
    final existing = _ledger;
    if (existing != null) return Future.value(existing);
    // UI restoration and the first playback segment may read concurrently.
    // Share one read and never let a late disk value replace a newer write.
    return _loadingLedger ??= store
        .read(owner)
        .then((value) {
          return _ledger ??= value;
        })
        .whenComplete(() => _loadingLedger = null);
  }

  /// Identity-bearing PC applog envelope, retained in the pinned PC reporting
  /// reference. Android DEX independently establishes audio event names and ms
  /// duration. This adapter must still be verified against the live PC account
  /// service; neither a fixture nor HTTP 200 establishes official total credit.
  /// No fabricated fallback did or credentials are accepted here.
  static Map<String, Object> eventBody({
    required Map<String, String> identity,
    required String owner,
    required List<QishuiListeningEvent> events,
    required bool playing,
  }) {
    final did = identity['device_id'] ?? '';
    final ua = identity['user_agent'] ?? '';
    final version = RegExp(r'^LunaPC/(\d+\.\d+\.\d+)\(\d+\)$').firstMatch(ua);
    if (!RegExp(r'^\d{1,30}$').hasMatch(did) ||
        !RegExp(r'^\d{1,30}$').hasMatch(owner) ||
        version == null) {
      throw const QishuiException('汽水听歌上报缺少可核对的账号和设备身份');
    }
    return {
      'caller': 'luna.desktop.client',
      'user': {
        'user_unique_id': did,
        'user_type': 12,
        'user_id': owner,
        'user_is_auth': true,
        'user_is_login': true,
        'device_id': did,
      },
      'header': {
        'app_id': '386088',
        'app_version': version[1]!,
        'custom': jsonEncode({
          'is_playing': playing ? 1 : 0,
          'user_login_status': 1,
        }),
      },
      'events': [for (final event in events) event.toJson()],
    };
  }

  Future<QishuiListeningDelivery> submit(
    List<QishuiListeningEvent> events, {
    required int heardMilliseconds,
    required bool playing,
  }) {
    final result = _tail.then((_) async {
      if (owner.isEmpty ||
          heardMilliseconds < 0 ||
          events.isEmpty ||
          events.length > 3) {
        throw const QishuiException('汽水听歌上报事件无效');
      }
      var previous = await ledger();
      // Settle local accounting before the first possible remote dispatch.
      // An interrupted request is uncertain and deliberately never replayed.
      if (heardMilliseconds > 0) {
        previous = QishuiListeningLedger(
          heardMilliseconds: previous.heardMilliseconds + heardMilliseconds,
          transportAcceptedMilliseconds: previous.transportAcceptedMilliseconds,
          unconfirmedMilliseconds:
              previous.unconfirmedMilliseconds + heardMilliseconds,
        );
        await store.write(owner, previous);
        _ledger = previous;
      }
      if (!current) return QishuiListeningDelivery.unconfirmed;
      if (!reportEnabled) return QishuiListeningDelivery.localOnly;
      try {
        final signer = api.signer;
        if (signer == null) {
          throw const QishuiException('汽水听歌上报设备身份尚未就绪');
        }
        final identity = await signer.identity(_abort.future);
        _guard();
        final body = jsonEncode(
          eventBody(
            identity: identity,
            owner: owner,
            events: events,
            playing: playing,
          ),
        );
        final response = await sendMusicRequest(
          client: api.client,
          platform: 'qishui',
          operation: MusicNetworkOperation.read,
          maximumResponseBytes: 65536,
          timeout: const Duration(seconds: 12),
          abortTrigger: _abort.future,
          retryRead: false,
          build: (cancel) =>
              http.AbortableRequest(
                  'POST',
                  Uri.https('mcs.zijieapi.com', '/v1/json'),
                  abortTrigger: cancel,
                )
                ..followRedirects = false
                ..headers.addAll({
                  'content-type': 'application/json; charset=utf-8',
                  'x-ss-stub': md5
                      .convert(utf8.encode(body))
                      .toString()
                      .toUpperCase(),
                })
                ..body = body,
        );
        _guard();
        if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
          return QishuiListeningDelivery.unconfirmed;
        }
        final reply = sodaMap(jsonDecode(utf8.decode(response.bodyBytes)));
        // An HTTP success without an explicit positive service receipt is
        // uncertain, including empty JSON. Never guess a zero success code.
        final accepted =
            reply['success'] != false &&
            reply['error'] == null &&
            (reply['code'] == null || reply['code'] == 0) &&
            (reply['status_code'] == null || reply['status_code'] == 0) &&
            (reply['message'] == null || reply['message'] == 'success') &&
            (reply['message'] == 'success' ||
                reply['code'] == 0 ||
                reply['status_code'] == 0);
        if (!accepted) return QishuiListeningDelivery.unconfirmed;
        if (heardMilliseconds > 0) {
          final updated = QishuiListeningLedger(
            heardMilliseconds: previous.heardMilliseconds,
            transportAcceptedMilliseconds:
                previous.transportAcceptedMilliseconds + heardMilliseconds,
            unconfirmedMilliseconds:
                previous.unconfirmedMilliseconds - heardMilliseconds,
          );
          await store.write(owner, updated);
          _ledger = updated;
        }
        return QishuiListeningDelivery.accepted;
      } on Object {
        // No old event is retained for a second attempt. Current local heard
        // time remains available even if the network or account has changed.
        return QishuiListeningDelivery.unconfirmed;
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// On account teardown only persist the final already-heard interval under
  /// its captured old owner. This path is local and can never dispatch HTTP.
  Future<void> rememberUnsent(int heardMilliseconds) async {
    if (heardMilliseconds <= 0 || owner.isEmpty) return;
    final result = _tail.then((_) async {
      final previous = await ledger();
      final updated = QishuiListeningLedger(
        heardMilliseconds: previous.heardMilliseconds + heardMilliseconds,
        transportAcceptedMilliseconds: previous.transportAcceptedMilliseconds,
        unconfirmedMilliseconds:
            previous.unconfirmedMilliseconds + heardMilliseconds,
      );
      await store.write(owner, updated);
      _ledger = updated;
    });
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    await result;
  }

  void dispose() {
    if (!_abort.isCompleted) _abort.complete();
  }
}
