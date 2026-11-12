import '../../../../shared/widgets/beta_selection_controls.dart';
import '../../../../shared/widgets/beta_page_motion.dart';
import '../../../../shared/widgets/beta_content_insets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/widgets/beta_glass_controls.dart';
import '../../data/platform_comments_repository.dart';
import '../../music_platform_providers.dart';
import '../../platform_backend_providers.dart';
import '../../presentation/platform_comments_page.dart';
import '../../presentation/platform_design.dart';
import '../netease_comments_repository.dart';
import 'netease_entity_picker.dart';

/// Resource selection belongs before a comment thread, rather than asking for
/// resource type codes, thread IDs and comment IDs in an API-shaped form.
class NeteaseCommentEntryPage extends ConsumerStatefulWidget {
  const NeteaseCommentEntryPage({
    required this.route,
    this.seed = const {},
    super.key,
  });
  final String route;
  final Map<String, Object?> seed;
  @override
  ConsumerState<NeteaseCommentEntryPage> createState() =>
      _NeteaseCommentEntryPageState();
}

class _NeteaseCommentEntryPageState
    extends ConsumerState<NeteaseCommentEntryPage> {
  late PlatformCommentKind _kind = switch (widget.route) {
    '/comment/album' => PlatformCommentKind.album,
    '/comment/playlist' => PlatformCommentKind.playlist,
    '/comment/mv' => PlatformCommentKind.mv,
    '/comment/dj' => PlatformCommentKind.podcast,
    '/comment/video' => PlatformCommentKind.video,
    '/comment/event' => PlatformCommentKind.event,
    _ => PlatformCommentKind.song,
  };
  NeteasePickedEntity? _picked;
  String? _credential;
  @override
  void initState() {
    super.initState();
    final kind = '${widget.seed['_entityKind'] ?? ''}';
    if (kind.isNotEmpty) {
      _kind = PlatformCommentKind.values.firstWhere(
        (k) => k.name == kind,
        orElse: () => kind == 'program' ? PlatformCommentKind.podcast : _kind,
      );
    }
    _credential = ref.read(platformAccountProvider).value?.token;
    final id = widget.seed['id'];
    if (id != null) {
      _picked = NeteasePickedEntity('$id', '${widget.seed['name'] ?? '查看评论'}');
    }
  }

  Future<void> _choose() async {
    final picked = await Navigator.of(context).push<NeteasePickedEntity>(
      MestingPageRoute(
        builder: (_) => NeteaseEntityPicker(
          kind: _kind == PlatformCommentKind.podcast ? 'program' : _kind.name,
          includeDetails: true,
        ),
      ),
    );
    if (!mounted || picked == null) return;
    setState(() => _picked = picked);
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(platformAccountProvider).value;
    if (account?.token != _credential) {
      return const PlatformPageFrame(
        title: '评论与互动',
        child: Center(child: Text('账号已变化，请返回后重新打开')),
      );
    }
    if (_picked != null && account != null && ref.watch(usesNeteaseProvider)) {
      return PlatformCommentsPage(
        repository: NeteaseCommentsRepository(
          ref.read(musicPlatformApiProvider),
          account,
          ref.read(neteaseMusicRepositoryProvider),
        ),
        resource: PlatformCommentResource(
          kind: _kind,
          id: _picked!.id,
          name: _picked!.name,
        ),
      );
    }
    return PlatformPageFrame(
      title: '评论与互动',
      child: ListView(
        padding: BetaContentInsets.musicPaddingOf(
          context,
          const EdgeInsets.all(24),
        ),
        children: [
          const Text('选择想查看的内容，即可阅读、点赞、回复和发布评论。'),
          const SizedBox(height: 22),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final kind in PlatformCommentKind.values)
                BetaSelectionChip(
                  label: Text(
                    neteaseEntityLabel(
                      kind == PlatformCommentKind.podcast
                          ? 'program'
                          : kind.name,
                    ),
                  ),
                  selected: _kind == kind,
                  onSelected: (_) => setState(() => _kind = kind),
                ),
            ],
          ),
          const SizedBox(height: 18),
          BetaGlassButton(
            blue: true,
            onPressed: _choose,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(CupertinoIcons.music_note_list),
                const SizedBox(width: 8),
                Text(
                  '选择${neteaseEntityLabel(_kind == PlatformCommentKind.podcast ? 'program' : _kind.name)}',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
