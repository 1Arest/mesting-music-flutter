import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/music_feature_page.dart';
import 'qishui_api.dart';
import 'qishui_image_upload.dart';
import 'qishui_models.dart';
import 'qishui_page_scope.dart';
import 'qishui_providers.dart';

/// Photos remain in memory during preview. The square PNG strips metadata and
/// matches the preview crop; choosing/cancelling never changes a cloud cover.
final qishuiCoverPhotoPickerProvider = Provider<Future<Uint8List?> Function()>(
  (ref) => () async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1800,
      maxHeight: 1800,
      imageQuality: 90,
      requestFullMetadata: false,
    );
    if (photo == null) return null;
    if (await photo.length() > QishuiImageUploader.maximumBytes) {
      throw const QishuiException('请选择10 MB以内的图片');
    }
    return photo.readAsBytes();
  },
);

Future<Uint8List> renderQishuiCover(ui.Image image, Alignment alignment) async {
  final edge = math.min(image.width, image.height).toDouble();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(
      (image.width - edge) * (alignment.x + 1) / 2,
      (image.height - edge) * (alignment.y + 1) / 2,
      edge,
      edge,
    ),
    const Rect.fromLTWH(0, 0, 640, 640),
    Paint()..filterQuality = FilterQuality.high,
  );
  final picture = recorder.endRecording();
  final result = await picture.toImage(640, 640);
  try {
    final bytes = (await result.toByteData(format: ui.ImageByteFormat.png))!;
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    picture.dispose();
    result.dispose();
  }
}

class QishuiPlaylistCoverPage extends ConsumerStatefulWidget {
  const QishuiPlaylistCoverPage({required this.playlist, super.key});
  final QishuiPlaylist playlist;
  @override
  ConsumerState<QishuiPlaylistCoverPage> createState() =>
      _QishuiPlaylistCoverPageState();
}

class _QishuiPlaylistCoverPageState
    extends ConsumerState<QishuiPlaylistCoverPage>
    with QishuiOwnedPage<QishuiPlaylistCoverPage> {
  ui.Image? _image;
  Alignment _alignment = Alignment.center;
  bool _picking = false, _saving = false;
  String? _error;
  int _generation = 0;
  Future<void> _pick() async {
    if (_saving || _picking || !ownerCurrent) return;
    final generation = ++_generation;
    setState(() {
      _picking = true;
      _error = null;
    });
    ui.Codec? codec;
    ui.Image? next;
    try {
      final bytes = await ref.read(qishuiCoverPhotoPickerProvider)();
      if (bytes == null || !ownerCurrent) return;
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 1600,
        allowUpscaling: false,
      );
      next = (await codec.getNextFrame()).image;
      if (!ownerCurrent || generation != _generation) return;
      final previous = _image;
      setState(() {
        _image = next;
        _alignment = Alignment.center;
      });
      next = null;
      if (previous != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
      }
    } on Object catch (error) {
      if (ownerCurrent) {
        setState(
          () => _error = error is QishuiException
              ? error.message
              : '图片读取未完成，请换一张图片重试',
        );
      }
    } finally {
      codec?.dispose();
      next?.dispose();
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    final image = _image;
    if (_saving || image == null || !ownerCurrent) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final bytes = await renderQishuiCover(image, _alignment);
      if (!ownerCurrent) return;
      final changed = await ref
          .read(qishuiRepositoryProvider)
          .changePlaylistCover(
            widget.playlist.id,
            bytes,
            abortTrigger: pageAbort,
          );
      if (mounted && ownerCurrent) Navigator.pop(context, changed);
    } on Object catch (error) {
      if (ownerCurrent) {
        setState(
          () => _error = error is QishuiException
              ? error.message
              : '封面尚未保存，请重试；所选图片已保留',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!watchOwner()) return changedAccount();
    return MusicFeaturePage(
      title: '更换歌单封面',
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.playlist.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: _image == null
                        ? ColoredBox(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            child: const Center(
                              child: Icon(
                                Icons.add_photo_alternate_outlined,
                                size: 56,
                              ),
                            ),
                          )
                        : RawImage(
                            image: _image,
                            fit: BoxFit.cover,
                            alignment: _alignment,
                          ),
                  ),
                ),
              ),
            ),
            if (_image != null) ...[
              const SizedBox(height: 12),
              const Text('调整裁剪位置'),
              Slider(
                key: const ValueKey('qishui-cover-crop'),
                min: -1,
                max: 1,
                value: _image!.width >= _image!.height
                    ? _alignment.x
                    : _alignment.y,
                onChanged: _saving
                    ? null
                    : (value) => setState(
                        () => _alignment = _image!.width >= _image!.height
                            ? Alignment(value, 0)
                            : Alignment(0, value),
                      ),
              ),
            ],
            const SizedBox(height: 16),
            BetaGlassButton(
              onPressed: _saving || _picking ? null : _pick,
              child: Text(_picking ? '正在读取图片' : '从相册选择图片'),
            ),
            const SizedBox(height: 12),
            BetaGlassButton(
              key: const ValueKey('qishui-cover-save'),
              onPressed: _image == null || _saving || _picking ? null : _save,
              accent: true,
              child: Text(_saving ? '正在保存并核对' : '保存封面'),
            ),
            const SizedBox(height: 12),
            const Text('保存后更新同一汽水账号的歌单封面。只有云端读回一致，才显示保存成功。'),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Semantics(liveRegion: true, child: Text(_error!)),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    ++_generation;
    _image?.dispose();
    super.dispose();
  }
}
