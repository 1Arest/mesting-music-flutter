import 'song_list_bookmark_capsule.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../models/track.dart';
import '../models/song_list_memory.dart';
import 'beta_content_insets.dart';
import 'beta_glass_controls.dart';
import 'music_notice.dart';
import 'keyboard_visibility_builder.dart';

/// The app supplies identity/storage once. Standalone widgets and host tests
/// without an owner scope retain their original behavior and do no storage IO.
class SongListOwnerScope extends InheritedWidget {
  const SongListOwnerScope({
    required this.owner,
    required this.memory,
    required super.child,
    super.key,
  });
  final String owner;
  final SongListMemory memory;
  static SongListOwnerScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SongListOwnerScope>();
  @override
  bool updateShouldNotify(SongListOwnerScope old) =>
      owner != old.owner || memory != old.memory;
}

/// One overlay per actual scrollable list. Pagination stays with its existing
/// owner; a deliberate locate action may request more pages, never playback.
class SongListTools extends StatefulWidget {
  const SongListTools({
    required this.child,
    this.listId,
    this.loadMore,
    this.hasMore = false,
    this.bottom,
    super.key,
  });
  final Widget child;
  final String? listId;
  final Future<void> Function()? loadMore;
  final bool hasMore;
  final double? bottom;
  static _SongListToolsState? _of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_SongListScope>()?.state;
  static bool contains(BuildContext context) => _of(context) != null;
  static void remember(BuildContext context, Track track) =>
      _of(context)?._remember(track);
  @override
  State<SongListTools> createState() => _SongListToolsState();
}

class _SongListToolsState extends State<SongListTools> {
  SongListOwnerScope? _owner;
  String _listId = '';
  final _rows = <_SongListEntryState>{};
  final _sources = <Object, List<Track>>{};
  final highlight = ValueNotifier<String?>(null);
  ScrollPosition? _position;
  Timer? _highlightTimer;
  bool _queued = false, _locating = false;
  int? _dismissed;
  int _epoch = 0;
  String? _logicalId() {
    if (widget.listId != null) return widget.listId;
    final route = ModalRoute.of(context)?.settings;
    if (route?.name?.isNotEmpty == true) return route!.name;
    if (route is Page && route.key is ValueKey) {
      return '${(route.key! as ValueKey).value}';
    }
    return null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final owner = SongListOwnerScope.of(context);
    final id = _logicalId() ?? '';
    if (owner?.owner != _owner?.owner ||
        owner?.memory != _owner?.memory ||
        id != _listId) {
      _owner?.memory.removeListener(_changed);
      _owner = owner;
      _listId = id;
      _owner?.memory.addListener(_changed);
      _epoch++;
      _locating = false;
      _dismissed = null;
      _sources.clear();
      _rows.clear();
      _position?.removeListener(_changed);
      _position = null;
      _highlightTimer?.cancel();
      highlight.value = null;
    }
  }

  @override
  void didUpdateWidget(covariant SongListTools old) {
    super.didUpdateWidget(old);
    if (widget.listId != old.listId) didChangeDependencies();
  }

  void _changed() {
    if (_queued || !mounted) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _remember(Track track) {
    if (_owner == null || _listId.isEmpty) return;
    _owner!.memory.remember(_owner!.owner, _listId, track);
    _dismissed = null;
  }

  void _attach(_SongListEntryState row) {
    if (!row.mounted ||
        !row._active ||
        !TickerMode.valuesOf(row.context).enabled) {
      return;
    }
    _rows.add(row);
    final source = row.widget.tracks;
    if (source != null) {
      // One current snapshot per structural list section. A refresh/sort must
      // replace its old membership, while search's local/online sections can
      // coexist. Sliver identity stays stable as lazy rows are recycled.
      _sources.removeWhere((key, _) => key is RenderObject && !key.attached);
      _sources[row.collectionAnchor ?? row.scrollPosition ?? this] = source;
      while (_sources.length > 16) {
        _sources.remove(_sources.keys.first);
      }
    }
    final position = row.scrollPosition;
    if (position != null && _position != position) {
      _position?.removeListener(_changed);
      _position = position;
      position.addListener(_changed);
    }
    _changed();
  }

  void _detach(_SongListEntryState row) {
    _rows.remove(row);
    if (_rows.isEmpty) {
      // A refresh/filter can remove the last scrollable completely. Never
      // leave the top action bound to its disposed ScrollPosition. Lazy jumps
      // reattach their new visible rows in the same frame as usual.
      _sources.clear();
      _position?.removeListener(_changed);
      _position = null;
    }
    _changed();
  }

  List<Track> _tracks() {
    final seen = <String>{};
    return [
      for (final source in _sources.values)
        ...source.where((t) => seen.add(t.id)),
    ];
  }

  bool _current(int epoch) =>
      mounted && epoch == _epoch && TickerMode.valuesOf(context).enabled;
  Future<void> _locate(SongListBookmark bookmark) async {
    if (_locating || _owner == null) return;
    final epoch = _epoch;
    setState(() => _locating = true);
    final watch = Stopwatch()..start();
    try {
      // Each successful page must add candidates. Network errors, cancellation,
      // owner changes and a bounded attempt leave the stored record intact.
      var tracks = _tracks();
      while (_current(epoch) &&
          !tracks.any((t) => t.id == bookmark.trackId) &&
          widget.hasMore &&
          widget.loadMore != null &&
          watch.elapsed < const Duration(seconds: 60)) {
        final before = tracks.length;
        await widget.loadMore!();
        await WidgetsBinding.instance.endOfFrame;
        if (!_current(epoch)) return;
        tracks = _tracks();
        if (tracks.length <= before) break;
      }
      if (!mounted || !_current(epoch)) return;
      final index = tracks.indexWhere((t) => t.id == bookmark.trackId);
      if (index < 0) throw StateError('当前列表中暂未找到这首歌，可稍后继续定位');
      // Lazy slivers need an approximate jump before their target has a render
      // object. Calibrate against an actual row, then ensureVisible precisely;
      // headers and text scaling therefore do not become hardcoded offsets.
      for (var attempt = 0; attempt < 14 && _current(epoch); attempt++) {
        _SongListEntryState? target;
        for (final row in _rows) {
          if (row.mounted && row.widget.track.id == bookmark.trackId) {
            target = row;
            break;
          }
        }
        if (target != null && mounted && target.mounted) {
          await Scrollable.ensureVisible(
            target.context,
            alignment: .35,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 280),
          );
          if (!mounted || !_current(epoch)) return;
          highlight.value = bookmark.trackId;
          _highlightTimer?.cancel();
          _highlightTimer = Timer(
            const Duration(seconds: 2),
            () => highlight.value = null,
          );
          return;
        }
        final position = _position;
        final candidates = _rows
            .where(
              (r) => r.mounted && r.scrollPosition == position && r.box != null,
            )
            .toList();
        if (position == null ||
            !position.hasContentDimensions ||
            candidates.isEmpty) {
          break;
        }
        final row = candidates.first;
        final anchor = tracks.indexWhere((t) => t.id == row.widget.track.id);
        if (anchor < 0) break;
        final box = row.box!;
        if (!mounted) return;
        final storageContext = position.context.storageContext;
        if (!storageContext.mounted) return;
        final viewport = storageContext.findRenderObject();
        final top = viewport is RenderBox
            ? viewport.localToGlobal(Offset.zero).dy
            : 0.0;
        final offset =
            position.pixels +
            box.localToGlobal(Offset.zero).dy -
            top +
            (index - anchor) * box.size.height;
        position.jumpTo(
          offset.clamp(position.minScrollExtent, position.maxScrollExtent),
        );
        await WidgetsBinding.instance.endOfFrame;
      }
      throw StateError('歌曲已加载，当前未能完成定位，请重试');
    } catch (error) {
      if (mounted && _current(epoch)) {
        showMusicNotice(
          context,
          icon: CupertinoIcons.info_circle,
          title: '$error'.replaceFirst('Bad state: ', ''),
          message: '',
        );
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _locating = false);
    }
  }

  Future<void> _top() async {
    final position = _position;
    if (position == null || !position.hasContentDimensions) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      position.jumpTo(position.minScrollExtent);
      return;
    }
    await position.animateTo(
      position.minScrollExtent,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _epoch++;
    _owner?.memory.removeListener(_changed);
    _position?.removeListener(_changed);
    _highlightTimer?.cancel();
    highlight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_owner == null || _listId.isEmpty) return widget.child;
    final bookmark = _owner!.memory.read(_owner!.owner, _listId);
    final showHint = bookmark != null && bookmark.updatedAt != _dismissed;
    final position = _position;
    final showTop =
        position != null &&
        position.hasContentDimensions &&
        position.pixels - position.minScrollExtent >
            math.max(400, position.viewportDimension * .65);
    return _SongListScope(
      state: this,
      child: KeyboardVisibilityBuilder(
        builder: (context, keyboard) => LayoutBuilder(
          builder: (context, constraints) {
            if (!constraints.hasBoundedHeight) return widget.child;
            return Stack(
              fit: StackFit.passthrough,
              children: [
                widget.child,
                if (!keyboard && (showHint || showTop))
                  Positioned(
                    key: const ValueKey('song-list-tools'),
                    right: 18,
                    bottom:
                        widget.bottom ??
                        (BetaContentInsets.musicBottomOf(context) + 10).clamp(
                          12,
                          math.max(12, constraints.maxHeight - 150),
                        ),
                    width: math.min(
                      238,
                      math.max(100, constraints.maxWidth - 36),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showTop)
                          BetaGlassButton(
                            key: const ValueKey('song-list-top'),
                            onPressed: _top,
                            width: 48,
                            height: 48,
                            horizontalPadding: 0,
                            label: '回到列表顶部',
                            child: const Icon(
                              CupertinoIcons.arrow_up,
                              size: 23,
                            ),
                          ),
                        if (showTop && showHint) const SizedBox(height: 8),
                        if (showHint)
                          SongListBookmarkCapsule(
                            title: bookmark.title,
                            cover:
                                _tracks()
                                    .where(
                                      (t) =>
                                          t.id == bookmark.trackId &&
                                          t.coverAsset.isNotEmpty,
                                    )
                                    .firstOrNull
                                    ?.coverAsset ??
                                bookmark.cover,
                            locating: _locating,
                            onLocate: () => _locate(bookmark),
                            onDismiss: () => setState(() {
                              // Stop after the in-flight request, without erasing
                              // the bookmark or starting any playback command.
                              _epoch++;
                              _locating = false;
                              _dismissed = bookmark.updatedAt;
                            }),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SongListScope extends InheritedWidget {
  const _SongListScope({required this.state, required super.child});
  final _SongListToolsState state;
  @override
  bool updateShouldNotify(_SongListScope old) => state != old.state;
}

/// Rows report their real scroll context without changing layout, playback or
/// long-press actions. Only a deliberately located song receives a temporary
/// background; scrolling does not subscribe every row to offset updates.
class SongListEntry extends StatefulWidget {
  const SongListEntry({
    required this.track,
    required this.child,
    this.tracks,
    super.key,
  });
  final Track track;
  final List<Track>? tracks;
  final Widget child;
  @override
  State<SongListEntry> createState() => _SongListEntryState();
}

class _SongListEntryState extends State<SongListEntry> {
  _SongListToolsState? _scope;
  bool _active = true;
  RenderBox? get box {
    final render = context.findRenderObject();
    return render is RenderBox && render.attached && render.hasSize
        ? render
        : null;
  }

  RenderObject? get collectionAnchor {
    RenderObject? render = context.findRenderObject();
    while (render != null) {
      if (render is RenderSliver) return render;
      render = render.parent;
    }
    return null;
  }

  ScrollPosition? get scrollPosition {
    ScrollPosition? result;
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        final state = element.state as ScrollableState;
        if (axisDirectionToAxis(state.position.axisDirection) ==
                Axis.vertical &&
            state.position.physics.allowUserScrolling) {
          result = state.position;
          return false;
        }
      }
      return true;
    });
    return result;
  }

  void _register() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_active) return;
      _scope?._attach(this);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope?._detach(this);
    _scope = context
        .dependOnInheritedWidgetOfExactType<_SongListScope>()
        ?.state;
    _register();
  }

  @override
  void didUpdateWidget(covariant SongListEntry old) {
    super.didUpdateWidget(old);
    _register();
  }

  @override
  void deactivate() {
    _active = false;
    _scope?._detach(this);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
    _register();
  }

  @override
  void dispose() {
    _scope?._detach(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _scope == null
      ? widget.child
      : ValueListenableBuilder<String?>(
          valueListenable: _scope!.highlight,
          child: widget.child,
          builder: (context, id, child) => ColoredBox(
            color: id == widget.track.id
                ? Theme.of(context).colorScheme.primary.withValues(alpha: .12)
                : Colors.transparent,
            child: child,
          ),
        );
}
