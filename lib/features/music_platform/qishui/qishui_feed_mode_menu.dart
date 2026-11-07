import 'package:flutter/material.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_glass_popover.dart';
import '../../../shared/widgets/music_activity_indicator.dart';
import 'qishui_models.dart';

/// The feed selector owns a bounded, anchored route above the shell chrome.
/// Loading and retry stay inside that route; opening it never moves playback
/// into another page or creates a sheet behind the navigation/accessory layer.
class QishuiFeedModeMenu extends StatefulWidget {
  const QishuiFeedModeMenu({
    required this.load,
    required this.onSelected,
    required this.isCurrent,
    this.selected,
    super.key,
  });
  final Future<List<QishuiFeedMode>> Function() load;
  final ValueChanged<QishuiFeedMode> onSelected;
  final bool Function() isCurrent;
  final QishuiFeedMode? selected;

  @override
  State<QishuiFeedModeMenu> createState() => _QishuiFeedModeMenuState();
}

class _QishuiFeedModeMenuState extends State<QishuiFeedModeMenu> {
  bool _open = false;

  Future<void> _show(BuildContext anchorContext) async {
    if (_open || !widget.isCurrent()) return;
    final box = anchorContext.findRenderObject()! as RenderBox;
    setState(() => _open = true);
    try {
      final selected = await showBetaGlassPopover<QishuiFeedMode>(
        context: anchorContext,
        anchor: box.localToGlobal(Offset.zero) & box.size,
        width: 300,
        label: '关闭听歌模式',
        builder: (menu) => _QishuiModeOptions(
          load: widget.load,
          selectedId: widget.selected?.id,
        ),
      );
      if (mounted && widget.isCurrent() && selected != null) {
        widget.onSelected(selected);
      }
    } finally {
      if (mounted) setState(() => _open = false);
    }
  }

  @override
  Widget build(BuildContext context) => Builder(
    builder: (anchor) => BetaGlassButton(
      key: const ValueKey('qishui-feed-mode-dropdown'),
      label: '听歌模式：${widget.selected?.name ?? '请选择'}',
      height: 46,
      horizontalPadding: 14,
      onPressed: () => _show(anchor),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              widget.selected?.name ?? '听歌模式',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 5),
          Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded),
        ],
      ),
    ),
  );
}

class _QishuiModeOptions extends StatefulWidget {
  const _QishuiModeOptions({required this.load, required this.selectedId});
  final Future<List<QishuiFeedMode>> Function() load;
  final String? selectedId;
  @override
  State<_QishuiModeOptions> createState() => _QishuiModeOptionsState();
}

class _QishuiModeOptionsState extends State<_QishuiModeOptions> {
  late Future<List<QishuiFeedMode>> _modes = widget.load();
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .52,
    ),
    child: FutureBuilder<List<QishuiFeedMode>>(
      future: _modes,
      builder: (context, snapshot) {
        if (snapshot.hasError || snapshot.data?.isEmpty == true) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(snapshot.hasError ? '听歌模式暂时无法读取' : '汽水暂未返回听歌模式'),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    final next = widget.load();
                    setState(() {
                      _modes = next;
                    });
                  },
                  child: const Text('重新读取'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(28),
            child: MusicActivityIndicator(label: '正在读取听歌模式'),
          );
        }
        return ListView(
          key: const ValueKey('qishui-feed-mode-options'),
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (final mode in snapshot.data!)
              ListTile(
                selected: mode.id == widget.selectedId,
                title: Text(mode.name),
                trailing: mode.id == widget.selectedId
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(context).pop(mode),
              ),
          ],
        );
      },
    ),
  );
}
