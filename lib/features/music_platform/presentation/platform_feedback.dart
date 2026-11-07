import '../../../core/errors/user_facing_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../downloads/audio_download_storage.dart';

import '../../../shared/widgets/music_notice.dart';
import '../../../core/audio/mesting_audio_handler.dart';
import '../data/music_platform_api.dart';
import '../qishui/qishui_api.dart';

void showPlatformFailure(BuildContext context, Object error) {
  showMusicNotice(
    context,
    icon: Icons.error_outline_rounded,
    title: error is QishuiException ? error.title : '操作未完成',
    message: error is QishuiException
        ? error.message
        : error is MusicPlatformException
        ? error.message
        : error is PlaybackContinuationException
        ? error.message
        : error is DownloadStorageException
        ? error.message
        : error is PlatformException
        ? error.message ?? '设备操作未完成，请检查系统授权后重试'
        : userFacingErrorMessage(error, fallback: '音频加载未完成，请重试或查看连接诊断'),
  );
}
