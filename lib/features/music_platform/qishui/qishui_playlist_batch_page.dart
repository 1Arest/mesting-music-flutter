import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/track.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../downloads/audio_downloads_page.dart';
import '../presentation/platform_feedback.dart';
import 'qishui_models.dart';
import 'qishui_page_scope.dart';
import 'qishui_playlist_selection.dart';
import 'qishui_playlist_tools.dart';
import 'qishui_providers.dart';

/// This full-height route owns the batch toolbar above the system safe area.
/// It deliberately sits on the root Navigator so the persistent music shell
/// cannot paint a mini player or tab pill over selection actions.
class QishuiPlaylistBatchPage extends ConsumerStatefulWidget {
  const QishuiPlaylistBatchPage({
    required this.playlist,
    required this.tracks,
    required this.owned,
    super.key,
  });
  final QishuiPlaylist playlist;
  final List<Track> tracks;
  final bool owned;

  @override
  ConsumerState<QishuiPlaylistBatchPage> createState() =>
      _QishuiPlaylistBatchPageState();
}

class _QishuiPlaylistBatchPageState
    extends ConsumerState<QishuiPlaylistBatchPage>
    with QishuiOwnedPage<QishuiPlaylistBatchPage> {
  late final _music = ref.read(qishuiRepositoryProvider);
  late final QishuiPlaylistSelection _draft = QishuiPlaylistSelection(
    widget.tracks,
  );
  bool _busy = false;
  bool _changed = false;

  Future<void> _act(Future<void> Function() action) async {
    if (_busy || !ownerCurrent) return;
    setState(() => _busy = true);
    try {
      await action();
    } on Object catch (error) {
      if (mounted && ownerCurrent) showPlatformFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _done() => _act(() async {
    if (_draft.orderChanged && widget.owned) {
      await _music.reorderPlaylist(widget.playlist.id, _draft.tracks);
      _changed = true;
    }
    if (mounted && ownerCurrent) Navigator.pop(context, _changed);
  });

  Future<void> _cancel() async {
    if (_busy) return;
    if (_draft.orderChanged) {
      final discard = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (dialog) => AlertDialog(
          title: const Text('放弃排序修改？'),
          content: const Text('拖动后的顺序尚未提交到汽水。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('继续编辑'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('放弃修改'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    if (mounted) Navigator.pop(context, _changed);
  }

  Future<void> _remove() async {
    final selected = _draft.selected;
    if (selected.isEmpty || !widget.owned || _busy || !ownerCurrent) return;
    if (!await confirmQishuiPlaylistRemoval(context, selected.length) ||
        !ownerCurrent) {
      return;
    }
    await _act(() async {
      await _music.removePlaylistTracks(widget.playlist.id, selected);
      // Refresh server membership without losing a separate unsaved drag order.
      // Newly returned members are retained; removed ids cannot be resurrected
      // by a later Done tap. The repository rechecks membership before sorting.
      final refreshed = await _music.playlist(
        widget.playlist.id,
        abortTrigger: pageAbort,
      );
      if (!mounted || !ownerCurrent) return;
      setState(() {
        _draft.acceptMembership(refreshed);
        _changed = true;
      });
    });
  }

  Future<void> _addTo() async {
    final selected = _draft.selected;
    if (selected.isEmpty || _busy || !ownerCurrent) return;
    await _act(() async {
      final destination = await chooseQishuiPlaylistDestination(
        context,
        ref,
        excludeId: widget.playlist.id,
        ownerIsCurrent: () => ownerCurrent,
      );
      if (destination == null || !ownerCurrent) return;
      await _music.addPlaylistTracks(destination.id, selected);
      if (!mounted || !ownerCurrent) return;
      showMusicNotice(
        context,
        icon: Icons.check_rounded,
        title: '已添加到歌单',
        message: destination.name,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!watchOwner()) return changedAccount();
    final tracks = _draft.tracks;
    final selected = _draft.selectedCount;
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
    final topInset = MediaQuery.paddingOf(context).top;
    final selectAll = TextButton(
      onPressed: _busy ? null : () => setState(_draft.toggleAll),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      ),
      child: Text(_draft.allSelected ? '取消全选' : '全选'),
    );
    final done = TextButton(
      onPressed: _busy ? null : _done,
      child: const Text('完成'),
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(largeText ? 124 : 64),
          child: Padding(
            padding: EdgeInsets.only(top: topInset),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: largeText
                  ? Column(
                      children: [
                        const Text(
                          '批量管理',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Row(children: [selectAll, const Spacer(), done]),
                      ],
                    )
                  : Row(
                      children: [
                        SizedBox(width: 96, child: selectAll),
                        const Expanded(
                          child: Text(
                            '批量管理',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SizedBox(width: 96, child: done),
                      ],
                    ),
            ),
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
              child: Row(
                children: [
                  Expanded(child: Text('已选择 $selected 首')),
                  TextButton(
                    onPressed: _busy ? null : _cancel,
                    child: const Text('取消'),
                  ),
                ],
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: tracks.isEmpty
                  ? const Center(child: Text('歌单里还没有歌曲'))
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      buildDefaultDragHandles: false,
                      onReorder: (oldIndex, newIndex) {
                        if (_busy || !widget.owned) return;
                        setState(() => _draft.move(oldIndex, newIndex));
                      },
                      itemCount: tracks.length,
                      itemBuilder: (context, index) {
                        final track = tracks[index];
                        return CheckboxListTile(
                          key: ValueKey(track.id),
                          value: _draft.contains(track.id),
                          onChanged: _busy
                              ? null
                              : (_) => setState(() => _draft.toggle(track.id)),
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            [
                              track.artist,
                              track.album,
                            ].where((value) => value.isNotEmpty).join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          secondary: widget.owned
                              ? ReorderableDragStartListener(
                                  index: index,
                                  enabled: !_busy,
                                  child: Semantics(
                                    label: '拖动调整歌曲顺序',
                                    child: const SizedBox(
                                      width: 48,
                                      height: 48,
                                      child: Icon(Icons.drag_handle),
                                    ),
                                  ),
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
        bottomNavigationBar: LiquidGlassSurface(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: _BatchTool(
                      icon: Icons.playlist_add,
                      label: '添加到歌单',
                      onPressed: selected == 0 || _busy ? null : _addTo,
                    ),
                  ),
                  Expanded(
                    child: _BatchTool(
                      icon: Icons.download_outlined,
                      label: '下载歌曲',
                      onPressed: selected == 0 || _busy
                          ? null
                          : () => _act(
                              () => enqueueAudioDownloads(
                                context,
                                ref,
                                _draft.selected,
                              ),
                            ),
                    ),
                  ),
                  if (widget.owned)
                    Expanded(
                      child: _BatchTool(
                        icon: Icons.delete_outline,
                        label: '批量删除',
                        onPressed: selected == 0 || _busy ? null : _remove,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BatchTool extends StatelessWidget {
  const _BatchTool({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(padding: const EdgeInsets.all(8)),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon),
        const SizedBox(height: 8),
        Text(label, textAlign: TextAlign.center),
      ],
    ),
  );
}
