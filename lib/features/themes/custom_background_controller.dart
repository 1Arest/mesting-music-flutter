import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/persistence/app_preferences.dart';

enum CustomBackgroundKind { image, video }

class CustomBackgroundState {
  const CustomBackgroundState({this.path, this.kind});

  final String? path;
  final CustomBackgroundKind? kind;

  bool get active => path != null && kind != null;
  bool get isVideo => kind == CustomBackgroundKind.video;
}

class CustomBackgroundController extends Notifier<CustomBackgroundState> {
  static const _pathKey = 'custom_background_path';
  static const _kindKey = 'custom_background_kind';
  final ImagePicker _picker = ImagePicker();

  @override
  CustomBackgroundState build() {
    final preferences = ref.watch(sharedPreferencesProvider);
    final path = preferences.getString(_pathKey);
    final savedKind = preferences.getString(_kindKey);
    final kind = CustomBackgroundKind.values
        .cast<CustomBackgroundKind?>()
        .firstWhere((value) => value?.name == savedKind, orElse: () => null);
    if (path == null || kind == null || !File(path).existsSync()) {
      return const CustomBackgroundState();
    }
    return CustomBackgroundState(path: path, kind: kind);
  }

  Future<bool> pickImage() => _pick(CustomBackgroundKind.image);

  Future<bool> pickVideo() => _pick(CustomBackgroundKind.video);

  Future<bool> _pick(CustomBackgroundKind kind) async {
    final picked = kind == CustomBackgroundKind.video
        ? await _picker.pickVideo(source: ImageSource.gallery)
        : await _picker.pickImage(
            source: ImageSource.gallery,
            imageQuality: 92,
            maxWidth: 2560,
          );
    if (picked == null) return false;

    final source = File(picked.path);
    final directory = await getApplicationDocumentsDirectory();
    final extension = _safeExtension(picked.path, kind);
    final target = File(
      '${directory.path}${Platform.pathSeparator}'
      'music_background_${DateTime.now().millisecondsSinceEpoch}$extension',
    );
    await source.copy(target.path);
    state = CustomBackgroundState(path: target.path, kind: kind);
    final preferences = ref.read(sharedPreferencesProvider);
    await preferences.setString(_pathKey, target.path);
    await preferences.setString(_kindKey, kind.name);
    return true;
  }

  Future<void> clear() async {
    state = const CustomBackgroundState();
    final preferences = ref.read(sharedPreferencesProvider);
    await preferences.remove(_pathKey);
    await preferences.remove(_kindKey);
  }

  String _safeExtension(String path, CustomBackgroundKind kind) {
    final name = path.replaceAll('\\', '/').split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot > 0 && name.length - dot <= 6) {
      return name.substring(dot).toLowerCase();
    }
    return kind == CustomBackgroundKind.video ? '.mp4' : '.jpg';
  }
}

final customBackgroundProvider =
    NotifierProvider<CustomBackgroundController, CustomBackgroundState>(
      CustomBackgroundController.new,
    );
