import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/audio/audio_output_controller.dart';
import 'apple_audio_glyphs.dart';

/// This is content inside the existing glass output card, not a second dialog.
/// Active selection stays native-confirmed; paused preferences are labelled
/// separately, without opening a system picker or inventing a successful route.
class PlayerOutputRoutes extends ConsumerStatefulWidget {
  const PlayerOutputRoutes({super.key});
  @override
  ConsumerState<PlayerOutputRoutes> createState() => _PlayerOutputRoutesState();
}

class _PlayerOutputRoutesState extends ConsumerState<PlayerOutputRoutes> {
  bool _loading = true;
  String? _pending, _error;
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    try {
      await ref.read(audioOutputProvider.notifier).refreshRoutes();
    } catch (_) {
      if (mounted) _error = '设备列表暂不可用，请关闭后重试。';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _select(AudioOutputRoute route) async {
    if (_pending != null || !route.selectable) return;
    setState(() {
      _pending = route.id;
      _error = null;
    });
    try {
      final confirmed = await ref
          .read(audioOutputProvider.notifier)
          .transfer(route.id);
      if (mounted && !confirmed) _error = '系统尚未确认切换，请重试。';
    } catch (_) {
      if (mounted) _error = '切换未完成，请重试。';
    }
    if (mounted) setState(() => _pending = null);
  }

  @override
  Widget build(BuildContext context) {
    final output = ref.watch(audioOutputProvider);
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: CupertinoActivityIndicator(),
          )
        else ...[
          for (final route in output.routes)
            Semantics(
              selected: route.selected,
              child: CupertinoButton(
                key: ValueKey('output-route-${route.id}'),
                padding: const EdgeInsets.symmetric(vertical: 12),
                onPressed: route.selectable && _pending == null
                    ? () => _select(route)
                    : null,
                child: Row(
                  children: [
                    AppleAudioGlyph(
                      route.local
                          ? AppleAudioGlyphKind.phone
                          : route.headphones
                          ? AppleAudioGlyphKind.earphones
                          : AppleAudioGlyphKind.speakerLoud,
                      size: 29,
                      color: route.selected ? colors.primary : colors.onSurface,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            route.name,
                            style: TextStyle(
                              color: colors.onSurface,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _pending == route.id
                                ? '正在切换…'
                                : output.pendingId == route.id
                                ? '已选择，播放时生效'
                                : route.selected
                                ? '当前播放设备'
                                : '点按切换',
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_pending == route.id)
                      const CupertinoActivityIndicator()
                    else if (route.selected)
                      Icon(CupertinoIcons.check_mark, color: colors.primary),
                  ],
                ),
              ),
            ),
          if (output.routes.isEmpty)
            Text(
              '暂未读取到可用输出，请检查设备连接后重试。',
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 13,
                height: 1.5,
              ),
            ),
        ],
        if (_error != null)
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: TextStyle(color: colors.error, height: 1.5),
            ),
          ),
      ],
    );
  }
}
