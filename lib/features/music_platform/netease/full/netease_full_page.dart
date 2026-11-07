import '../../../../shared/widgets/beta_page_motion.dart';
import '../../../../shared/widgets/song_list_tools.dart';
import '../../presentation/platform_lazy_list.dart';
import '../../../../shared/widgets/beta_choice_field.dart';
import '../../../../shared/widgets/beta_content_insets.dart';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../themes/beta_appearance.dart';
import '../../../../core/platform/distribution_channel.dart';
import '../../../../core/cache/cached_browse_loader.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../shared/models/track.dart';
import '../../../../shared/widgets/artwork_image.dart';
import '../../../../shared/widgets/beta_glass_controls.dart';
import '../../../../shared/widgets/beta_glass_action.dart';
import '../../../../shared/widgets/beta_bottom_search.dart';
import '../../../../shared/widgets/beta_page_search_layout.dart';
import '../../../experience/presentation/editorial_widgets.dart';
import '../../music_platform_providers.dart';
import '../../platform_backend_providers.dart';
import '../../presentation/platform_account_page.dart';
import '../../presentation/platform_profile_edit_page.dart';
import '../../../search/presentation/music_search_page.dart';
import '../../presentation/platform_design.dart';
import '../../domain/platform_session.dart';
import '../netease_features_page.dart';
import '../netease_features_repository.dart';
import '../netease_playback_settings_page.dart';
import '../netease_membership_page.dart';
import '../netease_account_overview.dart';
import '../netease_music_repository.dart';
import 'netease_catalog.dart';
import 'netease_content.dart';
import 'netease_full_repository.dart';
import 'netease_recognition.dart';
import 'netease_video.dart';
import 'netease_entity_picker.dart';
import 'netease_together_page.dart';
import '../messages/netease_messages_page.dart';
import '../messages/netease_unread.dart';
import 'netease_workflow_policy.dart';
import 'netease_comment_entry_page.dart';

final neteaseFullRepositoryProvider = Provider<NeteaseFullRepository>(
  (ref) => NeteaseFullRepository(ref.watch(neteaseMusicRepositoryProvider)),
);

String neteaseTaskTitle(NeteaseEndpoint e) => switch (e.route) {
  '/inner/version' => '兼容信息',
  '/comment/hotwall/list' => '云村热评',
  '/batch' => '账号与收藏概览',
  '/audio/match' => '听歌识曲',
  '/avatar/upload' => '更新头像',
  '/song/url' => '歌曲播放资源',
  '/song/url/v1' => '歌曲音质选择',
  '/song/download/url' => '歌曲下载资源',
  _ => e.title.replaceFirst(RegExp(r'^获取\s*'), '').replaceAll('接口', '').trim(),
};

/// Compact category links sit inside the existing four destinations. The
/// searchable catalogue is local metadata and performs no background writes.
class NeteaseFullNavigation extends ConsumerWidget {
  const NeteaseFullNavigation({
    required this.tab,
    this.categories,
    this.excludedCategories = const {},
    this.categoryLabels = const {},
    this.showHeading = true,
    this.grouped = true,
    this.heading = '网易云专区',
    super.key,
  });
  final String tab;
  final Set<String>? categories;
  final Set<String> excludedCategories;
  final Map<String, String> categoryLabels;
  final bool showHeading, grouped;
  final String heading;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(neteaseCatalogProvider);
    return entries.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (all) {
        final visibleCategories = all
            .where(
              (e) =>
                  e.tab == tab &&
                  e.category != '音乐搜索' &&
                  (categories == null || categories!.contains(e.category)) &&
                  !excludedCategories.contains(e.category),
            )
            .map((e) => e.category)
            .toSet();
        if (visibleCategories.isEmpty) return const SizedBox.shrink();
        final rows = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final category in visibleCategories)
              ListTile(
                contentPadding: grouped
                    ? null
                    : const EdgeInsets.symmetric(horizontal: 24),
                minLeadingWidth: grouped ? null : 26,
                horizontalTitleGap: grouped ? null : 18,
                leading: Icon(
                  _categoryIcon(category),
                  color: !DistributionChannel.isBeta && grouped
                      ? null
                      : BetaAppearance.feature(context, switch (category) {
                          '一起听' || '音效' => BetaFeatureTone.together,
                          '下载管理' => BetaFeatureTone.downloads,
                          '听歌回顾' ||
                          '听歌排行' ||
                          '听歌统计' => BetaFeatureTone.insights,
                          '我的喜欢' => BetaFeatureTone.music,
                          _ => BetaFeatureTone.action,
                        }),
                ),
                title: Text(
                  categoryLabels[category] ??
                      (category == '消息中心' ? '我的消息' : category),
                  style: grouped
                      ? null
                      : const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (category == '消息中心') ...[
                      NeteaseUnreadBadge(ref.watch(neteaseUnreadTotalProvider)),
                      const SizedBox(width: 8),
                    ],
                    const Icon(CupertinoIcons.chevron_right, size: 16),
                  ],
                ),
                onTap: () async {
                  await _push(
                    context,
                    category == '消息中心'
                        ? const NeteaseMessagesPage()
                        : category == '一起听'
                        ? const NeteaseTogetherPage()
                        : neteaseCategoryDestination(all, tab, category),
                  );
                  if (context.mounted && category == '消息中心') {
                    ref.invalidate(neteaseUnreadCountsProvider);
                  }
                },
              ),
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showHeading) EditorialSection(heading),
            if (grouped)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: PlatformPanel(padding: EdgeInsets.zero, child: rows),
              )
            else
              rows,
          ],
        );
      },
    );
  }
}

/// Singleton categories open their real workflow directly. Multi-task hubs
/// remain lists, preserving the meaning of Back without an empty wrapper.
Widget neteaseCategoryDestination(
  List<NeteaseEndpoint> all,
  String tab,
  String category,
) {
  final workflows = <String, NeteaseEndpoint>{};
  for (final entry in all.where(
    (e) => e.tab == tab && e.category == category,
  )) {
    workflows.putIfAbsent(neteaseWorkflowKey(entry), () => entry);
  }
  if (workflows.length == 1) {
    final entry = workflows.values.single;
    if (neteaseWorkflowKey(entry) == 'playback-settings') {
      return const NeteasePlaybackSettingsPage();
    }
    return NeteaseFullTaskPage(endpoint: entry);
  }
  return NeteaseFullHubPage(tab: tab, category: category);
}

IconData _categoryIcon(String category) => switch (category) {
  '消息中心' => CupertinoIcons.chat_bubble_2,
  '账号与安全' => CupertinoIcons.person_crop_circle,
  '云村与话题' => CupertinoIcons.bubble_left_bubble_right,
  '播客与声音' => CupertinoIcons.mic,
  '视频与MV' => CupertinoIcons.play_rectangle,
  '会员与云贝' => CupertinoIcons.star_circle,
  '音乐人中心' => CupertinoIcons.music_note_2,
  '听歌工具' => CupertinoIcons.slider_horizontal_3,
  '歌单与收藏' => CupertinoIcons.music_note_list,
  '音乐云盘' => CupertinoIcons.cloud,
  '已购音乐' => CupertinoIcons.bag,
  '历史与听歌报告' => CupertinoIcons.clock,
  '资料与收藏概览' => CupertinoIcons.square_stack_3d_up,
  '播放与同步' => CupertinoIcons.slider_horizontal_3,
  _ => CupertinoIcons.compass,
};
Future<void> _push(BuildContext context, Widget page) async =>
    Navigator.of(context).push(MestingPageRoute<void>(builder: (_) => page));

class NeteaseFullHubPage extends ConsumerStatefulWidget {
  const NeteaseFullHubPage({
    this.tab,
    this.category,
    this.entityKind,
    this.seed = const {},
    super.key,
  });
  final String? tab, category, entityKind;
  final Map<String, Object?> seed;
  @override
  ConsumerState<NeteaseFullHubPage> createState() => _NeteaseFullHubPageState();
}

class _NeteaseFullHubPageState extends ConsumerState<NeteaseFullHubPage> {
  String _search = '';
  late final _bottomSearch = BetaPageSearchController(
    hintText: '查找功能',
    onSubmitted: _filter,
    onCleared: () => _filter(''),
    onChanged: _filter,
  );
  void _filter(String value) {
    if (mounted) setState(() => _search = value);
  }

  @override
  void dispose() {
    _bottomSearch.dispose();
    super.dispose();
  }

  bool _matchesEntity(NeteaseEndpoint e) {
    final kind = widget.entityKind;
    if (kind == null) return true;
    if (kind == 'song') {
      return RegExp(
        r'^/(song|simi/song|comment($|/(music|hot|new|floor|like))|lyric|like$|scrobble|sheet|share/resource|send/song)',
      ).hasMatch(e.route);
    }
    if (kind == 'message') {
      return e.route.startsWith('/msg/') || e.route.startsWith('/send/');
    }
    if (kind == 'comment') {
      return e.route == '/comment' ||
          e.route.startsWith('/comment/') ||
          e.route == '/resource/like';
    }
    return e.route.startsWith('/$kind/') ||
        e.route == '/$kind' ||
        e.route == '/comment/$kind' ||
        e.route == '/send/$kind' ||
        e.route == '/share/resource';
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(neteaseCatalogProvider);
    return BetaPageSearchLayout(
      controller: _bottomSearch,
      child: PlatformPageFrame(
        title: widget.category ?? '更多音乐功能',
        child: Column(
          children: [
            Expanded(
              child: catalog.when(
                loading: () => const PlatformFeedbackState(loading: true),
                error: (_, _) => PlatformFeedbackState(
                  message: '功能目录加载失败',
                  retry: () => ref.invalidate(neteaseCatalogProvider),
                ),
                data: (all) {
                  final workflowKeys = <String>{};
                  final entries = all
                      .where(
                        (e) =>
                            (widget.tab == null || e.tab == widget.tab) &&
                            (widget.category == null ||
                                e.category == widget.category) &&
                            _matchesEntity(e) &&
                            ('${neteaseTaskTitle(e)} ${e.category}'.contains(
                              _search.trim(),
                            )),
                      )
                      .where((e) => workflowKeys.add(neteaseWorkflowKey(e)))
                      .toList();
                  return ListView.builder(
                    padding: EdgeInsets.only(
                      bottom: BetaContentInsets.bottomOf(context, 40),
                    ),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final endpoint = entries[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 5,
                        ),
                        leading: Icon(_categoryIcon(endpoint.category)),
                        title: Text(
                          neteaseWorkflowTitle(endpoint) ??
                              neteaseTaskTitle(endpoint),
                        ),
                        trailing: const Icon(
                          CupertinoIcons.chevron_right,
                          size: 16,
                        ),
                        onTap: () => _push(
                          context,
                          endpoint.route.startsWith('/listentogether/')
                              ? const NeteaseTogetherPage()
                              : NeteaseFullTaskPage(
                                  endpoint: endpoint,
                                  seed: {
                                    ...widget.seed,
                                    if (widget.entityKind != null)
                                      '_entityKind': widget.entityKind,
                                  },
                                ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NeteaseFullTaskPage extends ConsumerStatefulWidget {
  const NeteaseFullTaskPage({
    required this.endpoint,
    this.seed = const {},
    super.key,
  });
  final NeteaseEndpoint endpoint;
  final Map<String, Object?> seed;
  @override
  ConsumerState<NeteaseFullTaskPage> createState() =>
      _NeteaseFullTaskPageState();
}

class _NeteaseFullTaskPageState extends ConsumerState<NeteaseFullTaskPage> {
  final _browse = CachedBrowseLoader();
  String? get _searchKey => e.parameters
      .where(
        (p) =>
            {'keywords', 'keyword'}.contains(p.key) ||
            e.route.contains('search') &&
                {'name', 'podcastName'}.contains(p.key),
      )
      .firstOrNull
      ?.key;
  late final _taskSearch = BetaPageSearchController(
    hintText: '搜索内容',
    onSubmitted: (text) {
      final key = _searchKey;
      if (key != null) {
        _fields[key]!.text = text;
        _submit();
      }
    },
    onCleared: () {
      final key = _searchKey;
      if (key != null) _fields[key]!.clear();
      _generation++;
      if (mounted) {
        setState(() {
          _rows.clear();
          _dataRevision++;
          _facts.clear();
          _busy = false;
          _more = false;
          _error = null;
          _notice = null;
        });
      }
    },
  );
  Widget _searchLayout(Widget child) => _searchKey == null
      ? child
      : BetaPageSearchLayout(controller: _taskSearch, child: child);
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  final _files = <String, Object?>{};
  final _rows = <NeteaseContentRow>[];
  int _dataRevision = 0, _derivedRevision = -1;
  List<Track> _resultTracks = const [];
  List<MapEntry<String, String>> _factRows = const [];

  /// Keep playback context complete while avoiding a full row scan when a form
  /// field, loading indicator or filter-panel control rebuilds the page.
  void _deriveResults() {
    if (_derivedRevision == _dataRevision) return;
    _resultTracks = _rows
        .map((r) => r.track)
        .whereType<Track>()
        .toList(growable: false);
    _factRows = _facts.entries.toList(growable: false);
    _derivedRevision = _dataRevision;
  }

  final _facts = <String, String>{};
  final _selections = <String, String>{};
  String? _owner, _credential, _error, _notice, _videoUrl;
  bool _busy = false, _confirming = false, _more = false;
  bool _showFilters = false;
  int _generation = 0, _offset = 0, _page = 1;
  Object? _cursor;
  NeteaseEndpoint get e => widget.endpoint;
  bool get _nativeWorkflow =>
      neteaseFeedRoutes.containsKey(e.route) ||
      {
        'messages',
        'together',
        'search',
        'profile-edit',
        'account-login',
        'playback-settings',
        'vip-info',
        'comments',
      }.contains(neteaseWorkflowKey(e)) ||
      e.route == '/user/record' ||
      e.route == '/user/level';
  bool get _current =>
      ref.read(usesNeteaseProvider) &&
      ref.read(platformAccountProvider).value?.ownerId == _owner &&
      ref.read(platformAccountProvider).value?.token == _credential;
  bool get _loginWorkflow => {
    '/login',
    '/login/cellphone',
    '/login/qr/key',
    '/login/qr/create',
    '/login/qr/check',
    '/captcha/sent',
  }.contains(e.route);
  bool get _fileWorkflow => {
    '/cloud',
    '/voice/upload',
    '/avatar/upload',
    '/playlist/cover/update',
  }.contains(e.route);
  List<NeteaseParameter> get _params => e.parameters
      .where(
        (p) => !{
          'imgFile',
          'songFile',
          'qrimg',
          'unblock',
          'md5_password',
          'audioFP',
          'duration',
          'offset',
          'cursor',
          'page',
          'pageNo',
          'idCursor',
          'lasttime',
          'before',
          'idx',
          'res',
          ...neteaseAutomaticFields,
        }.contains(p.key),
      )
      .toList();
  @override
  void initState() {
    super.initState();
    final a = ref.read(platformAccountProvider).value;
    _owner = a?.ownerId;
    _credential = a?.token;
    for (final p in _params) {
      _fields[p.key] = TextEditingController(
        text:
            '${widget.seed[p.key] ?? neteaseWorkflowDefaults(e.route, a?.userId ?? '')[p.key] ?? ''}',
      );
    }
    if (_searchKey != null) _taskSearch.text.text = _fields[_searchKey]!.text;
    if (!_nativeWorkflow &&
        _searchKey == null &&
        !_loginWorkflow &&
        !e.write &&
        !_fileWorkflow &&
        e.route != '/audio/match' &&
        e.route != '/batch' &&
        e.unavailable == null &&
        _params
            .where((p) => p.required)
            .every((p) => _fields[p.key]!.text.isNotEmpty)) {
      Future.microtask(() => _load());
    }
  }

  @override
  void dispose() {
    _generation++;
    _browse.dispose();
    _taskSearch.dispose();
    for (final c in _fields.values) {
      c.clear();
      c.dispose();
    }
    _cleanupFiles();
    super.dispose();
  }

  Future<void> _cleanupFiles() async {
    for (final value in _files.values) {
      if (value is Map && value['path'] is String) {
        final file = File('${value['path']}');
        try {
          if (await file.exists()) await file.delete();
        } on FileSystemException {
          /* Only the picker-owned temporary copy is eligible. */
        }
      }
    }
  }

  Map<String, Object?> _query({bool next = false}) {
    final q = <String, Object?>{
      for (final p in e.parameters)
        if (neteaseWorkflowDefaults(
          e.route,
          ref.read(platformAccountProvider).value?.userId ?? '',
        ).containsKey(p.key))
          p.key: neteaseWorkflowDefaults(
            e.route,
            ref.read(platformAccountProvider).value?.userId ?? '',
          )[p.key],
      for (final p in e.parameters)
        if (widget.seed.containsKey(p.key)) p.key: widget.seed[p.key],
      ..._files,
      for (final f in _fields.entries)
        if (f.value.text.trim().isNotEmpty)
          f.key: f.key == 'password' ? f.value.text : f.value.text.trim(),
    };
    if (e.parameters.any((p) => p.key == 'offset')) {
      q['offset'] = next ? _offset : 0;
    }
    if (e.parameters.any((p) => p.key == 'pageNo')) {
      q['pageNo'] = next ? _page : 1;
    }
    if (e.parameters.any((p) => p.key == 'page')) q['page'] = next ? _page : 1;
    if (next && _cursor != null) {
      for (final k in ['cursor', 'lasttime', 'before', 'idCursor']) {
        if (e.parameters.any((p) => p.key == k)) q[k] = _cursor;
      }
    }
    if (e.route == '/batch') {
      q['requests'] = [
        for (final route in ['/user/account', '/user/level', '/user/subcount'])
          {'route': route, 'query': <String, Object?>{}},
      ];
    }
    return q;
  }

  Future<void> _submit() async {
    if (_busy ||
        _confirming ||
        !_current ||
        !(_form.currentState?.validate() ?? true)) {
      return;
    }
    if (_fileWorkflow && _files.isEmpty) {
      setState(() => _error = '请先选择文件');
      return;
    }
    final q = _query();
    if (e.write) {
      _confirming = true;
      final confirmed = await showCupertinoDialog<bool>(
        context: context,
        builder: (c) => CupertinoAlertDialog(
          title: Text('确认${neteaseTaskTitle(e)}？'),
          content: Text(
            '${e.route.startsWith('/send/')
                ? '这会向所选收件人发送消息。'
                : e.route == '/digitalAlbum/ordering'
                ? '这会创建购买订单，请核对内容、数量与支付方式。'
                : '操作将应用到当前网易云账号。'}\n提交后请等待平台确认结果。',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: e.title.contains('删除'),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('确认'),
            ),
          ],
        ),
      );
      _confirming = false;
      if (confirmed != true || !mounted || !_current) return;
    }
    await _load(query: q);
  }

  Future<void> _load({bool next = false, Map<String, Object?>? query}) async {
    if (_busy || !_current) return;
    final epoch = next ? _generation : ++_generation;
    if (!next) _browse.reset();
    final q = query ?? _query(next: next);
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      if (e.route == '/login/refresh') {
        await ref.read(platformAccountProvider.notifier).refreshNetease();
        if (mounted) {
          _credential = ref.read(platformAccountProvider).value?.token;
          setState(() => _notice = '登录状态已刷新');
        }
        return;
      }
      final repository = ref.read(neteaseFullRepositoryProvider);
      final page = next ? _page : 1;
      final payload = e.write
          ? await repository.run(e, q)
          : await _browse.load(
              key: page,
              request: () => repository.run(e, q),
              onUpdate: (previous, current) {
                if (!mounted || epoch != _generation || !_current) return;
                final old = NeteaseContent.parse(previous, e.route);
                final fresh = NeteaseContent.parse(current, e.route);
                setState(() {
                  replaceBrowsePage(
                    _rows,
                    old.rows,
                    fresh.rows,
                    (row) =>
                        row.id.isEmpty ? row.identity : '${row.kind}:${row.id}',
                  );
                  for (final entry in old.facts.entries) {
                    if (_facts[entry.key] == entry.value) {
                      _facts.remove(entry.key);
                    }
                  }
                  _facts.addAll(fresh.facts);
                  _dataRevision++;
                  _offset = (_offset - old.rows.length + fresh.rows.length)
                      .clamp(0, 2147483647);
                  if (page == _page - 1) {
                    _cursor = fresh.cursor;
                    _more =
                        fresh.more ||
                        (e.parameters.any((p) => p.key == 'offset') &&
                            fresh.rows.length >=
                                (int.tryParse('${q['limit']}') ?? 30));
                  }
                  _notice = _rows.isEmpty && _facts.isEmpty ? '暂无可展示的内容' : null;
                });
              },
            );
      if (!mounted || epoch != _generation || !_current) return;
      if (e.route == '/logout') {
        await ref.read(platformAccountProvider.notifier).signOut();
        return;
      }
      final result = NeteaseContent.parse(payload, e.route);
      setState(() {
        if (!next) {
          _rows.clear();
          _facts.clear();
          _offset = 0;
          _page = 1;
        }
        final identities = _rows.map((r) => r.identity).toSet();
        _rows.addAll(result.rows.where((r) => identities.add(r.identity)));
        _facts.addAll(result.facts);
        _dataRevision++;
        if ({'/video/url', '/mv/url', '/mlog/url'}.contains(e.route)) {
          _videoUrl = neteaseVideoUrl(payload);
        }
        _offset += result.rows.length;
        _page++;
        _cursor = result.cursor;
        _more =
            !e.write &&
            (result.more ||
                (e.parameters.any((p) => p.key == 'offset') &&
                    result.rows.length >=
                        (int.tryParse('${q['limit']}') ?? 30)));
        if (e.write) {
          _notice = '平台已确认操作，请刷新相关列表查看结果';
        } else if (_rows.isEmpty && neteaseIsCollection(e.route)) {
          _facts.clear();
          _notice = '暂无${neteaseTaskTitle(e).replaceAll('列表', '')}';
          _more = false;
        } else if (_rows.isEmpty && _facts.isEmpty) {
          _notice = '暂无可展示的内容';
        }
      });
    } catch (error) {
      if (mounted && epoch == _generation && _current) {
        setState(
          () => _error =
              '${error.toString().replaceFirst('Exception: ', '')} ${e.write ? '若请求已发送但结果未确认，请先刷新内容核对，避免重复提交。' : ''}',
        );
      }
    } finally {
      if (mounted && epoch == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _pick(bool image) async {
    if (_busy || !_current) return;
    try {
      if (image) {
        final chosen = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 90,
        );
        if (chosen == null || !mounted || !_current) return;
        final Uint8List bytes = await chosen.readAsBytes();
        if (!mounted || !_current) return;
        setState(() => _files['imgFile'] = bytes);
      } else {
        final file = await const MethodChannel(
          'com.mesting.music/netease_cloud_file',
        ).invokeMapMethod<Object?, Object?>('pick');
        if (file == null) return;
        if (!mounted || !_current) {
          final temporary = File('${file['path']}');
          if (await temporary.exists()) await temporary.delete();
          return;
        }
        await _cleanupFiles();
        if (mounted && _current) setState(() => _files['songFile'] = file);
      }
    } catch (_) {
      if (mounted && _current) setState(() => _error = '文件未能读取，请重新选择');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(platformAccountProvider);
    if (!_current) {
      return PlatformPageFrame(
        title: neteaseTaskTitle(e),
        child: const Center(child: Text('账号已变化，请返回后重新打开')),
      );
    }
    final key = neteaseWorkflowKey(e);
    if (e.route == '/batch' || e.route == '/user/level') {
      return const NeteaseAccountOverviewPage();
    }
    if (e.route.startsWith('/send/') && e.route != '/send/text') {
      return NeteaseShareMessagePage(
        kind: e.route.split('/').last,
        id: '${widget.seed['id'] ?? ''}',
        name: '${widget.seed['name'] ?? ''}',
      );
    }
    if (key == 'messages') return const NeteaseMessagesPage();
    if (key == 'together') return const NeteaseTogetherPage();
    if (key == 'search') return const MusicSearchPage();
    if (key == 'profile-edit') return const PlatformProfileEditPage();
    if (key == 'playback-settings') return const NeteasePlaybackSettingsPage();
    if (key == 'vip-info') return const NeteaseMembershipPage();
    if (key == 'account-login') {
      return const PlatformAccountPage(platform: MusicPlatform.netease);
    }
    if (key == 'comments') {
      return NeteaseCommentEntryPage(route: e.route, seed: widget.seed);
    }
    final feed = neteaseFeedRoutes[e.route];
    if (feed != null) {
      return NeteaseFeaturesPage(
        feed: feed,
        id: '${widget.seed['id'] ?? widget.seed['uid'] ?? ''}',
      );
    }
    if (e.route == '/user/record') {
      return const NeteaseFeaturesPage(feed: NeteaseFeed.week);
    }
    if (e.route == '/scrobble') return const NeteasePlaybackSettingsPage();
    if (e.unavailable != null) {
      return PlatformPageFrame(
        title: neteaseTaskTitle(e),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: PlatformFeedbackState(message: '平台暂不支持\n${e.unavailable}'),
        ),
      );
    }
    if (_loginWorkflow) {
      return PlatformPageFrame(
        title: neteaseTaskTitle(e),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('在账号管理中完成登录、验证码和扫码。登录状态由账号管理统一保存。'),
              const SizedBox(height: 20),
              BetaGlassButton(
                onPressed: () => _push(
                  context,
                  const PlatformAccountPage(
                    platform: MusicPlatform.netease,
                    loginOnly: true,
                  ),
                ),
                child: const Text('打开网易云账号管理'),
              ),
            ],
          ),
        ),
      );
    }
    _deriveResults();
    final tracks = _resultTracks;
    final visibleParams = _params.where(
      (p) =>
          p.key != _searchKey &&
          !widget.seed.containsKey(p.key) &&
          (e.write || p.required || _showFilters),
    );
    return _searchLayout(
      PlatformPageFrame(
        title: neteaseTaskTitle(e),
        child: SongListTools(
          listId:
              'netease-task:${e.route}:${widget.seed["id"] ?? widget.seed["ids"] ?? widget.seed["uid"] ?? ""}:${_query()[_searchKey] ?? ""}',
          hasMore: _more && !_busy,
          loadMore: () => _load(next: true),
          child: buildPlatformLazyList(
            padding: EdgeInsets.fromLTRB(
              22,
              10,
              22,
              BetaContentInsets.bottomOf(context, 40),
            ),
            header: [
              if (!e.write &&
                  _params.any(
                    (p) =>
                        !p.required &&
                        p.key != _searchKey &&
                        !widget.seed.containsKey(p.key) &&
                        !{'uid', 'userId'}.contains(p.key),
                  ))
                Align(
                  alignment: Alignment.centerRight,
                  child: BetaGlassButton(
                    onPressed: () =>
                        setState(() => _showFilters = !_showFilters),
                    child: Text(_showFilters ? '收起筛选' : '筛选'),
                  ),
                ),
              if (e.route == '/audio/match')
                NeteaseRecognitionCapture(
                  isCurrent: () => mounted && _current,
                  onFingerprint: (fp, duration) {
                    _files['audioFP'] = fp;
                    _files['duration'] = duration;
                    _load();
                  },
                ),
              Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final p in visibleParams)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _input(p),
                      ),
                    if (e.route == '/batch')
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text('一起查看当前账号资料、等级和收藏数量。'),
                      ),
                    if (_fileWorkflow) ...[
                      BetaGlassButton(
                        onPressed: _busy
                            ? null
                            : () => _pick(
                                e.route == '/avatar/upload' ||
                                    e.route == '/playlist/cover/update',
                              ),
                        child: Text(_files.isEmpty ? '选择文件' : '重新选择文件'),
                      ),
                      if (_files.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            _files['songFile'] is Map
                                ? '${(_files['songFile'] as Map)['name']}'
                                : '图片已选择',
                          ),
                        ),
                    ],
                    if (e.route != '/audio/match' &&
                        _searchKey == null &&
                        (e.write ||
                            visibleParams.isNotEmpty ||
                            e.route == '/batch'))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: BetaGlassButton(
                          onPressed: _busy ? null : _submit,
                          loading: _busy,
                          blue: e.write,
                          child: Text(e.write ? neteaseTaskTitle(e) : '打开内容'),
                        ),
                      ),
                  ],
                ),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(22),
                  child: Center(child: BetaActivityIndicator()),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Column(
                    children: [
                      Text(_error!),
                      const SizedBox(height: 12),
                      if (!e.write)
                        BetaGlassButton(
                          onPressed: _busy ? null : _submit,
                          child: const Text('重新加载'),
                        ),
                    ],
                  ),
                ),
              if (_notice != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(_notice!),
                ),
              if (_videoUrl != null)
                NeteaseVideoView(
                  key: ValueKey(_videoUrl),
                  url: _videoUrl!,
                  isCurrent: () => mounted && _current,
                ),
              if (e.route == '/style/detail')
                BetaGlassButton(
                  onPressed: () => _push(
                    context,
                    NeteaseFullHubPage(
                      entityKind: 'style',
                      seed: {'tagId': _query()['tagId']},
                    ),
                  ),
                  child: const Text('查看此曲风的歌曲、专辑与歌单'),
                ),
            ],
            itemCount: _factRows.length + _rows.length,
            itemBuilder: (context, index) => index < _factRows.length
                ? _factRow(context, _factRows[index])
                : _contentRow(context, _rows[index - _factRows.length], tracks),
            footer: [
              if (_more)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: BetaGlassButton(
                    onPressed: _busy ? null : () => _load(next: true),
                    loading: _busy,
                    child: const Text('加载更多'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _factRow(BuildContext context, MapEntry<String, String> fact) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: fact.key.contains('二维码')
            ? Column(
                children: [
                  QrImageView(data: fact.value, size: 220),
                  Text(
                    fact.key == '支付二维码'
                        ? '请使用所选支付应用扫码，核对订单后付款'
                        : '请使用网易云官方客户端扫码',
                  ),
                ],
              )
            : fact.key == '乐谱图片'
            ? ArtworkImage(uri: fact.value, height: 480, fit: BoxFit.contain)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fact.key, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 7),
                  SelectableText(fact.value),
                ],
              ),
      );

  Widget _contentRow(
    BuildContext context,
    NeteaseContentRow row,
    List<Track> tracks,
  ) => row.track != null
      ? EditorialTrackRow(track: row.track!, contextTracks: tracks)
      : ListTile(
          contentPadding: EdgeInsets.zero,
          leading: row.cover.isEmpty
              ? Icon(_categoryIcon(e.category))
              : ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ArtworkImage(uri: row.cover, width: 48, height: 48),
                ),
          title: Text(row.title),
          subtitle: row.subtitle.isEmpty ? null : Text(row.subtitle),
          trailing: row.id.isEmpty
              ? null
              : const Icon(CupertinoIcons.chevron_right, size: 16),
          onTap: () => _openRow(context, row),
        );

  void _openRow(BuildContext context, NeteaseContentRow row) {
    if (!_current) return;
    final catalog = ref.read(neteaseCatalogProvider).value;
    final relatedRoute =
        row.kind == 'message' && e.route != '/msg/private/history'
        ? '/msg/private/history'
        : row.kind == 'style'
        ? '/style/detail'
        : e.route == '/sheet/list'
        ? '/sheet/preview'
        : null;
    if (relatedRoute != null) {
      final endpoint = catalog
          ?.where((e) => e.route == relatedRoute)
          .firstOrNull;
      if (endpoint != null) {
        final from = NeteaseMusicRepository.object(
          row.raw['fromUser'] ?? row.raw['user'],
        );
        _push(
          context,
          NeteaseFullTaskPage(
            endpoint: endpoint,
            seed: {
              'id': row.id,
              'tagId': row.id,
              'uid': '${from['userId'] ?? row.id}',
            },
          ),
        );
        return;
      }
    }
    final kind = switch (row.kind) {
      'playlist' => NeteaseEntity.playlist,
      'album' => NeteaseEntity.album,
      'artist' => NeteaseEntity.artist,
      'mv' => NeteaseEntity.mv,
      'podcast' => NeteaseEntity.podcast,
      'user' => NeteaseEntity.user,
      _ => null,
    };
    if (kind != null) {
      openNeteaseItem(
        context,
        NeteaseItem(
          id: row.id,
          name: row.title,
          kind: kind,
          cover: row.cover,
          subtitle: row.subtitle,
        ),
      );
      return;
    }
    if (row.kind == 'video') {
      final catalog = ref.read(neteaseCatalogProvider).value;
      final endpoint = catalog
          ?.where((e) => e.route == '/video/url')
          .firstOrNull;
      if (endpoint != null) {
        _push(
          context,
          NeteaseFullTaskPage(endpoint: endpoint, seed: {'id': row.id}),
        );
        return;
      }
    }
    _push(
      context,
      NeteaseContentDetailPage(row: row, category: e.category, seed: _query()),
    );
  }

  Widget _input(NeteaseParameter p) {
    if (p.key == 'coverImgId') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_files['imgFile'] is Uint8List)
            Image.memory(_files['imgFile'] as Uint8List, height: 100),
          BetaGlassButton(
            onPressed: _busy ? null : () => _pick(true),
            child: Text(
              _files['imgFile'] != null || _fields[p.key]!.text.isNotEmpty
                  ? '更换声音封面'
                  : '选择声音封面',
            ),
          ),
        ],
      );
    }
    final entity = _pickerKind(p);
    if (entity != null) {
      return FormField<String>(
        initialValue: _fields[p.key]!.text,
        validator: (_) => p.required && _fields[p.key]!.text.isEmpty
            ? '请选择${neteaseEntityLabel(entity)}'
            : null,
        builder: (field) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(CupertinoIcons.music_note_list),
              title: Text(
                _selections[p.key] ??
                    (_fields[p.key]!.text.isEmpty
                        ? '选择${neteaseEntityLabel(entity)}'
                        : '已选择${neteaseEntityLabel(entity)}'),
              ),
              trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
              onTap: _busy
                  ? null
                  : () async {
                      await _chooseEntity(p);
                      field.didChange(_fields[p.key]!.text);
                    },
            ),
            if (field.errorText != null)
              Text(
                field.errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      );
    }
    if ({
      'startTime',
      'endTime',
      'birthday',
      'date',
      'publishTime',
    }.contains(p.key)) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(p.label),
        subtitle: Text(_dateLabel(_fields[p.key]!.text)),
        trailing: const Icon(CupertinoIcons.calendar),
        onTap: _busy ? null : () => _pickDate(p),
      );
    }
    final options = switch (p.key) {
      'gender' => const {'0': '未设置', '1': '男', '2': '女'},
      'like' => const {'true': '喜欢', 'false': '取消喜欢'},
      'op' => const {'add': '添加', 'del': '移除'},
      'sortType' => const {'1': '推荐', '2': '最热', '3': '最新'},
      'asc' => const {'true': '从早到晚', 'false': '从晚到早'},
      'payment' => const {'0': '支付宝', '3': '微信'},
      'level' => const {
        'standard': '标准',
        'higher': '较高',
        'exhigh': '极高',
        'lossless': '无损',
        'hires': 'Hi-Res',
        'jyeffect': '高清环绕',
        'sky': '沉浸环绕',
        'jymaster': '超清母带',
      },
      'privacy' =>
        e.route == '/playlist/create'
            ? const {'0': '公开', '10': '私密'}
            : const {'0': '公开', '1': '私密'},
      't' =>
        e.route == '/comment'
            ? const {'1': '发布评论', '2': '回复评论', '0': '删除评论'}
            : null,
      'type' =>
        e.route.startsWith('/comment')
            ? const {
                '0': '歌曲',
                '1': 'MV',
                '2': '歌单',
                '3': '专辑',
                '4': '电台节目',
                '5': '视频',
                '6': '动态',
                '7': '电台',
              }
            : null,
      _ => null,
    };
    final decoration = InputDecoration(
      labelText: p.label + (p.required ? ' *' : ''),
      helperText: p.key == 'user_ids'
          ? '搜索选择收件人，或输入用户编号'
          : p.help.isEmpty ||
                p.help.contains('/api') ||
                p.help.contains('接口') ||
                p.help.toLowerCase().contains('id')
          ? null
          : p.help,
      helperMaxLines: 3,
      suffixIcon: _pickerKind(p) == null
          ? null
          : Padding(
              padding: const EdgeInsets.all(4),
              child: BetaGlassAction(
                label: '搜索并选择',
                compact: true,
                onPressed: _busy ? null : () => _chooseEntity(p),
                icon: CupertinoIcons.search,
              ),
            ),
    );
    String? validate(String? value) =>
        p.required && (value ?? '').trim().isEmpty ? '请填写${p.label}' : null;
    if (options != null) {
      return BetaChoiceField<String>(
        initialValue: options.containsKey(_fields[p.key]!.text)
            ? _fields[p.key]!.text
            : null,
        isExpanded: true,
        decoration: decoration,
        items: [
          for (final item in options.entries)
            DropdownMenuItem(value: item.key, child: Text(item.value)),
        ],
        onChanged: _busy ? null : (value) => _fields[p.key]!.text = value ?? '',
        validator: validate,
      );
    }
    return TextFormField(
      controller: _fields[p.key],
      enabled: !_busy,
      obscureText: p.private,
      maxLines: p.private || p.key == 'user_ids'
          ? 1
          : p.multiline
          ? 3
          : 1,
      autocorrect: !p.private,
      enableSuggestions: !p.private,
      decoration: decoration,
      validator: validate,
    );
  }

  String? _pickerKind(NeteaseParameter p) {
    if (p.key == 'ids' && e.route == '/vip/growthpoint/get') return 'vipTask';
    if ({'uid', 'userId', 'user_ids', 'inviterId'}.contains(p.key)) {
      return 'user';
    }
    if ({'pid', 'playlist'}.contains(p.key)) return 'playlist';
    if ({'tagId'}.contains(p.key)) return 'style';
    if (p.key == 'actid') return 'topic';
    if ({'categoryId', 'secondCategoryId', 'cateId'}.contains(p.key)) {
      return 'podcastCategory';
    }
    if (p.key == 'sid') return e.route == '/cloud/match' ? 'cloudSong' : 'song';
    if (p.key == 'asid') return 'song';
    if ({'evId'}.contains(p.key)) return 'event';
    if ({'taskId', 'taskid', 'userTaskId'}.contains(p.key)) return 'yunbeiTask';
    if ({'rid', 'radioId', 'voiceListId'}.contains(p.key)) return 'podcast';
    if ({'artistId'}.contains(p.key)) return 'artist';
    if ({'albumId'}.contains(p.key)) return 'album';
    if ({'mvid', 'mvId', 'vid'}.contains(p.key)) return 'mv';
    if ({'programId'}.contains(p.key)) return 'program';
    if ({
      'songId',
      'songid',
      'targetSongId',
      'formerSongId',
      'tracks',
      'ids',
    }.contains(p.key)) {
      return 'song';
    }
    if (p.key != 'id') return null;
    if (e.route == '/musician/cloudbean/obtain') return 'musicianTask';
    if (e.route.startsWith('/ugc/')) return e.route.split('/')[2];
    if (e.route.startsWith('/user/cloud')) return 'cloudSong';
    if (e.route.startsWith('/dj') || e.route.startsWith('/voicelist')) {
      return 'podcast';
    }
    if (e.route.startsWith('/mv') || e.route == '/video/sub') return 'mv';
    if (e.route.startsWith('/playlist') ||
        e.route == '/top/list' ||
        e.route == '/related/playlist') {
      return 'playlist';
    }
    if (e.route.startsWith('/artist')) return 'artist';
    if (e.route.startsWith('/album') || e.route.startsWith('/digitalAlbum')) {
      return 'album';
    }
    if (e.route.startsWith('/song') ||
        e.route.startsWith('/simi/song') ||
        e.route.startsWith('/lyric') ||
        e.route == '/check/music' ||
        e.route == '/like' ||
        e.route.startsWith('/sheet')) {
      return 'song';
    }
    return 'song';
  }

  Future<void> _chooseEntity(NeteaseParameter p) async {
    final kind = _pickerKind(p);
    if (kind == null || !_current) return;
    final picked = await Navigator.of(context).push<NeteasePickedEntity>(
      MestingPageRoute(
        builder: (_) => NeteaseEntityPicker(kind: kind, includeDetails: true),
      ),
    );
    if (picked == null || !mounted || !_current) return;
    final id = picked.id;
    final multiple = {'ids', 'tracks', 'user_ids'}.contains(p.key);
    final current = _fields[p.key]!.text.trim();
    setState(() {
      _fields[p.key]!.text = multiple && current.isNotEmpty
          ? '$current,$id'
          : id;
      _selections[p.key] = multiple && current.isNotEmpty
          ? '${_selections[p.key] ?? '已选内容'}、${picked.name}'
          : picked.name;
      // Dependent metadata follows the selected object, rather than asking a
      // person to copy task periods, creator IDs or voice category IDs.
      for (final key in [
        'period',
        'categoryId',
        'secondCategoryId',
        'coverImgId',
        'voiceListId',
      ]) {
        if (_fields.containsKey(key) && picked.raw[key] != null) {
          _fields[key]!.text = '${picked.raw[key]}';
        }
      }
      if (e.route == '/playlist/update' && p.key == 'id') {
        _fields['name']?.text = picked.name;
        _fields['desc']?.text = '${picked.raw['description'] ?? ''}';
        _fields['tags']?.text = (picked.raw['tags'] as List? ?? const []).join(
          ';',
        );
      }
    });
    if (!e.write &&
        _params
            .where((p) => p.required)
            .every((p) => _fields[p.key]!.text.isNotEmpty)) {
      await _load();
    }
  }

  String _dateLabel(String value) {
    final date =
        DateTime.tryParse(value) ??
        DateTime.fromMillisecondsSinceEpoch(
          int.tryParse(value) ?? DateTime.now().millisecondsSinceEpoch,
        );
    return '${date.year}年${date.month}月${date.day}日';
  }

  Future<void> _pickDate(NeteaseParameter p) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted || !_current) return;
    setState(
      () => _fields[p.key]!.text =
          e.route == '/musician/play/trend' || p.key == 'date'
          ? '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
          : '${date.millisecondsSinceEpoch}',
    );
  }
}

class NeteaseContentDetailPage extends StatefulWidget {
  const NeteaseContentDetailPage({
    required this.row,
    this.category,
    this.seed = const {},
    super.key,
  });
  final NeteaseContentRow row;
  final String? category;
  final Map<String, Object?> seed;
  @override
  State<NeteaseContentDetailPage> createState() =>
      _NeteaseContentDetailPageState();
}

class _NeteaseContentDetailPageState extends State<NeteaseContentDetailPage> {
  NeteaseContentRow get row => widget.row;
  String? get category => widget.category;
  Map<String, Object?> get seed => widget.seed;
  late NeteaseContent _details;
  late List<MapEntry<String, String>> _detailFacts;

  void _parseDetails() {
    _details = NeteaseContent.parse(row.raw, '/content/detail');
    _detailFacts = _details.facts.entries.toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _parseDetails();
  }

  @override
  void didUpdateWidget(NeteaseContentDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.row, row)) _parseDetails();
  }

  @override
  Widget build(BuildContext context) {
    final details = _details;
    return PlatformPageFrame(
      title: row.kind == 'message' ? '消息内容' : '内容详情',
      child: buildPlatformLazyList(
        padding: BetaContentInsets.musicPaddingOf(
          context,
          const EdgeInsets.all(24),
        ),
        header: [
          Text(row.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          SelectableText(row.subtitle),
        ],
        itemCount: _detailFacts.length + details.rows.length,
        itemBuilder: (context, index) {
          if (index < _detailFacts.length) {
            final fact = _detailFacts[index];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('${fact.key}：${fact.value}'),
            );
          }
          final item = details.rows[index - _detailFacts.length];
          return ListTile(
            title: Text(item.title),
            subtitle: item.subtitle.isEmpty ? null : Text(item.subtitle),
            onTap: () => _push(
              context,
              NeteaseContentDetailPage(
                row: item,
                category: category,
                seed: seed,
              ),
            ),
          );
        },
        footer: [
          const SizedBox(height: 24),
          BetaGlassButton(
            onPressed: () => _push(
              context,
              NeteaseFullHubPage(
                category: row.kind == 'content' ? category : null,
                entityKind: row.kind == 'content' ? null : row.kind,
                seed: {
                  ...seed,
                  ...row.raw.map(
                    (k, v) => MapEntry(k, v is String || v is num ? v : null),
                  ),
                  'id': row.kind == 'comment' ? seed['id'] : row.id,
                  'uid': row.id,
                  'user_ids': row.raw['fromUser'] is Map
                      ? '${(row.raw['fromUser'] as Map)['userId']}'
                      : row.id,
                  'commentId': row.id,
                  'cid': row.id,
                },
              ),
            ),
            child: const Text('相关功能'),
          ),
        ],
      ),
    );
  }
}
