import '../../../shared/widgets/beta_text_editing.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../../experience/presentation/beta_bottom_bar.dart';
import '../../../shared/widgets/beta_glass_action.dart';
import '../../../shared/widgets/beta_activity_indicator.dart';
import '../../themes/music_typography.dart';

/// Input and send are sibling glass surfaces. Nesting a glass button inside a
/// glass container disables its refraction in the renderer. Keep both bounded
/// and independent, matching the persistent music bar's actual material.
class PlatformCommentComposer extends StatelessWidget {
  const PlatformCommentComposer({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.keyboardVisible,
    this.reply,
    this.onCancelReply,
    this.hintText,
    this.sendLabel = '发送评论',
    this.actionIcon = CupertinoIcons.arrow_up,
    this.expandOnPress = true,
    this.onChanged,
    this.onSubmitted,
    this.singleLine = false,
    this.autofocus = false,
    super.key,
  });
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  // Scaffold consumes the body's insets when resizing. The owning page reads
  // keyboard visibility above Scaffold and passes that platform detail here.
  final bool keyboardVisible;
  final String? reply;
  final VoidCallback? onCancelReply;

  /// Chat uses exactly the same optical surfaces as comments; only the copy
  /// changes. Keep the renderer and keyboard behaviour in this one component.
  final String? hintText;
  final String sendLabel;
  final IconData actionIcon;
  final bool expandOnPress, singleLine, autofocus;
  final ValueChanged<String>? onChanged, onSubmitted;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (reply != null)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '回复 $reply',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: '取消回复',
                  onPressed: onCancelReply,
                  icon: const Icon(CupertinoIcons.xmark, size: 16),
                ),
              ],
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: RepaintBoundary(
                child: GlassContainer(
                  key: const ValueKey('comment-liquid-glass-input'),
                  useOwnLayer: true,
                  quality: GlassQuality.premium,
                  settings: betaMusicPillGlass(context),
                  shape: const LiquidRoundedRectangle(borderRadius: 24),
                  child: TextField(
                    contextMenuBuilder: buildBetaEditingMenu,
                    selectionControls: mestingTextSelectionControls,
                    cursorRadius: const Radius.circular(1),
                    controller: controller,
                    autofocus: autofocus,
                    onChanged: onChanged,
                    onSubmitted: onSubmitted,
                    enabled: !sending,
                    maxLength: 1000,
                    minLines: 1,
                    maxLines: singleLine
                        ? 1
                        : keyboardVisible
                        ? 2
                        : 4,
                    textInputAction: singleLine
                        ? TextInputAction.search
                        : TextInputAction.newline,
                    style: const TextStyle(
                      fontSize: MusicTypography.calloutSize,
                      height: 1.4,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          hintText ?? (reply == null ? '写下你的评论…' : '回复评论…'),
                      counterText: '',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 13,
                      ),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              enabled: !sending,
              liveRegion: sending,
              excludeSemantics: true,
              label: sending ? '正在发送' : sendLabel,
              child: Tooltip(
                message: '发送',
                child: ExcludeFocus(
                  excluding: sending,
                  child: IgnorePointer(
                    ignoring: sending,
                    child: RepaintBoundary(
                      child: GlassButton.custom(
                        key: const ValueKey('comment-blue-glass-send'),
                        // Busy is not a faded disabled material. Block interaction
                        // above while keeping blue glass and white spinner opaque.
                        onTap: () {
                          if (!sending) onSend();
                        },
                        width: 48,
                        height: 48,
                        useOwnLayer: true,
                        quality: GlassQuality.premium,
                        stretch: expandOnPress ? .15 : 0,
                        interactionScale: expandOnPress ? null : 1,
                        shape: const LiquidRoundedRectangle(borderRadius: 24),
                        settings: betaBlueActionGlass,
                        child: sending
                            ? const BetaActivityIndicator(
                                color: Colors.white,
                                radius: 12,
                              )
                            : Icon(actionIcon, color: Colors.white, size: 23),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
