import '../../../shared/widgets/music_feature_page.dart';
import 'qishui_page_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/persistence/app_preferences.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/music_activity_indicator.dart';
import 'qishui_api.dart';
import 'qishui_models.dart';
import 'qishui_providers.dart';
import 'qishui_repository.dart';

/// Account/date-scoped activity journal. A submitted or uncertain write is
/// never replayed automatically, including after a process restart.
String qishuiClaimJournalKey(String uid, String day) =>
    'qishui_activity_claim_v1_${Uri.encodeComponent(uid)}_$day';

class QishuiWelfareStatus {
  QishuiWelfareStatus(this.payload);
  final Map<String, dynamic> payload;
  int get _serverMillis =>
      sodaInt(sodaMap(payload['status_info'])['now_ts_ms']);
  Map<String, dynamic> get activity => sodaMap(payload['activity_free_vip']);
  Map<String, dynamic> get membership => sodaMap(payload['membership']);
  Map<String, dynamic> get listening => sodaMap(payload['play_entitlements']);
  DateTime get serverNow => DateTime.fromMillisecondsSinceEpoch(
    sodaInt(sodaMap(payload['status_info'])['now_ts_ms']) > 0
        ? sodaInt(sodaMap(payload['status_info'])['now_ts_ms'])
        : DateTime.now().millisecondsSinceEpoch,
    isUtc: true,
  );
  String get day => serverNow
      .add(const Duration(hours: 8))
      .toIso8601String()
      .substring(0, 10);
  bool get claimed =>
      activity['latest_apply_date'] == day ||
      sodaRows(
        activity['calendar_dates'],
      ).any((v) => v['date'] == day && v['status'] == 8);
  bool get active =>
      sodaInt(activity['start_time_sec']) > 0 &&
      sodaInt(activity['start_time_sec']) * 1000 <=
          serverNow.millisecondsSinceEpoch &&
      sodaInt(activity['end_time_sec']) * 1000 >
          serverNow.millisecondsSinceEpoch;
  bool get claimable =>
      _serverMillis > 0 &&
      active &&
      !claimed &&
      sodaMap(sodaMap(payload['treasure'])['config'])['entrance_authorize'] !=
          false;
}

class QishuiWelfarePage extends ConsumerStatefulWidget {
  const QishuiWelfarePage({super.key});
  @override
  ConsumerState<QishuiWelfarePage> createState() => _QishuiWelfarePageState();
}

class _QishuiWelfarePageState extends ConsumerState<QishuiWelfarePage>
    with QishuiOwnedPage<QishuiWelfarePage> {
  late final QishuiRepository _music = ref.read(qishuiRepositoryProvider);
  late Future<QishuiWelfareStatus> _status = _read();
  bool _busy = false;
  String? _message;
  Future<QishuiWelfareStatus> _read() async =>
      QishuiWelfareStatus(await _music.commerce(abortTrigger: pageAbort));
  Future<void> _claim(QishuiWelfareStatus before) async {
    if (_busy || !_music.current || !before.claimable) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      // Re-read qualification and the server date at the actual user action.
      // A calendar left open overnight cannot submit yesterday's entitlement.
      final fresh = await _read();
      if (!ownerCurrent || !_music.current) return;
      if (fresh.day != before.day || !fresh.claimable) {
        setState(() {
          _status = Future.value(fresh);
          _message = '领取资格已变化，请核对当前权益后再操作';
        });
        return;
      }
      final preferences = ref.read(sharedPreferencesProvider);
      final key = qishuiClaimJournalKey(_music.api.session!.userId, fresh.day);
      if (preferences.containsKey(key)) {
        setState(() => _message = '今天已有领取记录，请刷新权益核对；不会重复提交。');
        return;
      }
      // Persist BEFORE dispatch. Failure to journal means no remote write.
      if (!await preferences.setString(key, 'submitted')) {
        throw const QishuiException('领取记录未能保存，请重试');
      }
      if (!_music.current || !mounted) return;
      final result = await _music.call(
        '/luna/commerce/v2/apply_free_vip',
        write: true,
      );
      if (!_music.current || !mounted) return;
      if (result['apply_status'] != 0) {
        await preferences.setString(key, 'rejected');
        throw QishuiException(
          '活动领取未完成（${sodaInt(result['apply_status'])}），请刷新核对资格',
        );
      }
      final after = await _read();
      if (!_music.current || !mounted) return;
      if (after.day != before.day || !after.claimed) {
        throw const QishuiException('已收到领取回执，权益到账尚未确认，请刷新核对');
      }
      await preferences.setString(key, 'confirmed');
      if (mounted) {
        setState(() {
          _status = Future.value(after);
          _message = '今日活动免费 VIP 已在账号权益中确认';
        });
      }
    } on Object catch (error) {
      if (mounted && _music.current) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!watchOwner()) return changedAccount();
    return MusicFeaturePage(
      title: '免费听与权益',
      child: SizedBox.expand(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: FutureBuilder<QishuiWelfareStatus>(
            future: _status,
            builder: (context, snapshot) {
              final status = snapshot.data;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!snapshot.hasData && !snapshot.hasError)
                    const Center(child: MusicActivityIndicator()),
                  if (snapshot.hasError) Text('${snapshot.error}'),
                  if (status != null) ...[
                    Text(
                      '账号权益',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      status.membership['is_membership'] == true
                          ? '当前会员权益有效'
                          : '当前未确认有效会员',
                    ),
                    const SizedBox(height: 28),
                    Text(
                      '活动免费 VIP',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      status.claimed
                          ? '今日已领取'
                          : status.active
                          ? '活动进行中'
                          : '当前没有可领取的活动',
                    ),
                    const SizedBox(height: 16),
                    BetaGlassButton(
                      blue: true,
                      loading: _busy,
                      onPressed: !_busy && status.claimable
                          ? () => _claim(status)
                          : null,
                      child: const Text('领取今日活动 VIP'),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      '广告奖励时长',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '活动 VIP 与广告奖励时长分别结算。当前尚未接通官版广告任务凭证，暂不能在 Mesting 领取或连续领取奖励时长。',
                    ),
                    if (status.listening.containsKey(
                      'reward_tasks_finished',
                    )) ...[
                      const SizedBox(height: 12),
                      Text(
                        '服务端已完成任务：${sodaInt(status.listening['reward_tasks_finished'])}',
                      ),
                    ],
                  ],
                  const SizedBox(height: 24),
                  BetaGlassButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _status = _read()),
                    child: const Text('刷新权益'),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 20),
                    Semantics(liveRegion: true, child: Text(_message!)),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
