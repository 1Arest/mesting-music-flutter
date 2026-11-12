import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/beta_glass_scroll_body.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../library/library_providers.dart';
import '../../downloads/audio_download_storage.dart';
import '../playlist_audit.dart';

/// A complete snapshot is read from the account-owned repository. Every removal rechecks owner
/// and membership; audit findings never delete files or platform favourites.
class PlaylistAuditPage extends ConsumerStatefulWidget {
  const PlaylistAuditPage({required this.playlistId, super.key});
  final String playlistId;
  @override
  ConsumerState<PlaylistAuditPage> createState() => _AuditState();
}

class _AuditState extends ConsumerState<PlaylistAuditPage> {
  String? _owner, _error;
  bool _busy = true;
  List<Track> _tracks = [], _unreadable = [];
  final _selected = <String>{};
  @override
  void initState() {
    super.initState();
    Future.microtask(_scan);
  }

  Future<void> _scan() async {
    setState(() {
      _busy = true;
      _error = null;
      _selected.clear();
    });
    final repository = ref.read(libraryRepositoryProvider);
    final owner = repository.ownerId;
    try {
      final tracks = await repository
          .watchPlaylistTracks(widget.playlistId)
          .first;
      final unavailable = <Track>[];
      for (final t in tracks) {
        if (!mounted || ref.read(libraryRepositoryProvider).ownerId != owner) {
          return;
        }
        final uri = Uri.tryParse(t.audioAsset);
        if (uri?.scheme == 'content') {
          if (!await const AudioDownloadStorage().readable(t.audioAsset)) {
            unavailable.add(t);
          }
        } else if (uri?.scheme == 'file' || t.audioAsset.startsWith('/')) {
          final f = uri?.scheme == 'file'
              ? File.fromUri(uri!)
              : File(t.audioAsset);
          if (!await f.exists()) unavailable.add(t);
        }
      }
      if (mounted && ref.read(libraryRepositoryProvider).ownerId == owner) {
        setState(() {
          _owner = owner;
          _tracks = tracks;
          _unreadable = unavailable;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '体检未完成，请检查文件授权后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final repository = ref.read(libraryRepositoryProvider);
    if (repository.ownerId != _owner || _selected.isEmpty) return;
    final ids = Set<String>.of(_selected);
    final approved = await showLiquidGlassBottomSheet<bool>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('从歌单移除 ${ids.length} 首歌曲？'),
              const SizedBox(height: 16),
              const Text('仅移除歌单关联，收藏和音乐文件保留。'),
              CupertinoButton(
                onPressed: () => Navigator.pop(sheet, true),
                child: const Text('移除所选歌曲'),
              ),
              CupertinoButton(
                onPressed: () => Navigator.pop(sheet, false),
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted ||
        approved != true ||
        ref.read(libraryRepositoryProvider).ownerId != _owner) {
      return;
    }
    setState(() => _busy = true);
    try {
      for (final id in ids) {
        if (ref.read(libraryRepositoryProvider).ownerId != _owner) return;
        await repository.removeTrackFromPlaylist(widget.playlistId, id);
      }
      await _scan();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '部分操作未完成，请重新体检';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(libraryRepositoryProvider).ownerId;
    if (_owner != null && owner != _owner) {
      return Scaffold(
        appBar: AppBar(title: const Text('歌单体检')),
        body: const Center(child: Text('账号已变化，请返回重新打开')),
      );
    }
    final duplicates = duplicateRecordings(_tracks);
    final restricted = _tracks.where(hasRecordedRestriction).toList();
    Widget row(Track t) => ListTile(
      leading: CupertinoCheckbox(
        value: _selected.contains(t.id),
        onChanged: _busy
            ? null
            : (v) => setState(() {
                if (v == true) {
                  _selected.add(t.id);
                } else {
                  _selected.remove(t.id);
                }
              }),
      ),
      title: Text(t.title),
      subtitle: Text('${t.artist} · ${t.source.name}'),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('歌单体检'),
        actions: [
          CupertinoButton(
            onPressed: _busy ? null : _scan,
            child: const Text('重新检查'),
          ),
        ],
      ),
      body: BetaGlassScrollBody(
        padding: const EdgeInsets.all(20),
        children: [
          if (_busy) const Center(child: CupertinoActivityIndicator()),
          if (_error != null) Text(_error!),
          const Text(
            '歌单体检',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          const Text('疑似重复仅供核对，请自行选择保留版本。文件不可读也可能是授权变化。在线歌曲不会因一次网络失败被判定失效。'),
          const SizedBox(height: 20),
          Text('疑似重复 · ${duplicates.length} 组'),
          for (final group in duplicates)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(children: group.map(row).toList()),
            ),
          const SizedBox(height: 20),
          Text('本地文件不可读取 · ${_unreadable.length} 首'),
          ..._unreadable.map(row),
          const SizedBox(height: 20),
          Text('已有不可播提示 · ${restricted.length} 首'),
          const Text('来自已保存的平台信息，权限可能变化，建议先尝试重新播放。'),
          ...restricted.map(
            (t) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [row(t), Text(t.availabilityMessage)],
            ),
          ),
          if (!_busy &&
              duplicates.isEmpty &&
              _unreadable.isEmpty &&
              restricted.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Text('未发现疑似重复或不可读取的本地文件。'),
            ),
          BetaGlassButton(
            onPressed: _busy || _selected.isEmpty ? null : _remove,
            child: Text('移除所选 ${_selected.length} 首'),
          ),
        ],
      ),
    );
  }
}
