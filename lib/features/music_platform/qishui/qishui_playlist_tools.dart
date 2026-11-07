import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/track.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../../shared/widgets/music_activity_indicator.dart';
import '../../../shared/widgets/music_feature_page.dart';
import '../music_platform_providers.dart';
import 'qishui_models.dart';
import 'qishui_page_scope.dart';
import 'qishui_providers.dart';

/// Shared identity heading keeps the management drawer and target picker tied
/// to the actual returned playlist; no screenshot account data is embedded.
class QishuiPlaylistSheetHeading extends StatelessWidget {
  const QishuiPlaylistSheetHeading({
    required this.playlist,
    this.currentCount,
    super.key,
  });
  final QishuiPlaylist playlist;
  final int? currentCount;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 64,
          height: 64,
          child: playlist.cover.isEmpty
              ? ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Icon(
                    playlist.kind == 1
                        ? Icons.favorite_rounded
                        : Icons.library_music_rounded,
                  ),
                )
              : ArtworkImage(uri: playlist.cover),
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              playlist.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              [
                playlist.ownerName.isEmpty ? '汽水音乐' : playlist.ownerName,
                '${currentCount ?? playlist.count} 首',
              ].join(' · '),
            ),
          ],
        ),
      ),
    ],
  );
}

Future<bool> confirmQishuiPlaylistRemoval(
  BuildContext context,
  int count,
) async =>
    await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialog) => AlertDialog(
        title: Text('从汽水歌单移除 $count 首歌曲？'),
        content: const Text('该操作会同步到你的汽水账号。已下载的本地文件不会删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('确认移除'),
          ),
        ],
      ),
    ) ==
    true;

Future<bool?> showQishuiPlaylistPrivacy(
  BuildContext context,
  bool? current,
) => showLiquidGlassBottomSheet<bool>(
  context: context,
  useRootNavigator: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (sheet) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('歌单隐私', style: Theme.of(sheet).textTheme.titleLarge),
        const SizedBox(height: 12),
        ListTile(
          leading: const Icon(Icons.lock_outline),
          title: const Text('仅自己可见'),
          trailing: current == true ? const Icon(Icons.check_rounded) : null,
          onTap: () => Navigator.pop(sheet, true),
        ),
        ListTile(
          leading: const Icon(Icons.public),
          title: const Text('公开歌单'),
          trailing: current == false ? const Icon(Icons.check_rounded) : null,
          onTap: () => Navigator.pop(sheet, false),
        ),
      ],
    ),
  ),
);

/// Return a target only. The caller retains selected recordings and submits
/// after the drawer closes and ownership is checked again. Reads are cancelled
/// when the drawer closes, independently from the parent page's lifetime.
Future<QishuiPlaylist?> chooseQishuiPlaylistDestination(
  BuildContext context,
  WidgetRef ref, {
  String? excludeId,
  required bool Function() ownerIsCurrent,
}) async {
  final music = ref.read(qishuiRepositoryProvider);
  final owner = ref.read(platformAccountProvider).value;
  final abort = Completer<void>();
  var lists = music.playlists(abortTrigger: abort.future);
  Object? result;
  try {
    result = await showLiquidGlassBottomSheet<Object>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (context, refresh) => Consumer(
          builder: (context, watch, _) {
            final account = watch.watch(platformAccountProvider).value;
            if (account?.ownerId != owner?.ownerId ||
                account?.token != owner?.token ||
                !ownerIsCurrent()) {
              return const Padding(
                padding: EdgeInsets.all(28),
                child: Text('账号已变化，请关闭后重新操作'),
              );
            }
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .72,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
                    child: Text(
                      '添加到汽水歌单',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('新建歌单'),
                    onTap: () => Navigator.pop(sheet, 'create'),
                  ),
                  Flexible(
                    child: FutureBuilder<List<QishuiPlaylist>>(
                      future: lists,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return MusicFeatureMessage(
                            message: '${snapshot.error}',
                            onRetry: () => refresh(() {
                              lists = music.playlists(
                                abortTrigger: abort.future,
                              );
                            }),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: MusicActivityIndicator()),
                          );
                        }
                        final values = snapshot.data!
                            .where(
                              (playlist) =>
                                  playlist.id != excludeId &&
                                  (playlist.ownerId == owner?.userId ||
                                      playlist.kind == 1),
                            )
                            .toList();
                        if (values.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('暂无可添加的歌单，可以新建一个'),
                          );
                        }
                        return ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: values.length,
                          itemBuilder: (context, index) => ListTile(
                            title: Text(
                              values[index].name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text('${values[index].count} 首歌曲'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.pop(sheet, values[index]),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  } finally {
    if (!abort.isCompleted) abort.complete();
  }
  if (!context.mounted || !ownerIsCurrent() || !music.current) return null;
  if (result is QishuiPlaylist) return result;
  if (result != 'create') return null;
  final name = await _askPlaylistName(context);
  if (name == null || !context.mounted || !ownerIsCurrent()) return null;
  // This is an explicit Create submission, not an optimistic local placeholder.
  return music.createPlaylist(name);
}

Future<String?> askQishuiPlaylistName(BuildContext context) =>
    _askPlaylistName(context);

Future<String?> _askPlaylistName(BuildContext context) => showDialog<String>(
  context: context,
  useRootNavigator: true,
  builder: (_) => const _QishuiPlaylistNameDialog(),
);

/// The route owns its controller until its exit transition actually unmounts.
class _QishuiPlaylistNameDialog extends StatefulWidget {
  const _QishuiPlaylistNameDialog();
  @override
  State<_QishuiPlaylistNameDialog> createState() =>
      _QishuiPlaylistNameDialogState();
}

class _QishuiPlaylistNameDialogState extends State<_QishuiPlaylistNameDialog> {
  final _name = TextEditingController();
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('新建汽水歌单'),
    content: TextField(
      controller: _name,
      maxLength: 30,
      autofocus: true,
      decoration: const InputDecoration(labelText: '歌单名称'),
      onChanged: (_) => setState(() {}),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: _name.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _name.text.trim()),
        child: const Text('创建'),
      ),
    ],
  );
}

/// Search results are a selection source, not an implicit mutation. Pressing
/// Add returns a stable list to the owning playlist page, which performs the
/// write and server readback under its original credential.
class QishuiPlaylistAddSongsPage extends ConsumerStatefulWidget {
  const QishuiPlaylistAddSongsPage({super.key});
  @override
  ConsumerState<QishuiPlaylistAddSongsPage> createState() =>
      _QishuiPlaylistAddSongsPageState();
}

class _QishuiPlaylistAddSongsPageState
    extends ConsumerState<QishuiPlaylistAddSongsPage>
    with QishuiOwnedPage<QishuiPlaylistAddSongsPage> {
  final _query = TextEditingController();
  final _selected = <String, Track>{};
  Future<List<Track>>? _results;

  void _search() {
    final query = _query.text.trim();
    if (query.isEmpty || !ownerCurrent) return;
    setState(() {
      _results = ref
          .read(qishuiRepositoryProvider)
          .search(query, abortTrigger: pageAbort);
    });
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!watchOwner()) return changedAccount();
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 68,
        leading: const Center(child: BetaGlassBackButton()),
        title: const Text('添加歌曲'),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: BetaGlassField(
                child: TextField(
                  controller: _query,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    labelText: '搜索汽水歌曲',
                    suffixIcon: IconButton(
                      tooltip: '搜索',
                      onPressed: _search,
                      icon: const Icon(Icons.search),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _results == null
                  ? const MusicFeatureMessage(message: '搜索后勾选要添加的汽水歌曲')
                  : FutureBuilder<List<Track>>(
                      future: _results,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return MusicFeatureMessage(
                            message: '${snapshot.error}',
                            onRetry: _search,
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(child: MusicActivityIndicator());
                        }
                        if (snapshot.data!.isEmpty) {
                          return const MusicFeatureMessage(message: '没有找到歌曲');
                        }
                        return ListView.builder(
                          itemCount: snapshot.data!.length,
                          itemBuilder: (context, index) {
                            final track = snapshot.data![index];
                            return CheckboxListTile(
                              value: _selected.containsKey(track.id),
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                track.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onChanged: (_) => setState(() {
                                if (_selected.remove(track.id) == null) {
                                  _selected[track.id] = track;
                                }
                              }),
                            );
                          },
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: BetaGlassButton(
                  blue: true,
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.pop(
                          context,
                          List<Track>.unmodifiable(_selected.values),
                        ),
                  child: Text('添加 ${_selected.length} 首歌曲'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
