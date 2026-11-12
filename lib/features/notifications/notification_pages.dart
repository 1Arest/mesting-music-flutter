import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../shared/widgets/beta_glass_controls.dart';
import '../../shared/widgets/beta_glass_scroll_body.dart';
import '../../shared/widgets/beta_page_motion.dart';
import '../../shared/widgets/beta_selection_controls.dart';
import '../music_platform/domain/platform_session.dart';
import 'notification_bridge.dart';
import 'notification_coordinator.dart';
import 'notification_models.dart';
import 'notification_runner.dart';

/// Notification preferences share the existing Apple scope. Native Android
/// remains authoritative for permission/channel opt-outs and persisted choices.
class MusicNotificationSettingsPage extends StatefulWidget {
  const MusicNotificationSettingsPage({
    this.bridge = const MusicNotificationBridge(),
    super.key,
  });
  final MusicNotificationBridge bridge;
  @override
  State<MusicNotificationSettingsPage> createState() =>
      _NotificationSettingsState();
}

class _NotificationSettingsState extends State<MusicNotificationSettingsPage> {
  Map<String, dynamic> snapshot = {}, settings = {};
  bool loading = true, busy = false, permission = false, scheduled = false;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
    musicNoticeRevision.addListener(_reload);
  }

  void _reload() => unawaited(_load());
  Future<void> _load() async {
    final state = await widget.bridge.state();
    if (!mounted) return;
    setState(() {
      snapshot = noticeMap(state['json']);
      settings = noticeMap(snapshot['settings']);
      permission = state['permission'] == true;
      scheduled = state['scheduled'] == true;
      loading = false;
    });
  }

  Future<void> _set(String key, bool value) async {
    setState(() => busy = true);
    try {
      await widget.bridge.call<void>('settings', {
        'values': {key: value},
      });
      await _load();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _switch(String key, String title, {String? subtitle}) =>
      BetaSwitchTile(
        value: settings[key] != false,
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        onChanged: busy ? null : (value) => _set(key, value),
      );
  Widget _group(List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 20),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(children: children),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('消息与通知')),
    body: _NoticePageBody(
      child: loading
          ? const Center(child: CupertinoActivityIndicator())
          : BetaGlassScrollBody(
              padding: const EdgeInsets.all(20),
              children: [
                _group([
                  _switch('enabled', '消息提醒', subtitle: '同时检查两个已登录平台，与当前页面平台无关'),
                ]),
                if (!permission)
                  _group([
                    const ListTile(
                      leading: Icon(CupertinoIcons.bell_slash),
                      title: Text('系统通知尚未开启'),
                      subtitle: Text('允许通知后，才能在通知栏看到消息提醒。'),
                    ),
                    BetaGlassButton(
                      blue: true,
                      onPressed: () async {
                        await widget.bridge.call<bool>('permission');
                        await _load();
                        if (!permission) {
                          await widget.bridge.call<bool>('systemSettings');
                        }
                      },
                      child: const Text('开启系统通知'),
                    ),
                    const SizedBox(height: 16),
                  ]),
                for (final platform in noticePlatforms) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                    child: Text(
                      platform.label,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _group([
                    _switch(platform.name, '${platform.label}通知'),
                    for (final kind in MusicNoticeKind.values)
                      _switch('${platform.name}:${kind.name}', kind.label),
                  ]),
                ],
                _group([
                  ListTile(
                    leading: const Icon(CupertinoIcons.clock),
                    title: Text(scheduled ? '后台定期检查已安排' : '后台检查尚未安排'),
                    subtitle: const Text(
                      '有账号登录、允许通知并开启提醒后生效。后台由系统约每 15 分钟检查；省电限制或强行停止可能延后或暂停。',
                    ),
                  ),
                  ListTile(
                    leading: const Icon(CupertinoIcons.bell),
                    title: const Text('提醒记录'),
                    trailing: const Icon(
                      CupertinoIcons.chevron_right,
                      size: 18,
                    ),
                    onTap: () => Navigator.of(context).push(
                      betaContentRoute<void>(
                        const MusicNotificationInboxPage(),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(CupertinoIcons.gear),
                    title: const Text('系统通知设置'),
                    trailing: const Icon(
                      CupertinoIcons.chevron_right,
                      size: 18,
                    ),
                    onTap: () => widget.bridge.call<bool>('systemSettings'),
                  ),
                ]),
                if (noticeMap(snapshot['errors']).isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('部分消息暂未读取成功，已保留上次记录。登录失效时，请重新登录对应平台后再检查。'),
                  ),
                BetaGlassButton(
                  blue: true,
                  onPressed: busy
                      ? null
                      : () async {
                          setState(() => busy = true);
                          try {
                            await MusicNoticeRunner(
                              bridge: widget.bridge,
                            ).poll();
                            await _load();
                          } finally {
                            if (mounted) setState(() => busy = false);
                          }
                        },
                  child: Text(busy ? '正在检查…' : '现在检查'),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 16, 8, 24),
                  child: Text(
                    '首次开启先建立记录，不补发历史消息。私信与互动来自平台消息；音乐推荐和关注歌手新作品根据平台内容更新提醒。',
                  ),
                ),
              ],
            ),
    ),
  );
  @override
  void dispose() {
    musicNoticeRevision.removeListener(_reload);
    super.dispose();
  }
}

class MusicNotificationInboxPage extends StatefulWidget {
  const MusicNotificationInboxPage({
    this.platform,
    this.noticeId,
    this.bridge = const MusicNotificationBridge(),
    super.key,
  });
  final String? platform, noticeId;
  final MusicNotificationBridge bridge;
  @override
  State<MusicNotificationInboxPage> createState() => _NoticeInboxState();
}

class _NoticeInboxState extends State<MusicNotificationInboxPage> {
  List<Map<String, dynamic>> rows = [];
  bool loading = true;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
    musicNoticeRevision.addListener(_reload);
  }

  void _reload() => unawaited(_load());
  Future<void> _load() async {
    final raw = await widget.bridge.state();
    final state = noticeMap(raw['json']);
    final values =
        noticeRows(state['inbox'])
            .where(
              (r) =>
                  widget.platform == null || r['platform'] == widget.platform,
            )
            .toList()
          ..sort(
            (a, b) => ((b['time'] as num?)?.toInt() ?? 0).compareTo(
              (a['time'] as num?)?.toInt() ?? 0,
            ),
          );
    if (mounted) {
      setState(() {
        rows = values;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('消息提醒')),
    body: _NoticePageBody(
      child: loading
          ? const Center(child: CupertinoActivityIndicator())
          : rows.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  '暂时没有提醒记录\n开启系统通知后，会在检查到消息时更新。',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : BetaGlassScrollBody(
              padding: const EdgeInsets.all(20),
              children: [
                for (final row in rows)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(22),
                      border: row['id'] == widget.noticeId
                          ? Border.all(
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : null,
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      leading: Icon(
                        row['kind'] == 'privateMessage'
                            ? CupertinoIcons.chat_bubble
                            : CupertinoIcons.bell,
                      ),
                      title: Text(
                        '${row['platform'] == 'netease' ? '网易云' : '酷狗'} · ${noticeText(row['title'], 80)}',
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(noticeText(row['body'], 500)),
                      ),
                    ),
                  ),
              ],
            ),
    ),
  );
  @override
  void dispose() {
    musicNoticeRevision.removeListener(_reload);
    super.dispose();
  }
}

/// iPad keeps grouped settings at a readable width, while phones use the full
/// safe area. The scroll view owns a single vertical gesture surface.
class _NoticePageBody extends StatelessWidget {
  const _NoticePageBody({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: child,
      ),
    ),
  );
}
