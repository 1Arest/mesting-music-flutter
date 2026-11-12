import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/security/credential_mutation_signal.dart';
import '../music_platform/domain/platform_session.dart';
import 'notification_bridge.dart';
import 'notification_models.dart';
import 'notification_sources.dart';

const noticePlatforms = [MusicPlatform.netease, MusicPlatform.kugou];

/// Both entry points use the same runner. The native lease prevents duplicate
/// front/background polls; generation and fresh encrypted reads reject results
/// from a logout, account switch, or settings change while a request was pending.
class MusicNoticeRunner {
  MusicNoticeRunner({
    this.bridge = const MusicNotificationBridge(),
    Future<NoticeAccount?> Function(MusicPlatform)? readAccount,
    NoticeSourceBundle Function(NoticeAccount, String)? sourceFactory,
  }) : readAccount = readAccount ?? readNoticeAccount,
       sourceFactory =
           sourceFactory ??
           ((account, machine) => NoticeSources(account, machine: machine));
  final MusicNotificationBridge bridge;
  final Future<NoticeAccount?> Function(MusicPlatform) readAccount;
  final NoticeSourceBundle Function(NoticeAccount, String) sourceFactory;

  static void installCredentialGuard() {
    CredentialMutationSignal.beforeMutation = (key) async {
      final platform = key.contains('netease')
          ? 'netease'
          : key.contains('kugou')
          ? 'kugou'
          : null;
      if (platform == null) return;
      try {
        await const MusicNotificationBridge().call<void>('invalidate', {
          'platform': platform,
        });
      } on Object {
        /* Secure account operations must still work if notifications detach. */
      }
    };
  }

  Future<void> poll() async {
    if (!bridge.supported) return;
    final status = await bridge.state();
    if (noticeMap(noticeMap(status['json'])['settings'])['enabled'] == false ||
        status['permission'] == false) {
      return;
    }
    final accounts = <MusicPlatform, NoticeAccount?>{};
    for (final platform in noticePlatforms) {
      try {
        accounts[platform] = await readAccount(platform);
      } on Object {
        await _error(platform, 'account');
      }
    }
    await bridge.call<void>('bind', {
      'owners': {
        for (final entry in accounts.entries)
          entry.key.name: entry.value?.scope ?? '',
      },
    });
    final claim = await bridge.call<Map>('begin');
    if (claim == null) return;
    final state = noticeMap(claim['json']);
    final settings = noticeMap(state['settings']);
    final feeds = noticeMap(state['feeds']);
    final device = await bridge.state();
    try {
      await Future.wait([
        for (final account in accounts.values)
          if (account != null && settings[account.platform.name] != false)
            _account(
              account,
              settings,
              feeds,
              claim,
              '${device['machine'] ?? 'Android'}',
            ),
      ]);
    } finally {
      await bridge.call<void>('release', {'lease': claim['lease']});
    }
  }

  Future<void> _account(
    NoticeAccount account,
    Map<String, dynamic> settings,
    Map<String, dynamic> feeds,
    Map claim,
    String machine,
  ) async {
    final sources = sourceFactory(account, machine);
    final pending = sources
        .build()
        .where(
          (source) =>
              source.kind == null ||
              settings['${account.platform.name}:${source.kind!.name}'] !=
                  false,
        )
        .toList();
    var index = 0, abandoned = false;
    Future<void> worker() async {
      while (!abandoned && index < pending.length) {
        final source = pending[index++];
        try {
          if ((await readAccount(account.platform))?.scope != account.scope) {
            abandoned = true;
            return;
          }
          final previous = noticeMap(feeds['${account.scope}|${source.key}']);
          final feed = await source
              .load('${previous['cursor'] ?? ''}')
              .timeout(const Duration(seconds: 22));
          if ((await readAccount(account.platform))?.scope != account.scope) {
            abandoned = true;
            return;
          }
          final diff = NoticeDiff.apply(feed, previous);
          final accepted = await bridge.call<bool>('commit', {
            'lease': claim['lease'],
            'generation': claim['generation'],
            'platform': account.platform.name,
            'scope': account.scope,
            'feed': source.key,
            'state': jsonEncode(diff.state),
            'events': feed.events.map((e) => e.toJson()).toList(),
            'fresh': diff.fresh.map((e) => e.toJson()).toList(),
          });
          if (accepted != true) {
            abandoned = true;
            return;
          }
        } on Object {
          await _error(account.platform, source.key);
        }
      }
    }

    try {
      // Two bounded workers prevent one failed feed from starving artist and
      // recommendation checks within Android's short job execution window.
      await Future.wait([worker(), worker()]);
    } finally {
      sources.close();
    }
  }

  Future<void> _error(MusicPlatform platform, String feed) =>
      bridge.call<void>('error', {'platform': platform.name, 'feed': feed});
}

/// This is called by main.dart's retained entry point. It initializes protocol
/// plugins only: no application widget tree, database, audio player or login UI.
Future<void> runBackgroundNotices() async {
  MusicNoticeRunner.installCredentialGuard();
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('mesting_disclaimer_accepted_v1') != true) return;
    await MusicNoticeRunner().poll().timeout(const Duration(seconds: 80));
  } on Object {
    /* Keep cursors intact and let the next system job retry. */
  } finally {
    await const MusicNotificationBridge().call<void>('finished');
  }
}
