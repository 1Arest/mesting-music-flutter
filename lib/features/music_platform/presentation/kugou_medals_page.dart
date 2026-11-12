import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_music_chrome_scope.dart';
import '../../../shared/widgets/beta_page_motion.dart';
import '../data/kugou_medal_repository.dart';
import '../data/kugou_official_api.dart';
import '../domain/kugou_medal_catalog.dart';
import '../domain/platform_session.dart';
import '../kugou_listening_profile_providers.dart';
import '../music_platform_providers.dart';
import 'kugou_official_page.dart';
import '../../themes/music_typography.dart';

final kugouMedalRepositoryProvider = Provider<KugouMedalRepository>(
  (ref) => KugouMedalRepository(
    ref.watch(kugouListeningProfileRepositoryProvider).official,
  ),
);

/// 分类和分页各自保留成功内容；刷新失败不清空徽章或滚动状态。
class KugouMedalGalleryPage extends ConsumerStatefulWidget {
  const KugouMedalGalleryPage({required this.session, super.key});
  final PlatformSession session;
  @override
  ConsumerState<KugouMedalGalleryPage> createState() =>
      _KugouMedalGalleryState();
}

class _CategoryCache {
  final items = <KugouMedalItem>[];
  int page = 0;
  bool hasMore = true, busy = false;
  String? error;
}

abstract class _OwnerState<T extends ConsumerStatefulWidget>
    extends ConsumerState<T> {
  PlatformSession get owner;
  bool get current {
    if (!mounted) return false;
    final active = ref.read(platformAccountProvider).value;
    return mounted &&
        active?.platform == MusicPlatform.kugou &&
        active?.userId == owner.userId &&
        active?.token == owner.token &&
        active?.kugouStandardToken == owner.kugouStandardToken;
  }

  KugouMedalRepository get repository => ref.read(kugouMedalRepositoryProvider);
  String message(Object error) =>
      error is KugouOfficialException ? error.message : '徽章资料读取失败，请重试';
  bool watchOwner() {
    final active = ref.watch(platformAccountProvider).value;
    return active?.platform == MusicPlatform.kugou &&
        active?.userId == owner.userId &&
        active?.token == owner.token &&
        active?.kugouStandardToken == owner.kugouStandardToken;
  }
}

class _KugouMedalGalleryState extends _OwnerState<KugouMedalGalleryPage> {
  @override
  PlatformSession get owner => widget.session;
  KugouMedalSummary? _summary;
  final _cache = <String, _CategoryCache>{};
  String? _category, _group, _error;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_loading || !current) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await repository.summary(owner);
      if (!current) return;
      setState(() {
        _summary = data;
        final categories = data.categories
            .expand((c) => c.children.isEmpty ? [c] : c.children)
            .toList();
        if (!categories.any((c) => c.type == _category)) {
          _category = categories.firstOrNull?.type;
        }
        _group = data.categories
            .where(
              (c) =>
                  c.type == _category ||
                  c.children.any((s) => s.type == _category),
            )
            .firstOrNull
            ?.type;
      });
      if (_category != null) await _load(_category!, reset: true);
    } catch (error) {
      if (current) setState(() => _error = message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _load(String type, {bool reset = false}) async {
    final cache = _cache.putIfAbsent(type, _CategoryCache.new);
    if (cache.busy || !current || !reset && !cache.hasMore) return;
    setState(() {
      cache.busy = true;
      cache.error = null;
    });
    try {
      final data = await repository.list(
        owner,
        type,
        page: reset ? 1 : cache.page + 1,
      );
      if (!current) return;
      setState(() {
        if (reset) cache.items.clear();
        final keys = cache.items.map((i) => i.key).toSet();
        cache.items.addAll(data.items.where((i) => keys.add(i.key)));
        cache.page = data.page;
        cache.hasMore = data.hasMore;
      });
    } catch (error) {
      if (current) setState(() => cache.error = message(error));
    } finally {
      if (mounted) setState(() => cache.busy = false);
    }
  }

  Future<void> _detail(KugouMedalItem item) async {
    await Navigator.of(context).push<void>(
      betaContentRoute(KugouMedalDetailPage(owner: owner, item: item)),
    );
    if (current) unawaited(_refresh());
  }

  @override
  Widget build(BuildContext context) {
    final valid = watchOwner();
    final cache = _cache[_category];
    final categories = _summary?.categories ?? const <KugouMedalCategory>[];
    final group = categories.where((c) => c.type == _group).firstOrNull;
    return _MedalScaffold(
      title: '勋章收藏馆',
      refresh: _loading ? null : _refresh,
      child: !valid
          ? const Center(child: Text('账号已变化，请返回后重新打开'))
          : RefreshIndicator(
              onRefresh: _refresh,
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  owner.nickname.isEmpty
                                      ? '我的徽章'
                                      : owner.nickname,
                                  style: const TextStyle(
                                    fontSize: MusicTypography.titleSize,
                                    fontWeight: MusicTypography.titleWeight,
                                  ),
                                ),
                              ),
                              Text(
                                _summary?.total == null
                                    ? '— 枚'
                                    : '${_summary!.total} 枚',
                                style: const TextStyle(
                                  fontSize: MusicTypography.sectionTitleSize,
                                  fontWeight: MusicTypography.titleWeight,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          BetaGlassButton(
                            label: '佩戴管理',
                            height: 48,
                            onPressed: () async {
                              await Navigator.of(context).push<void>(
                                betaContentRoute(
                                  KugouMedalWearPage(owner: owner),
                                ),
                              );
                              if (current) unawaited(_refresh());
                            },
                            child: const Text('佩戴管理'),
                          ),
                          if (_error != null)
                            _Feedback(_error!, retry: _refresh),
                          if (_loading && _summary == null)
                            const Padding(
                              padding: EdgeInsets.all(30),
                              child: Center(child: BetaActivityIndicator()),
                            ),
                          const SizedBox(height: 15),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (final category in categories)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 7),
                                    child: ChoiceChip(
                                      label: Text(category.name),
                                      selected: _group == category.type,
                                      onSelected: (_) {
                                        final next =
                                            category.children.firstOrNull ??
                                            category;
                                        setState(() {
                                          _group = category.type;
                                          _category = next.type;
                                        });
                                        if (!_cache.containsKey(next.type)) {
                                          unawaited(_load(next.type));
                                        }
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (group?.children.isNotEmpty == true) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 7,
                              runSpacing: 5,
                              children: [
                                for (final choice in group!.children)
                                  ChoiceChip(
                                    label: Text(
                                      '${choice.name}${choice.count == null ? '' : ' ${choice.count}'}',
                                    ),
                                    selected: _category == choice.type,
                                    onSelected: (_) {
                                      setState(() => _category = choice.type);
                                      if (!_cache.containsKey(choice.type)) {
                                        unawaited(_load(choice.type));
                                      }
                                    },
                                  ),
                              ],
                            ),
                          ],
                          if (cache?.error != null)
                            _Feedback(
                              cache!.error!,
                              retry: () =>
                                  _load(_category!, reset: cache.page == 0),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (cache != null)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverLayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.crossAxisExtent;
                          final large =
                              MediaQuery.textScalerOf(context).scale(14) > 21;
                          return SliverGrid.builder(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: large
                                      ? 2
                                      : (width / 150).floor().clamp(2, 4),
                                  mainAxisExtent:
                                      140 +
                                      MediaQuery.textScalerOf(
                                            context,
                                          ).scale(14) *
                                          5,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                ),
                            itemCount: cache.items.length,
                            itemBuilder: (_, i) => _MedalTile(
                              item: cache.items[i],
                              onTap: () => _detail(cache.items[i]),
                            ),
                          );
                        },
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: cache?.busy == true
                          ? const Center(child: BetaActivityIndicator())
                          : cache == null
                          ? const SizedBox.shrink()
                          : cache.items.isEmpty
                          ? const Center(child: Text('这个分类暂未返回徽章'))
                          : cache.hasMore
                          ? Center(
                              child: TextButton(
                                onPressed: () => _load(_category!),
                                child: const Text('加载更多徽章'),
                              ),
                            )
                          : const Center(child: Text('已显示全部徽章')),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class KugouMedalDetailPage extends ConsumerStatefulWidget {
  const KugouMedalDetailPage({
    required this.owner,
    required this.item,
    super.key,
  });
  final PlatformSession owner;
  final KugouMedalItem item;
  @override
  ConsumerState<KugouMedalDetailPage> createState() => _MedalDetailState();
}

class _MedalDetailState extends _OwnerState<KugouMedalDetailPage> {
  @override
  PlatformSession get owner => widget.owner;
  KugouMedalDetail? _detail;
  String? _error;
  bool _busy = false, _uncertain = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (_busy || !current) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await repository.detail(owner, widget.item);
      if (current) {
        setState(() {
          _detail = result;
          _uncertain = false;
        });
      }
    } catch (error) {
      if (current) setState(() => _error = message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _write(KugouMedalItem item, {bool receive = false}) async {
    if (_busy || _uncertain || !current) return;
    setState(() {
      _busy = true;
      _uncertain = true;
      _error = null;
    });
    try {
      if (receive) {
        await repository.receive(owner, item);
      } else {
        await repository.wear(owner, item);
      }
      final updated = await repository.detail(owner, item);
      if (current) {
        setState(() {
          _detail = updated;
          _uncertain = false;
        });
      }
    } catch (_) {
      if (current) setState(() => _error = '操作结果尚未核对，请先刷新查看官方状态。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final valid = watchOwner();
    final levels = _detail?.levels ?? [widget.item];
    return _MedalScaffold(
      title: widget.item.name.isEmpty ? '徽章详情' : widget.item.name,
      refresh: _busy ? null : _load,
      child: !valid
          ? const Center(child: Text('账号已变化，请返回后重新打开'))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_busy) const Center(child: BetaActivityIndicator()),
                if (_error != null) _Feedback(_error!, retry: _load),
                for (final item in levels)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(child: _MedalArt(item, size: 150)),
                          const SizedBox(height: 12),
                          Text(
                            item.name,
                            style: const TextStyle(
                              fontSize: MusicTypography.sectionTitleSize,
                              fontWeight: MusicTypography.titleWeight,
                            ),
                          ),
                          if (item.level.isNotEmpty) Text('等级 ${item.level}'),
                          Text(
                            item.expired
                                ? '已到期'
                                : item.earned
                                ? '已获得'
                                : '尚未获得',
                          ),
                          if (item.receivedAt.isNotEmpty)
                            Text('获得日期 ${item.receivedAt}'),
                          if (item.earned && _detail != null)
                            TextButton(
                              onPressed: _busy || _uncertain
                                  ? null
                                  : () => _write(item),
                              child: Text(
                                item.selected(1) > 0 ? '取消佩戴' : '佩戴这枚徽章',
                              ),
                            ),
                          if (item.canReceive && _detail != null)
                            TextButton(
                              onPressed: _busy || _uncertain
                                  ? null
                                  : () => _write(item, receive: true),
                              child: const Text('领取徽章'),
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                const Text(
                  '获得条件',
                  style: TextStyle(
                    fontSize: MusicTypography.headingSize,
                    fontWeight: MusicTypography.titleWeight,
                  ),
                ),
                const SizedBox(height: 10),
                for (final line in _detail?.conditions ?? const <String>[])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(line, style: const TextStyle(height: 1.55)),
                  ),
                if (_detail?.conditions.isEmpty == true)
                  const Text('这枚徽章的完整条件由官方详情页提供。'),
                if (widget.item.classifyId != null)
                  TextButton(
                    onPressed: () => openKugouOfficialPage(
                      context,
                      ref,
                      owner,
                      Uri.https(
                        'activity.kugou.com',
                        '/page/v-21847b5d/detail.html',
                        {
                          'isHideTitleBar': '1',
                          'type': widget.item.type,
                          'classifyId': '${widget.item.classifyId}',
                          if (widget.item.level.isNotEmpty)
                            'level': widget.item.level,
                        },
                      ),
                    ),
                    child: const Text('查看官方完整条件与详情'),
                  ),
              ],
            ),
    );
  }
}

/// 佩戴顺序即勾选顺序。主页5枚/评论2枚分别按官版source保存，互不覆盖。
class KugouMedalWearPage extends ConsumerStatefulWidget {
  const KugouMedalWearPage({required this.owner, super.key});
  final PlatformSession owner;
  @override
  ConsumerState<KugouMedalWearPage> createState() => _MedalWearState();
}

class _MedalWearState extends _OwnerState<KugouMedalWearPage> {
  @override
  PlatformSession get owner => widget.owner;
  int _source = 1, _page = 0;
  final _items = <KugouMedalItem>[];
  final _selected = <KugouMedalItem>[];
  bool _busy = false, _more = true, _uncertain = false;
  String? _error;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
  }

  Future<void> _load({bool reset = false}) async {
    if (_busy || !current) return;
    final generation = ++_generation;
    final source = _source;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await repository.owned(
        owner,
        source: source,
        page: reset ? 1 : _page + 1,
      );
      if (!current || generation != _generation) return;
      setState(() {
        if (reset) {
          _items.clear();
          _selected.clear();
          _uncertain = false;
        }
        final keys = _items.map((i) => i.key).toSet();
        for (final item in result.items.where((i) => keys.add(i.key))) {
          _items.add(item);
          if (item.selected(source) > 0) _selected.add(item);
        }
        _selected.sort(
          (a, b) => a.selected(source).compareTo(b.selected(source)),
        );
        _page = result.page;
        _more = result.hasMore;
      });
    } catch (error) {
      if (current && generation == _generation) {
        setState(() => _error = message(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || _uncertain || _more || !current) return;
    setState(() {
      _busy = true;
      _uncertain = true;
      _error = null;
    });
    try {
      await repository.select(owner, _source, _selected);
      if (mounted && current) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('佩戴设置已提交，正在核对')));
      }
    } catch (_) {
      if (current) setState(() => _error = '保存结果尚未核对，请刷新查看官方佩戴状态。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    // 只读取核对，不自动重复提交；未确认前保持写入口锁定。
    if (current) await _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final valid = watchOwner();
    final limit = _source == 1 ? 5 : 2;
    return _MedalScaffold(
      title: '佩戴管理',
      refresh: _busy ? null : () => _load(reset: true),
      child: !valid
          ? const Center(child: Text('账号已变化，请返回后重新打开'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 1, label: Text('个人主页')),
                      ButtonSegment(value: 2, label: Text('歌曲评论')),
                    ],
                    selected: {_source},
                    onSelectionChanged: _busy
                        ? null
                        : (values) {
                            setState(() {
                              _source = values.single;
                              _items.clear();
                              _selected.clear();
                              _page = 0;
                              _more = true;
                            });
                            unawaited(_load(reset: true));
                          },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('已选 ${_selected.length}/$limit · 按选择顺序显示'),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _Feedback(_error!, retry: () => _load(reset: true)),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(14),
                    itemCount: _items.length + 1,
                    itemBuilder: (context, i) {
                      if (i == _items.length) {
                        return _busy
                            ? const Center(child: BetaActivityIndicator())
                            : _more
                            ? TextButton(
                                onPressed: () => _load(),
                                child: const Text('加载更多可佩戴徽章'),
                              )
                            : const Padding(
                                padding: EdgeInsets.all(20),
                                child: Center(child: Text('已读取全部可佩戴徽章')),
                              );
                      }
                      final item = _items[i];
                      final selected = _selected.indexWhere(
                        (v) => v.key == item.key,
                      );
                      return CheckboxListTile(
                        value: selected >= 0,
                        secondary: _MedalArt(item, size: 48),
                        title: Text(item.name),
                        subtitle: Text(
                          selected >= 0
                              ? '显示顺序 ${selected + 1}'
                              : item.level.isEmpty
                              ? '未选择'
                              : '等级 ${item.level}',
                        ),
                        onChanged: _busy || _uncertain || _more
                            ? null
                            : (checked) {
                                if (checked == true &&
                                    _selected.length >= limit) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('这里最多可佩戴 $limit 枚徽章'),
                                    ),
                                  );
                                  return;
                                }
                                setState(() {
                                  if (selected >= 0) {
                                    _selected.removeAt(selected);
                                  } else {
                                    _selected.add(item);
                                  }
                                });
                              },
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: BetaGlassButton(
                      label: '保存佩戴设置',
                      height: 52,
                      onPressed: _busy || _more || _uncertain ? null : _save,
                      child: Text(_more ? '先读取全部徽章' : '保存佩戴设置'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _MedalScaffold extends StatelessWidget {
  const _MedalScaffold({
    required this.title,
    required this.child,
    this.refresh,
  });
  final String title;
  final Widget child;
  final VoidCallback? refresh;
  @override
  Widget build(BuildContext context) => BetaMusicChromeCover(
    child: Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
              child: Row(
                children: [
                  const BetaGlassBackButton(),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize:
                            MediaQuery.textScalerOf(context).scale(14) > 21
                            ? MusicTypography.headingSize
                            : MusicTypography.sectionTitleSize,
                        fontWeight: MusicTypography.titleWeight,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '刷新',
                    onPressed: refresh,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    ),
  );
}

class _Feedback extends StatelessWidget {
  const _Feedback(this.message, {required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        TextButton(onPressed: retry, child: const Text('刷新核对')),
      ],
    ),
  );
}

class _MedalArt extends StatelessWidget {
  const _MedalArt(this.item, {required this.size});
  final KugouMedalItem item;
  final double size;
  @override
  Widget build(BuildContext context) => item.image.isEmpty
      ? SizedBox(
          width: size,
          height: size,
          child: Icon(
            Icons.workspace_premium_outlined,
            size: size * .6,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        )
      : Opacity(
          opacity: item.earned ? 1 : .4,
          child: ArtworkImage(
            uri: item.image,
            width: size,
            height: size,
            fit: BoxFit.contain,
          ),
        );
}

class _MedalTile extends StatelessWidget {
  const _MedalTile({required this.item, required this.onTap});
  final KugouMedalItem item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _MedalArt(item, size: 92),
            const SizedBox(height: 8),
            Text(
              item.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: MusicTypography.titleWeight),
            ),
            const SizedBox(height: 4),
            Text(
              item.expired
                  ? '已到期'
                  : item.earned
                  ? '已获得'
                  : '尚未获得',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}
