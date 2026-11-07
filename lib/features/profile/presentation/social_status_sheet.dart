import '../../../shared/widgets/artwork_scroll_frontier.dart';
import '../../../shared/widgets/beta_text_editing.dart';
import 'package:flutter/material.dart';

import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../social/domain/social_models.dart';
import '../../social/presentation/social_widgets.dart';
import '../../themes/music_typography.dart';

const socialStatusPresets = <SocialStatus>[
  SocialStatus(emoji: '🎧', text: '找人一起听'),
  SocialStatus(emoji: '💪', text: '加油'),
  SocialStatus(emoji: '🫠', text: 'emo'),
  SocialStatus(emoji: '🌷', text: '等春天'),
  SocialStatus(emoji: '😆', text: '超开心'),
  SocialStatus(emoji: '🥰', text: '恋爱中'),
  SocialStatus(emoji: '❤️‍🔥', text: '想恋爱'),
  SocialStatus(emoji: '🎵', text: '求推歌'),
  SocialStatus(emoji: '🙏', text: '许个愿'),
  SocialStatus(emoji: '💯', text: '准备考试'),
  SocialStatus(emoji: '🕒', text: '等待中'),
  SocialStatus(emoji: '🧑‍💻', text: '忙碌中'),
  SocialStatus(emoji: '😵‍💫', text: '失眠'),
  SocialStatus(emoji: '📚', text: '爱学习'),
];

const _statusSheetBorderRadius = BorderRadius.only(
  topLeft: Radius.circular(30),
  topRight: Radius.circular(30),
);

Future<SocialStatus?> showSocialStatusPicker(
  BuildContext context, {
  required SocialStatus initialStatus,
}) {
  return showLiquidGlassBottomSheet<SocialStatus>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    barrierColor: Colors.black.withValues(alpha: .58),
    builder: (context) => FractionallySizedBox(
      heightFactor: .78,
      child: _SocialStatusPicker(initialStatus: initialStatus),
    ),
  );
}

class _SocialStatusPicker extends StatefulWidget {
  const _SocialStatusPicker({required this.initialStatus});

  final SocialStatus initialStatus;

  @override
  State<_SocialStatusPicker> createState() => _SocialStatusPickerState();
}

class _SocialStatusPickerState extends State<_SocialStatusPicker> {
  late SocialStatus _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialStatus;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SocialGlass(
      key: const ValueKey('social-status-picker-surface'),
      radius: 30,
      borderRadius: _statusSheetBorderRadius,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withValues(alpha: .20),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '选择状态',
                        style: TextStyle(
                          fontSize: MusicTypography.sectionTitleSize,
                          fontWeight: MusicTypography.titleWeight,
                        ),
                      ),
                    ),
                    if (widget.initialStatus.isNotEmpty)
                      TextButton(
                        onPressed: () =>
                            Navigator.pop(context, const SocialStatus.empty()),
                        child: const Text('清除'),
                      ),
                    TextButton(
                      key: const ValueKey('social-status-done'),
                      onPressed: _selected.isEmpty
                          ? null
                          : () => Navigator.pop(context, _selected),
                      child: const Text(
                        '完成',
                        style: TextStyle(
                          fontWeight: MusicTypography.titleWeight,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          Expanded(
            child: ListView(
              physics: const ArtworkFrontierPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(
                18,
                16,
                18,
                MediaQuery.viewPaddingOf(context).bottom + 28,
              ),
              children: [
                _CustomStatusTile(
                  selected: !_isPreset(_selected) && _selected.isNotEmpty,
                  status: _selected,
                  onTap: _editCustomStatus,
                ),
                const SizedBox(height: 18),
                Text(
                  '推荐状态',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: MusicTypography.captionSize,
                    fontWeight: MusicTypography.bodyWeight,
                  ),
                ),
                const SizedBox(height: 10),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: socialStatusPresets.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisExtent: 58,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemBuilder: (context, index) {
                    final status = socialStatusPresets[index];
                    final selected = status == _selected;
                    return _PresetStatusTile(
                      status: status,
                      selected: selected,
                      onTap: () => setState(() => _selected = status),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isPreset(SocialStatus status) => socialStatusPresets.contains(status);

  Future<void> _editCustomStatus() async {
    final status = await showLiquidGlassBottomSheet<SocialStatus>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: .58),
      builder: (context) => _CustomStatusEditor(
        initialStatus: _isPreset(_selected)
            ? const SocialStatus(emoji: '✨', text: '')
            : _selected,
      ),
    );
    if (status != null && mounted) Navigator.pop(context, status);
  }
}

class _CustomStatusTile extends StatelessWidget {
  const _CustomStatusTile({
    required this.selected,
    required this.status,
    required this.onTap,
  });

  final bool selected;
  final SocialStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: accent.withValues(alpha: selected ? .16 : .07),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: accent.withValues(alpha: selected ? .52 : .16),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .12),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  selected ? status.emoji : '✨',
                  style: const TextStyle(fontSize: MusicTypography.headingSize),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected ? status.text : '自定义状态',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: MusicTypography.subheadlineSize,
                        fontWeight: MusicTypography.bodyWeight,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      '写下此刻的心情或正在做的事',
                      style: TextStyle(
                        fontSize: MusicTypography.smallCaptionSize,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetStatusTile extends StatelessWidget {
  const _PresetStatusTile({
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final SocialStatus status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: selected
          ? accent.withValues(alpha: .18)
          : Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: .62),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: .60)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Text(
                status.emoji,
                style: const TextStyle(fontSize: MusicTypography.headingSize),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  status.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: MusicTypography.footnoteSize,
                    fontWeight: MusicTypography.bodyWeight,
                  ),
                ),
              ),
              if (selected) Icon(Icons.check_rounded, size: 17, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomStatusEditor extends StatefulWidget {
  const _CustomStatusEditor({required this.initialStatus});

  final SocialStatus initialStatus;

  @override
  State<_CustomStatusEditor> createState() => _CustomStatusEditorState();
}

class _CustomStatusEditorState extends State<_CustomStatusEditor> {
  static const _emojis = ['✨', '🎧', '🌷', '🌙', '🔥', '💿', '🐱', '🍑'];
  late final TextEditingController _controller;
  late String _emoji;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialStatus.text);
    _emoji = widget.initialStatus.emoji.trim().isEmpty
        ? _emojis.first
        : widget.initialStatus.emoji;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SocialGlass(
          key: const ValueKey('custom-social-status-surface'),
          radius: 30,
          borderRadius: _statusSheetBorderRadius,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '自定义状态',
                  style: TextStyle(
                    fontSize: MusicTypography.sectionTitleSize,
                    fontWeight: MusicTypography.titleWeight,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '好友会在你的主页看到这条状态。',
                  style: TextStyle(
                    fontSize: MusicTypography.smallCaptionSize,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final emoji in _emojis)
                      _EmojiChoice(
                        emoji: emoji,
                        selected: _emoji == emoji,
                        onTap: () => setState(() => _emoji = emoji),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  contextMenuBuilder: buildBetaEditingMenu,
                  selectionControls: mestingTextSelectionControls,
                  cursorRadius: const Radius.circular(1),
                  key: const ValueKey('custom-social-status-field'),
                  controller: _controller,
                  autofocus: true,
                  maxLength: 12,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    hintText: '例如：今天只想听慢歌',
                    prefixIcon: Icon(Icons.edit_rounded),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    key: const ValueKey('custom-social-status-save'),
                    onPressed: _controller.text.trim().isEmpty ? null : _submit,
                    child: const Text('使用这个状态'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.pop(context, SocialStatus(emoji: _emoji, text: text));
  }
}

class _EmojiChoice extends StatelessWidget {
  const _EmojiChoice({
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: selected
          ? accent.withValues(alpha: .18)
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: .60)
                  : Colors.transparent,
            ),
          ),
          child: Text(
            emoji,
            style: const TextStyle(fontSize: MusicTypography.headingSize),
          ),
        ),
      ),
    );
  }
}
