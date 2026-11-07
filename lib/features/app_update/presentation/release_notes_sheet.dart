import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/beta_glass_action.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../themes/music_typography.dart';

Future<void> showMusicReleaseNotes(
  BuildContext context, {
  required String version,
  required List<String> notes,
}) => showLiquidGlassBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  useSafeArea: true,
  sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : null,
  builder: (context) => Material(
    key: const ValueKey('release-notes-sheet'),
    type: MaterialType.transparency,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .8,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '此次更新',
                    style: TextStyle(
                      fontSize: MusicTypography.sectionTitleSize,
                      fontWeight: MusicTypography.titleWeight,
                    ),
                  ),
                ),
                BetaGlassAction(
                  label: '关闭更新说明',
                  icon: CupertinoIcons.xmark,
                  blue: false,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Mesting Music $version',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: MusicTypography.subheadlineSize,
              ),
            ),
            const SizedBox(height: 24),
            if (notes.isEmpty)
              const Text(
                '此版本暂未提供更新说明。',
                style: TextStyle(
                  fontSize: MusicTypography.calloutSize,
                  height: 1.6,
                ),
              ),
            MusicReleaseNotesList(notes: notes),
          ],
        ),
      ),
    ),
  ),
);

/// Both offline history and the installed-version sheet use the same real text.
class MusicReleaseNotesList extends StatelessWidget {
  const MusicReleaseNotesList({required this.notes, super.key});
  final List<String> notes;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final note in notes)
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Icon(CupertinoIcons.check_mark, size: 17),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  note,
                  style: const TextStyle(
                    fontSize: MusicTypography.calloutSize,
                    height: 1.55,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
