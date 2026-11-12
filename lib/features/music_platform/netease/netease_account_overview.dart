import '../../../shared/widgets/beta_content_insets.dart';
import 'dart:math' as math;
import '../../../core/cache/cached_browse_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../platform_backend_providers.dart';
import '../music_platform_providers.dart';
import '../presentation/platform_design.dart';
import '../presentation/platform_avatar.dart';
import '../data/music_platform_api.dart';
import 'netease_music_repository.dart';
import 'full/netease_manual_routes.dart';
import '../../themes/music_typography.dart';

/// Official account level is independent of membership and the local SVIP
/// switch. Missing fields remain unknown, including progress requirements.
class NeteaseAccountLevel {
  const NeteaseAccountLevel(this.level, this.data);
  final int level;
  final Map<String, dynamic> data;
  static NeteaseAccountLevel? parse(Map<String, dynamic> payload) {
    final data = NeteaseMusicRepository.object(payload['data']);
    final level = int.tryParse('${data['level']}');
    return level == null || level < 0 || level > 10
        ? null
        : NeteaseAccountLevel(level, data);
  }

  int? remaining(String next, String now) {
    final n = int.tryParse('${data[next]}'),
        current = int.tryParse('${data[now]}');
    return n == null || current == null ? null : math.max(0, n - current);
  }

  int? get songsRemaining => remaining('nextPlayCount', 'nowPlayCount');
  int? get daysRemaining => remaining('nextLoginCount', 'nowLoginCount');
  String get benefits =>
      '${data['info'] ?? ''}'.replaceAll(RegExp(r'<[^>]+>'), '').trim();
}

class NeteaseAccountOverview {
  const NeteaseAccountOverview(
    this.profile,
    this.level,
    this.counts,
    this.failed,
  );
  final Map<String, dynamic> profile, counts;
  final NeteaseAccountLevel? level;
  final List<String> failed;
}

/// Separate read requests avoid a fragile batch transport and permit partial
/// results. The repository's credential guard also rejects an account switch
/// between these requests; no exception payload is exposed to the screen.
Future<NeteaseAccountOverview> loadNeteaseAccountOverview(
  NeteaseMusicRepository music,
) async {
  final failed = <String>[];
  Future<Map<String, dynamic>> read(String route, String section) async {
    try {
      final contract = neteaseCompleteContract(route, const {});
      if (contract == null) throw const MusicPlatformException('此账号信息暂不可用');
      return await music.api.request(
        contract.path,
        contract.data,
        weapi: contract.weapi,
        expectedCredential: music.credential,
      );
    } catch (_) {
      failed.add(section);
      return {};
    }
  }

  final result = await Future.wait([
    read('/user/account', '账号资料'),
    read('/user/level', '账号等级'),
    read('/user/subcount', '收藏数量'),
  ]);
  if (music.api.session?.credentialId != music.credential) {
    throw const MusicPlatformException('账号已变化，请重新打开页面');
  }
  final level = NeteaseAccountLevel.parse(result[1]);
  if (level == null && !failed.contains('账号等级')) failed.add('账号等级');
  return NeteaseAccountOverview(
    NeteaseMusicRepository.object(result[0]['profile']),
    level,
    result[2],
    List.unmodifiable(failed),
  );
}

final neteaseAccountOverviewProvider = FutureProvider.autoDispose((ref) async {
  await ref.watch(platformAccountProvider.future);
  return cachedBrowse(
    ref,
    () => loadNeteaseAccountOverview(ref.watch(neteaseMusicRepositoryProvider)),
  );
}, retry: (_, _) => null);

class NeteaseAccountOverviewPage extends ConsumerWidget {
  const NeteaseAccountOverviewPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => PlatformPageFrame(
    title: '账号与收藏概览',
    child: ref
        .watch(neteaseAccountOverviewProvider)
        .when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (_, _) => Center(
            child: BetaGlassButton(
              onPressed: () => ref.invalidate(neteaseAccountOverviewProvider),
              child: const Text('账号信息暂时无法加载，点击重试'),
            ),
          ),
          data: (value) {
            final level = value.level;
            final scheme = Theme.of(context).colorScheme;
            const countLabels = {
              'createdPlaylistCount': '创建的歌单',
              'subPlaylistCount': '收藏的歌单',
              'artistCount': '收藏的歌手',
              'albumCount': '收藏的专辑',
              'mvCount': '收藏的 MV',
              'djRadioCount': '收藏的播客',
            };
            return ListView(
              padding: BetaContentInsets.musicPaddingOf(
                context,
                const EdgeInsets.fromLTRB(22, 20, 22, 40),
              ),
              children: [
                Center(
                  child: PlatformAvatar(
                    url: '${value.profile['avatarUrl'] ?? ''}',
                    size: 80,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '${value.profile['nickname'] ?? '网易云账号'}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 24),
                if (level != null) ...[
                  Text(
                    '当前等级：Lv.${level.level}',
                    key: const ValueKey('netease-account-level'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: MusicTypography.sectionTitleSize,
                      fontWeight: MusicTypography.titleWeight,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (var i = 0; i <= 10; i++)
                        Text(
                          '$i',
                          style: MusicTypography.caption.copyWith(
                            color: i == level.level
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: level.level / 10,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  const SizedBox(height: 24),
                  if (level.benefits.isNotEmpty) ...[
                    const Text(
                      '当前等级权益',
                      style: TextStyle(
                        fontSize: MusicTypography.bodySize,
                        fontWeight: MusicTypography.titleWeight,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(level.benefits),
                    const SizedBox(height: 24),
                  ],
                  if (level.level < 10) ...[
                    Text(
                      '距离下一级：Lv.${level.level + 1}',
                      style: const TextStyle(
                        fontSize: MusicTypography.bodySize,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      level.songsRemaining == null
                          ? '听歌量进度暂未提供'
                          : '还需听 ${level.songsRemaining} 首歌',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      level.daysRemaining == null
                          ? '登录天数进度暂未提供'
                          : '还需登录 ${level.daysRemaining} 天',
                    ),
                  ] else
                    const Text('已达到最高等级', textAlign: TextAlign.center),
                ] else
                  const Text('账号等级暂未获取', textAlign: TextAlign.center),
                const SizedBox(height: 28),
                const Text(
                  '收藏概览',
                  style: TextStyle(
                    fontSize: MusicTypography.headingSize,
                    fontWeight: MusicTypography.titleWeight,
                  ),
                ),
                for (final entry in countLabels.entries)
                  if (value.counts[entry.key] is num)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(entry.value),
                      trailing: Text('${value.counts[entry.key]}'),
                    ),
                if (value.failed.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text('${value.failed.join('、')}暂时无法加载，其余内容已保留。'),
                  const SizedBox(height: 12),
                  BetaGlassButton(
                    onPressed: () =>
                        ref.invalidate(neteaseAccountOverviewProvider),
                    child: const Text('重新加载'),
                  ),
                ],
              ],
            );
          },
        ),
  );
}
