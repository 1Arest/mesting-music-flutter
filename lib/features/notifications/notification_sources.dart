import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/network/music_http_client.dart';
import '../../core/security/retained_credential_vault.dart';
import '../../core/security/retained_secure_storage.dart';
import '../music_platform/data/embedded_music_server.dart';
import '../music_platform/data/kugou_account_store.dart';
import '../music_platform/data/music_platform_api.dart';
import '../music_platform/domain/platform_session.dart';
import '../music_platform/netease/netease_api.dart';
import '../music_platform/netease/netease_session.dart';
import '../music_platform/netease/netease_music_repository.dart';
import '../music_platform/netease/messages/netease_messages_repository.dart';
import 'notification_models.dart';

class NoticeAccount {
  NoticeAccount(this.identity, {this.netease})
    : scope = sha256
          .convert(
            utf8.encode(
              '${identity.ownerId}\n${identity.token}\n${identity.kugouStandardToken}',
            ),
          )
          .toString();
  final PlatformSession identity;
  final NeteaseSession? netease;
  final String scope;
  MusicPlatform get platform => identity.platform;
}

/// Never selects a visible platform or migrates/writes the secure store. Each
/// call reopens durable storage, including the final check before publication.
Future<NoticeAccount?> readNoticeAccount(MusicPlatform platform) async {
  if (platform == MusicPlatform.kugou) {
    final session = await SecureKugouAccountStore().readRetained();
    return session == null ? null : NoticeAccount(session);
  }
  if (platform != MusicPlatform.netease) return null;
  final raw = await RetainedCredentialVault(
    retainedSecureStorage,
  ).readFresh(SecureNeteaseSessionStore.key);
  if (raw == null) return null;
  final session = NeteaseSession.fromJson(
    jsonDecode(raw) as Map<String, dynamic>,
  );
  return NoticeAccount(session.identity, netease: session);
}

class NoticeSource {
  const NoticeSource(this.key, this.load, {this.kind});
  final String key;
  final MusicNoticeKind? kind;
  final Future<NoticeFeed> Function(String cursor) load;
}

/// Polling transports are short-lived and account-owned. Existing embedded
/// protocols supply music recommendations; message polling has no read receipt,
/// subscription write, device registration, or background playback side effect.
abstract interface class NoticeSourceBundle {
  List<NoticeSource> build();
  void close();
}

class NoticeSources implements NoticeSourceBundle {
  NoticeSources(
    this.account, {
    required this.machine,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final NoticeAccount account;
  final String machine;
  final DateTime Function() clock;
  final client = MusicHttpClient();
  @override
  void close() => client.close();

  @override
  List<NoticeSource> build() =>
      account.platform == MusicPlatform.netease ? _netease() : _kugou();

  List<NoticeSource> _netease() {
    final api = NeteaseApi(client)..configure(account.netease);
    final music = NeteaseMusicRepository(api);
    final messages = NeteaseMessagesRepository(music);
    return [
      NoticeSource('private', (_) async {
        final rows = await messages.conversations();
        return NoticeFeed('private', [
          for (final row in rows)
            if (row.unread > 0 && row.last.from.id != account.identity.userId)
              MusicNotice(
                id: 'private:${row.peer.id}:${row.last.id}:${row.last.time.millisecondsSinceEpoch}',
                platform: account.platform,
                kind: MusicNoticeKind.privateMessage,
                title: noticeText(row.peer.name, 60),
                body: noticeText(row.last.text),
                time: row.last.time.millisecondsSinceEpoch,
                peer: row.peer.id,
              ),
        ]);
      }, kind: MusicNoticeKind.privateMessage),
      for (final kind in NeteaseNoticeKind.values)
        NoticeSource(
          'interaction:${kind.name}',
          (_) async => NoticeFeed('interaction:${kind.name}', [
            for (final row in await messages.notices(kind))
              MusicNotice(
                id: 'interaction:${kind.name}:${row.id}:${row.time.millisecondsSinceEpoch}',
                platform: account.platform,
                kind: MusicNoticeKind.interaction,
                title: kind == NeteaseNoticeKind.fans ? '有新的关注' : '有新的互动',
                body: noticeText('${row.person.name} ${row.text}'),
                time: row.time.millisecondsSinceEpoch,
              ),
          ]),
          kind: MusicNoticeKind.interaction,
        ),
      NoticeSource('artist', (_) async {
        final response = await api.call(
          '/artist/new/song',
          query: {'limit': 30},
        );
        final data = noticeMap(response['data']);
        final rows = sourceRows(data['newWorks'] ?? response['data']);
        final songs = [
          for (final row in rows)
            if (row['songLists'] is List)
              ...noticeRows(row['songLists'])
            else
              row,
        ];
        return NoticeFeed('artist', [
          for (final row in songs)
            if ('${row['id'] ?? ''}'.isNotEmpty)
              MusicNotice(
                id: 'artist:${row['id']}',
                platform: account.platform,
                kind: MusicNoticeKind.artist,
                title: '关注歌手有新作品',
                body: noticeText('${_artists(row)} · ${row['name'] ?? '新作品'}'),
                time: _milliseconds(row['publishTime']),
              ),
        ]);
      }, kind: MusicNoticeKind.artist),
      NoticeSource('daily', (_) async {
        final songs = await music.daily();
        return _daily(
          'daily',
          songs.map((s) => '${s.artist} · ${s.title}').toList(),
        );
      }, kind: MusicNoticeKind.recommendation),
    ];
  }

  List<NoticeSource> _kugou() {
    final api = MusicPlatformApi(server: EmbeddedMusicServer(), client: client)
      ..session = account.identity;
    return [
      // Official 20.8.8 MsgPullProtocol uses sync/poll + opaque `s`, separate
      // from MsgReadProtocol. Messages stay unread on the upstream platform.
      NoticeSource('messages', (cursor) async {
        final directory = await getApplicationSupportDirectory();
        final file = File(
          '${directory.path}/music_platform/runtime/device_info.json',
        );
        if (!await file.exists() || await file.length() > 16384) {
          throw const FormatException('Registered device unavailable');
        }
        final device = noticeMap(jsonDecode(await file.readAsString()));
        final query = kugouNoticeParameters(
          account.identity,
          device,
          machine,
          clock(),
        );
        final body = jsonEncode({'s': cursor});
        query['signature'] = kugouNoticeSignature(
          account.identity,
          query,
          body,
        );
        final response = await client
            .post(
              // The legacy host's current HTTPS certificate does not match it.
              // Use the official gateway host-routing path with normal TLS checks.
              Uri.https('gateway.kugou.com', '/msg.mobile/v3/sync/poll', query),
              headers: {
                'Content-Type': 'application/json;charset=utf-8',
                'Accept': 'application/json',
              },
              body: body,
            )
            .timeout(const Duration(seconds: 18));
        if (response.statusCode != 200) {
          throw const FormatException('Message transport unavailable');
        }
        return parseKugouNoticePoll(
          noticeMap(jsonDecode(utf8.decode(response.bodyBytes))),
          account.platform,
        );
      }),
      NoticeSource('artist', (_) async {
        final response = await api.get(
          '/artist/follow/newsongs',
          query: {'pagesize': '30'},
        );
        final rows = sourceRows(response['data']);
        return NoticeFeed('artist', [
          for (final row in rows)
            if ('${row['album_id'] ?? row['albumid'] ?? row['id'] ?? ''}'
                .isNotEmpty)
              MusicNotice(
                id: 'artist:${row['album_id'] ?? row['albumid'] ?? row['id']}',
                platform: account.platform,
                kind: MusicNoticeKind.artist,
                title: '关注歌手有新作品',
                body: noticeText(
                  '${row['singername'] ?? row['singer_name'] ?? ''} · ${row['album_name'] ?? row['albumname'] ?? row['name'] ?? '新作品'}',
                ),
                time: _milliseconds(row['publish_time'] ?? row['addtime']),
              ),
        ]);
      }, kind: MusicNoticeKind.artist),
      NoticeSource('daily', (_) async {
        final response = await api.get('/recommend/songs');
        final rows = sourceRows(response['data']);
        return _daily(
          'daily',
          [
            for (final row in rows)
              noticeText(row['filename'] ?? row['songname'] ?? row['name']),
          ].where((s) => s.isNotEmpty).toList(),
        );
      }, kind: MusicNoticeKind.recommendation),
    ];
  }

  NoticeFeed _daily(String key, List<String> titles) {
    final now = clock();
    final date = '${now.year}-${now.month}-${now.day}';
    return NoticeFeed(
      key,
      titles.isEmpty
          ? const []
          : [
              MusicNotice(
                id: 'daily:$date',
                platform: account.platform,
                kind: MusicNoticeKind.recommendation,
                title: '今天的音乐推荐已更新',
                body: noticeText(titles.take(4).join('、')),
                time: now.millisecondsSinceEpoch,
              ),
            ],
    );
  }
}

List<Map<String, dynamic>> sourceRows(Object? value) {
  if (value is List) return noticeRows(value);
  final map = noticeMap(value);
  for (final key in [
    'list',
    'lists',
    'songs',
    'song_list',
    'songlist',
    'info',
    'data',
  ]) {
    if (map[key] is List) return noticeRows(map[key]);
    if (map[key] is Map && key == 'data') return sourceRows(map[key]);
  }
  throw const FormatException('Unknown notification feed shape');
}

String _artists(Map<String, dynamic> row) => noticeRows(
  row['ar'] ?? row['artists'],
).map((a) => noticeText(a['name'], 50)).join(' / ');

int _milliseconds(Object? raw) {
  final value = int.tryParse('$raw') ?? 0;
  return value > 0 && value < 100000000000 ? value * 1000 : value;
}

/// Match the actual retained authorization. A Lite login is never relabelled
/// as a standard-client login. The public protocol salts match the embedded
/// md3Music helpers; upstream acceptance still needs account/device validation.
Map<String, String> kugouNoticeParameters(
  PlatformSession owner,
  Map<String, dynamic> device,
  String machine,
  DateTime now,
) {
  final values = {
    for (final key in ['mid', 'uuid', 'dfid']) key: '${device[key] ?? ''}',
  };
  if (values.values.any((s) => s.isEmpty || s == '-')) {
    throw const FormatException('Incomplete registered device');
  }
  return {
    ...values,
    'userid': owner.userId,
    'token': owner.kugouOfficialToken,
    'appid': '${owner.kugouAppId}',
    'clientver': '${owner.kugouClientVersion}',
    'clienttime': '${now.millisecondsSinceEpoch ~/ 1000}',
    'utype': '0',
    'machine': machine,
  };
}

String kugouNoticeSignature(
  PlatformSession owner,
  Map<String, String> query,
  String body,
) {
  final salt = owner.kugouAppId == 1005
      ? 'OIlwieks28dk2k092lksi2UIkp'
      : 'LnT6xpN3khm36zse0QzvmgTZ3waWdRSA';
  final keys = query.keys.where((k) => k != 'signature').toList()..sort();
  return md5
      .convert(
        utf8.encode(
          '$salt${keys.map((k) => '$k=${query[k]}').join()}$body$salt',
        ),
      )
      .toString();
}

NoticeFeed parseKugouNoticePoll(
  Map<String, dynamic> response,
  MusicPlatform platform,
) {
  if (response['status'] != 1 ||
      response['list'] is! List ||
      response['s'] is! String) {
    throw const FormatException('Message response not confirmed');
  }
  return NoticeFeed('messages', [
    for (final row in noticeRows(response['list'])) ?_kugouEvent(row, platform),
  ], cursor: response['s'] as String);
}

MusicNotice? _kugouEvent(Map<String, dynamic> row, MusicPlatform platform) {
  if ([6, 7].contains(row['type'])) return null;
  if (row['platform'] != null &&
      row['platform'] != '' &&
      row['platform'] != 'android') {
    return null;
  }
  final md = '${row['md'] ?? ''}';
  if (md.isNotEmpty && md != 'listen') return null;
  final message = noticeMap(row['message']);
  if ((int.tryParse('${message['msgtype']}') ?? 0) < 0) return null;
  final id = '${row['msgid'] ?? ''}';
  if (id.isEmpty || id == '0' || message.isEmpty) return null;
  final tag = '${row['tag'] ?? ''}';
  // The server's explicit category is preferred. Chat tags are independently
  // identifiable; unknown music notices remain visible as general interaction.
  final kind = switch ('${message['category'] ?? row['category'] ?? ''}') {
    'artist' || 'artist_dynamic' => MusicNoticeKind.artist,
    'recommend' || 'new_song' => MusicNoticeKind.recommendation,
    _ when tag.contains('CHAT:') && tag != '___CHAT:FANS___' =>
      MusicNoticeKind.privateMessage,
    _ => MusicNoticeKind.interaction,
  };
  final content = noticeMap(message['content']);
  final title = noticeText(
    message['title'] ?? content['title'] ?? kind.label,
    60,
  );
  final body = _messageBody(message);
  return MusicNotice(
    id: 'message:$id',
    platform: platform,
    kind: kind,
    title: title,
    body: body.isEmpty ? '收到一条新消息' : body,
    time: _milliseconds(row['addtime']),
    peer: '${row['uid'] ?? ''}',
  );
}

/// Display message content, never a raw JSON envelope or its metadata fields.
String _messageBody(Object? value, [int depth = 0]) {
  if (depth > 4 || value == null) return '';
  if (value is String) {
    final decoded = noticeMap(value);
    if (decoded.isNotEmpty) return _messageBody(decoded, depth + 1);
    return noticeText(value);
  }
  final map = noticeMap(value);
  for (final key in ['text', 'msg', 'content', 'message', 'description']) {
    final body = _messageBody(map[key], depth + 1);
    if (body.isNotEmpty) return body;
  }
  return '';
}
