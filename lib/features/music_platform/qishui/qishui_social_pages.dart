import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/beta_content_insets.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_page_motion.dart';
import '../../../shared/widgets/music_activity_indicator.dart';
import '../../../shared/widgets/music_feature_page.dart';
import '../../../shared/widgets/beta_secondary_music_layout.dart';
import '../presentation/platform_avatar.dart';
import 'qishui_api.dart';
import 'qishui_artist_page.dart';
import 'qishui_browse_providers.dart';
import 'qishui_page_scope.dart';
import 'qishui_search_catalog.dart';
import 'qishui_social_models.dart';
import 'qishui_social_providers.dart';

String _message(Object error) =>
    error is QishuiException ? error.message : '汽水资料暂未读取成功，请重试。';

Widget _minePage(
  BuildContext context, {
  required String title,
  required Widget child,
}) => BetaSecondaryMusicLayout.wrap(
  context,
  MusicFeaturePage(title: title, child: child),
  selectedIndex: 3,
);

void _invalidateStats(WidgetRef ref) {
  ref.invalidate(qishuiSocialStatsProvider);
  ref.invalidate(qishuiBrowseProvider('profile'));
}

/// A page owns its cursor chain, read cancellation and visible rows. A failed
/// next page keeps earlier results and never pretends they are the whole list.
class QishuiFollowListPage extends ConsumerStatefulWidget {
  const QishuiFollowListPage({required this.kind, this.userId, super.key});
  final QishuiFollowListKind kind;
  final String? userId;

  @override
  ConsumerState<QishuiFollowListPage> createState() =>
      _QishuiFollowListPageState();
}

class _QishuiFollowListPageState extends ConsumerState<QishuiFollowListPage>
    with QishuiOwnedPage<QishuiFollowListPage> {
  late final _social = ref.read(qishuiSocialRepositoryProvider);
  final _people = <String, QishuiSocialPerson>{};
  final _visited = <String>{};
  String _cursor = '';
  bool _loading = false, _hasMore = true;
  String? _busy, _notice, _continuationProblem;
  Object? _error;
  int _generation = 0;
  QishuiFollowSource _source = QishuiFollowSource.qishui;
  Completer<void> _readAbort = Completer<void>();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool refresh = false}) async {
    if (_loading || _busy != null || !ownerCurrent || !refresh && !_hasMore) {
      return;
    }
    final generation = ++_generation;
    final source = _source;
    final cursor = refresh ? '' : _cursor;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _social.list(
        widget.kind,
        userId: widget.userId,
        cursor: cursor,
        source: source,
        abortTrigger: Future.any([pageAbort, _readAbort.future]),
      );
      if (!ownerCurrent || generation != _generation) return;
      setState(() {
        if (refresh) {
          _people.clear();
          _visited.clear();
        }
        _visited.add(cursor);
        for (final person in page.items) {
          _people[person.key] = person;
        }
        _hasMore = page.hasMore && !_visited.contains(page.nextCursor);
        _continuationProblem = page.continuationProblem;
        if (page.hasMore && !_hasMore) {
          _continuationProblem = '汽水续载位置重复，请下拉刷新。';
        }
        if (_visited.length >= 500 && _hasMore) {
          _hasMore = false;
          _continuationProblem = '本次读取已达到上限，请刷新后继续核对。';
        }
        if (_hasMore) _cursor = page.nextCursor!;
      });
    } on Object catch (error) {
      if (ownerCurrent && generation == _generation) {
        setState(() => _error = error);
      }
    } finally {
      if (ownerCurrent && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _follow(QishuiSocialPerson person) async {
    final id = person.userId;
    if (_busy != null ||
        _loading ||
        id == null && person.artistId == null ||
        !ownerCurrent) {
      return;
    }
    setState(() {
      _busy = person.key;
      _notice = null;
    });
    try {
      final changed = person.artistEntity
          ? person.following == null
                ? person.withArtistMembership(
                    await _social.artistMembership(
                      person.artistId!,
                      abortTrigger: pageAbort,
                    ),
                  )
                : await _social.setArtistFollowing(
                    person,
                    person.following != true,
                    abortTrigger: pageAbort,
                  )
          : person.following == null && !person.requested
          ? await _social.userInfo(id!, abortTrigger: pageAbort)
          : await _social.setFollowing(
              id!,
              person.following != true && !person.requested,
              abortTrigger: pageAbort,
            );
      if (ownerCurrent) {
        setState(() {
          _people[person.key] = changed;
          _notice = changed.requested ? '已向对方提交关注申请' : '官方关注状态已刷新';
        });
        _invalidateStats(ref);
      }
    } on Object catch (error) {
      if (ownerCurrent) setState(() => _notice = _message(error));
    } finally {
      if (ownerCurrent) setState(() => _busy = null);
    }
  }

  void _selectSource(QishuiFollowSource source) {
    if (source == _source || _busy != null || !ownerCurrent) return;
    // Switching a source cancels its read and rejects any already-delivered
    // completion. A cursor from one official group never enters the other.
    ++_generation;
    if (!_readAbort.isCompleted) _readAbort.complete();
    _readAbort = Completer<void>();
    setState(() {
      _source = source;
      _people.clear();
      _visited.clear();
      _cursor = '';
      _hasMore = true;
      _loading = false;
      _continuationProblem = null;
      _error = null;
      _notice = null;
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    ++_generation;
    if (!_readAbort.isCompleted) _readAbort.complete();
    super.dispose();
  }

  Future<void> _open(QishuiSocialPerson person) async {
    if (_busy != null || !ownerCurrent) return;
    final page = !person.artistEntity && person.userId != null
        ? QishuiSocialUserPage(person: person)
        : QishuiArtistPage(
            artist: QishuiArtist(
              id: person.artistId!,
              name: person.name,
              artwork: person.avatar,
            ),
          );
    await Navigator.of(context).push(betaContentRoute<void>(page));
    if (ownerCurrent && !person.artistEntity && person.userId != null) {
      try {
        final updated = await _social.userInfo(
          person.userId!,
          abortTrigger: pageAbort,
        );
        if (ownerCurrent) setState(() => _people[person.key] = updated);
      } on Object {
        // Returning from a detail page must not discard the loaded list if
        // its optional state refresh fails. Pull-to-refresh remains available.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!watchOwner()) return changedAccount();
    final rows = _people.values.toList(growable: false);
    return _minePage(
      context,
      title: widget.kind.label,
      child: RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            top: 12,
            bottom: BetaContentInsets.musicBottomOf(context),
          ),
          itemCount: rows.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SegmentedButton<QishuiFollowSource>(
                      segments: [
                        for (final source in QishuiFollowSource.values)
                          ButtonSegment(
                            value: source,
                            label: Text(source.label),
                          ),
                      ],
                      selected: {_source},
                      showSelectedIcon: false,
                      onSelectionChanged: _busy == null
                          ? (values) => _selectSource(values.single)
                          : null,
                    ),
                    const SizedBox(height: 14),
                    Text('${_source.label}分组，已读取 ${rows.length} 项'),
                    if (_notice != null)
                      Semantics(liveRegion: true, child: Text(_notice!)),
                  ],
                ),
              );
            }
            if (index > rows.length) return _footer(rows.isEmpty);
            final person = rows[index - 1];
            final ownUser = person.userId == _social.owner;
            return ListTile(
              key: ValueKey('qishui-social-${person.key}'),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 8,
              ),
              leading: PlatformAvatar(url: person.avatar, size: 48),
              title: Text(
                person.name.isEmpty ? '汽水用户' : person.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                person.artistEntity ? '歌手 · 点击查看作品' : person.signature,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _open(person),
              trailing:
                  !person.artistEntity && (person.userId == null || ownUser)
                  ? const Icon(Icons.chevron_right)
                  : BetaGlassButton(
                      height: 48,
                      horizontalPadding: 12,
                      label: '${person.relationshipLabel} ${person.name}',
                      loading: _busy == person.key,
                      interactionEnabled: _busy == null && !_loading,
                      onPressed: () => _follow(person),
                      child: Text(person.relationshipLabel),
                    ),
            );
          },
        ),
      ),
    );
  }

  Widget _footer(bool empty) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        if (_loading)
          const MusicActivityIndicator()
        else if (_error != null) ...[
          Semantics(liveRegion: true, child: Text(_message(_error!))),
          const SizedBox(height: 16),
          BetaGlassButton(onPressed: _load, child: const Text('重试')),
        ] else if (_hasMore)
          BetaGlassButton(onPressed: _load, child: const Text('加载更多'))
        else
          Text(_continuationProblem ?? (empty ? '汽水暂无可显示的记录' : '已读取当前可见列表')),
      ],
    ),
  );
}

class QishuiSocialUserPage extends ConsumerStatefulWidget {
  const QishuiSocialUserPage({required this.person, super.key});
  final QishuiSocialPerson person;
  @override
  ConsumerState<QishuiSocialUserPage> createState() =>
      _QishuiSocialUserPageState();
}

class _QishuiSocialUserPageState extends ConsumerState<QishuiSocialUserPage>
    with QishuiOwnedPage<QishuiSocialUserPage> {
  late QishuiSocialPerson _person = widget.person;
  late final _social = ref.read(qishuiSocialRepositoryProvider);
  bool _busy = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() =>
      _act(() => _social.userInfo(_person.userId!, abortTrigger: pageAbort));

  Future<void> _act(Future<QishuiSocialPerson> Function() action) async {
    if (_busy || !ownerCurrent) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final next = await action();
      if (ownerCurrent) {
        setState(() => _person = next);
        _invalidateStats(ref);
      }
    } on Object catch (error) {
      if (ownerCurrent) setState(() => _notice = _message(error));
    } finally {
      if (ownerCurrent) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!watchOwner()) return changedAccount();
    return _minePage(
      context,
      title: '汽水用户',
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          BetaContentInsets.musicBottomOf(context),
        ),
        children: [
          Center(child: PlatformAvatar(url: _person.avatar, size: 84)),
          const SizedBox(height: 20),
          Text(_person.name, style: Theme.of(context).textTheme.headlineSmall),
          if (_person.signature.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_person.signature),
          ],
          const SizedBox(height: 24),
          if (_person.userId != _social.owner)
            BetaGlassButton(
              loading: _busy,
              onPressed: () => _person.following == null && !_person.requested
                  ? _load()
                  : _act(
                      () => _social.setFollowing(
                        _person.userId!,
                        _person.following != true && !_person.requested,
                        abortTrigger: pageAbort,
                      ),
                    ),
              child: Text(_person.relationshipLabel),
            ),
          const SizedBox(height: 12),
          BetaGlassButton(
            onPressed: _busy ? null : _load,
            child: const Text('刷新官方状态'),
          ),
          if (_notice != null) ...[
            const SizedBox(height: 16),
            Semantics(liveRegion: true, child: Text(_notice!)),
          ],
        ],
      ),
    );
  }
}

/// The official likes detail is an aggregate plus server-provided popup text.
/// It does not identify individual likers, so this page shows only returned
/// totals and detail rather than inventing a fan/liker activity list.
class QishuiLikesPage extends ConsumerStatefulWidget {
  const QishuiLikesPage({super.key});
  @override
  ConsumerState<QishuiLikesPage> createState() => _QishuiLikesPageState();
}

class _QishuiLikesPageState extends ConsumerState<QishuiLikesPage>
    with QishuiOwnedPage<QishuiLikesPage> {
  @override
  Widget build(BuildContext context) {
    if (!watchOwner()) return changedAccount();
    final value = ref.watch(qishuiSocialStatsProvider);
    return _minePage(
      context,
      title: '获赞明细',
      child: value.when(
        loading: () => const Center(child: MusicActivityIndicator()),
        error: (error, _) => MusicFeatureMessage(
          message: _message(error),
          onRetry: () => ref.invalidate(qishuiSocialStatsProvider),
        ),
        data: (stats) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(qishuiSocialStatsProvider);
            await ref.read(qishuiSocialStatsProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              BetaContentInsets.musicBottomOf(context),
            ),
            children: [
              Text('累计获赞', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                '${stats.likes ?? '—'}',
                style: Theme.of(context).textTheme.displaySmall,
              ),
              if (stats.commentLikes != null) ...[
                const SizedBox(height: 24),
                Text('评论获赞 ${stats.commentLikes}'),
              ],
              if (stats.likesTitle.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  stats.likesTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
              if (stats.likesDescription.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(stats.likesDescription),
              ],
              if (stats.likes == null) ...[
                const SizedBox(height: 24),
                const Text('汽水暂未返回累计获赞数据，下拉可以重新读取。'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
