import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/music_feature_page.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import '../app_update_providers.dart';
import '../domain/release_history.dart';
import 'release_notes_sheet.dart';
import '../../themes/music_typography.dart';

/// Opening history never checks the update service. Package metadata only
/// labels the installed version; history remains usable if that read fails.
class MusicReleaseHistoryPage extends ConsumerWidget {
  const MusicReleaseHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installed = ref.watch(appVersionProvider).value;
    final versions = musicReleaseNotes.entries.toList();
    return MusicFeaturePage(
      title: '更新说明',
      child: Builder(
        builder: (contentContext) => ListView.separated(
          key: const PageStorageKey('music-release-history'),
          // Read from inside the secondary glass layout so the final historical
          // note can scroll above its player/navigation accessories as well.
          padding: EdgeInsets.fromLTRB(
            22,
            16,
            22,
            BetaContentInsets.bottomOf(contentContext, 28),
          ),
          itemCount: versions.length,
          separatorBuilder: (_, _) => const Divider(height: 25),
          itemBuilder: (context, index) {
            final entry = versions[index];
            final current = installed?.versionName == entry.key;
            return ExpansionTile(
              key: PageStorageKey('release-history-${entry.key}'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 16),
              initiallyExpanded: current || index == 0,
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text(
                'v${entry.key}',
                style: const TextStyle(
                  fontSize: MusicTypography.headingSize,
                  fontWeight: MusicTypography.titleWeight,
                ),
              ),
              subtitle: current ? const Text('当前安装版本') : null,
              children: [MusicReleaseNotesList(notes: entry.value)],
            );
          },
        ),
      ),
    );
  }
}
