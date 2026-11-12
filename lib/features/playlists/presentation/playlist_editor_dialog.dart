import '../../../shared/widgets/music_activity_indicator.dart';
import '../../../shared/widgets/beta_text_editing.dart';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../../shared/widgets/artwork_image.dart';
import '../../themes/music_theme_tokens.dart';
import '../../music_platform/presentation/platform_design.dart';
import '../../../core/platform/distribution_channel.dart';
import '../../../shared/widgets/beta_glass_action.dart';
import '../../themes/music_typography.dart';

class PlaylistDraft {
  const PlaylistDraft({
    required this.name,
    required this.description,
    required this.coverAsset,
  });
  final String name;
  final String description;
  final String? coverAsset;
}

/// Commit inside the sheet to retain the user's draft after a remote failure.
Future<PlaylistDraft?> showPlaylistEditorDialog(
  BuildContext context, {
  String? initialName,
  String initialDescription = '',
  String? initialCoverAsset,
  Future<void> Function(PlaylistDraft)? onSave,
}) => showModalBottomSheet<PlaylistDraft>(
  context: context,
  useRootNavigator: true,
  useSafeArea: true,
  isScrollControlled: true,
  isDismissible: false,
  enableDrag: false,
  backgroundColor: Colors.transparent,
  constraints: const BoxConstraints(maxWidth: 720),
  builder: (_) => _PlaylistEditor(
    initialName: initialName,
    initialDescription: initialDescription,
    initialCover: initialCoverAsset,
    onSave: onSave,
  ),
);

class _PlaylistEditor extends StatefulWidget {
  const _PlaylistEditor({
    this.initialName,
    required this.initialDescription,
    this.initialCover,
    this.onSave,
  });
  final String? initialName;
  final String initialDescription;
  final String? initialCover;
  final Future<void> Function(PlaylistDraft)? onSave;
  @override
  State<_PlaylistEditor> createState() => _PlaylistEditorState();
}

class _PlaylistEditorState extends State<_PlaylistEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.initialDescription,
  );
  int? _template;
  final _covers = PageController(viewportFraction: .72);
  int _coverPage = 0;
  String? _photo;
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _covers.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1800,
        maxHeight: 1800,
        imageQuality: 90,
        requestFullMetadata: false,
      );
      if (photo == null) return;
      if (await photo.length() > 10 * 1024 * 1024) {
        throw StateError('请选择小于 10 MB 的图片');
      }
      if (mounted) {
        setState(() {
          _photo = photo.path;
          _template = null;
          _error = null;
        });
        // Jump directly so intermediate template pages cannot clear the photo.
        _covers.jumpToPage(0);
      }
    } catch (_) {
      if (mounted) setState(() => _error = '图片读取失败，请换一张图片重试');
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = '请先填写歌单名称');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      var cover = widget.initialCover;
      if (_template != null || _photo != null) {
        cover = await persistPlaylistCover(template: _template, photo: _photo);
      }
      final draft = PlaylistDraft(
        name: _name.text.trim(),
        description: _description.text.trim(),
        coverAsset: cover,
      );
      await widget.onSave?.call(draft);
      if (mounted) Navigator.pop(context, draft);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is StateError
              ? error.message
              : '歌单未能保存，请检查网络后重试。输入与封面已保留。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final header = Row(
      children: [
        if (DistributionChannel.isBeta)
          BetaGlassAction(
            key: const ValueKey('playlist-editor-close'),
            label: '取消',
            icon: Icons.close_rounded,
            blue: false,
            onPressed: _saving ? null : () => Navigator.pop(context),
          )
        else
          IconButton(
            tooltip: '取消',
            onPressed: _saving ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, size: 29),
          ),
        Expanded(
          child: Text(
            widget.initialName == null ? '新建歌单' : '编辑歌单',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: MusicTypography.sectionTitleSize,
              fontWeight: MusicTypography.titleWeight,
              color: tokens.textPrimary,
            ),
          ),
        ),
        if (DistributionChannel.isBeta)
          BetaGlassAction(
            key: const ValueKey('playlist-editor-save'),
            label: '保存歌单',
            icon: Icons.check_rounded,
            loading: _saving,
            onPressed: _saving ? null : _save,
          )
        else
          IconButton.filled(
            key: const ValueKey('playlist-editor-save'),
            tooltip: '保存歌单',
            onPressed: _saving ? null : _save,
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              disabledBackgroundColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: .35),
              minimumSize: const Size.square(48),
            ),
            icon: _saving
                ? SizedBox.square(
                    dimension: 22,
                    child: MusicActivityIndicator(
                      independent: true,
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 28),
          ),
      ],
    );
    return PopScope(
      canPop: !_saving,
      child: PlatformStyle(
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .88,
                ),
                child: Column(
                  key: const ValueKey('playlist-editor-sheet'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Confirmation remains fixed while forms scroll above the keyboard.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                      child: header,
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 26),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 28),
                              SizedBox(
                                height: 226,
                                child: PageView.builder(
                                  controller: _covers,
                                  physics: _saving
                                      ? const NeverScrollableScrollPhysics()
                                      : null,
                                  onPageChanged: (index) => setState(() {
                                    _coverPage = index;
                                    _template = index == 0 ? null : index - 1;
                                    if (index != 0) _photo = null;
                                  }),
                                  itemCount: 7,
                                  itemBuilder: (context, index) {
                                    final selected = index == 0
                                        ? _template == null
                                        : _template == index - 1;
                                    return Center(
                                      child: Semantics(
                                        button: true,
                                        selected: selected,
                                        label: index == 0
                                            ? '当前封面或从相册选择'
                                            : '封面模板 $index',
                                        child: InkWell(
                                          onTap: _saving
                                              ? null
                                              : () {
                                                  if (index == 0) {
                                                    _pick();
                                                  } else {
                                                    setState(() {
                                                      _template = index - 1;
                                                      _photo = null;
                                                    });
                                                    _covers.animateToPage(
                                                      index,
                                                      duration: const Duration(
                                                        milliseconds: 240,
                                                      ),
                                                      curve:
                                                          Curves.easeOutCubic,
                                                    );
                                                  }
                                                },
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                          child: Container(
                                            width: 212,
                                            height: 212,
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              border: Border.all(
                                                width: selected ? 2 : 1,
                                                color: selected
                                                    ? Theme.of(
                                                        context,
                                                      ).colorScheme.primary
                                                    : Colors.transparent,
                                              ),
                                            ),
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(13),
                                              child: index == 0
                                                  ? (_photo ??
                                                                widget
                                                                    .initialCover) !=
                                                            null
                                                        ? ArtworkImage(
                                                            uri:
                                                                _photo ??
                                                                widget
                                                                    .initialCover!,
                                                            width: 204,
                                                            height: 204,
                                                          )
                                                        : ColoredBox(
                                                            color: Theme.of(context)
                                                                .colorScheme
                                                                .surfaceContainerHighest,
                                                            child: const Center(
                                                              child: Icon(
                                                                Icons
                                                                    .add_photo_alternate_outlined,
                                                                size: 40,
                                                              ),
                                                            ),
                                                          )
                                                  : CustomPaint(
                                                      painter:
                                                          PlaylistTemplatePainter(
                                                            index - 1,
                                                          ),
                                                      size: const Size.square(
                                                        204,
                                                      ),
                                                    ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              // Position cues reflect both swiping and gallery selection.
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  for (var index = 0; index < 7; index++)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 10,
                                      ),
                                      child: Icon(
                                        index == 0
                                            ? Icons.photo_camera_rounded
                                            : Icons.circle,
                                        size: index == 0 ? 16 : 8,
                                        color: index == _coverPage
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : tokens.textMuted.withValues(
                                                alpha: .4,
                                              ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              TextButton.icon(
                                onPressed: _saving ? null : _pick,
                                icon: const Icon(Icons.photo_library_outlined),
                                label: const Text('从相册选择封面'),
                              ),
                              const SizedBox(height: 20),
                              TextField(
                                contextMenuBuilder: buildBetaEditingMenu,
                                selectionControls: mestingTextSelectionControls,
                                cursorRadius: const Radius.circular(1),
                                key: const ValueKey(
                                  'playlist-editor-name-field',
                                ),
                                controller: _name,
                                enabled: !_saving,
                                maxLength: 30,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: MusicTypography.sectionTitleSize,
                                  fontWeight: MusicTypography.titleWeight,
                                  color: tokens.textPrimary,
                                ),
                                decoration: const InputDecoration(
                                  hintText: '歌单名称',
                                  counterText: '',
                                ),
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                contextMenuBuilder: buildBetaEditingMenu,
                                selectionControls: mestingTextSelectionControls,
                                cursorRadius: const Radius.circular(1),
                                key: const ValueKey(
                                  'playlist-editor-description-field',
                                ),
                                controller: _description,
                                enabled: !_saving,
                                maxLength: 100,
                                minLines: 2,
                                maxLines: 3,
                                decoration: const InputDecoration(
                                  hintText: '添加描述，留下一段心情',
                                ),
                              ),
                              if (_error != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    _error!,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                      height: 1.6,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Normalize to the upstream image contract: 640×640 opaque PNG, including
/// upscaling small photos. A source path alone is never treated as cloud saved.
Future<String> persistPlaylistCover({int? template, String? photo}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
  ui.Image? source;
  ui.Codec? codec;
  if (template != null) {
    PlaylistTemplatePainter(template).paint(canvas, const Size.square(640));
  } else {
    codec = await ui.instantiateImageCodec(
      await File(photo!).readAsBytes(),
      targetWidth: 1280,
    );
    source = (await codec.getNextFrame()).image;
    final edge = math.min(source.width, source.height).toDouble();
    canvas.drawImageRect(
      source,
      Rect.fromLTWH(
        (source.width - edge) / 2,
        (source.height - edge) / 2,
        edge,
        edge,
      ),
      const Rect.fromLTWH(0, 0, 640, 640),
      Paint()..filterQuality = FilterQuality.high,
    );
  }
  final picture = recorder.endRecording();
  final output = await picture.toImage(640, 640);
  final bytes = await output.toByteData(format: ui.ImageByteFormat.png);
  source?.dispose();
  codec?.dispose();
  picture.dispose();
  output.dispose();
  final documents = await getApplicationDocumentsDirectory();
  final directory = Directory('${documents.path}/playlist_covers');
  await directory.create(recursive: true);
  final file = File(
    '${directory.path}/cover_${DateTime.now().microsecondsSinceEpoch}.png',
  );
  final png = bytes!;
  await file.writeAsBytes(
    png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
    flush: true,
  );
  return file.path;
}

/// Native cover templates are reproducible and independent from network art.
class PlaylistTemplatePainter extends CustomPainter {
  const PlaylistTemplatePainter(this.index);
  final int index;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    const palettes = [
      [Color(0xFFF3D9B6), Color(0xFF272525), Color(0xFFEEEAE3)],
      [Color(0xFFD8E6F1), Color(0xFF263E5C), Color(0xFFA6BACD)],
      [Color(0xFFE8B8B2), Color(0xFF5E3528), Color(0xFFF2E9D9)],
      [Color(0xFFB4C9B5), Color(0xFF223C32), Color(0xFFE7E0C4)],
      [Color(0xFFD8CEFA), Color(0xFF302B53), Color(0xFFF8D8B3)],
      [Color(0xFFF4CF5C), Color(0xFF362D28), Color(0xFFFFEEE2)],
    ];
    final colors = palettes[index % palettes.length];
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
          stops: const [0, .53, 1],
        ).createShader(rect),
    );
    if (index.isEven) {
      for (var i = 0; i < 14; i++) {
        canvas.drawCircle(
          Offset(size.width * .74, size.height * .66),
          size.width * (.12 + i * .047),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = size.width * .025
            ..color = colors[1].withValues(alpha: .05 + i * .025),
        );
      }
    } else {
      final path = Path()
        ..moveTo(0, size.height)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            colors: [colors[1], colors[2]],
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
          ).createShader(rect),
      );
    }
    final label = TextPainter(
      text: const TextSpan(
        text: 'M',
        style: TextStyle(
          color: Color(0xCCFFFFFF),
          fontSize: 60,
          fontWeight: MusicTypography.titleWeight,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.scale(size.width / 640);
    label.paint(canvas, const Offset(38, 28));
    canvas.restore();
    label.dispose();
  }

  @override
  bool shouldRepaint(PlaylistTemplatePainter oldDelegate) =>
      oldDelegate.index != index;
}
