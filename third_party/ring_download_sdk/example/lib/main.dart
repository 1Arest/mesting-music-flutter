import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:ring_download_sdk/ring_download_sdk.dart';

// A headless integration probe. Production apps supply their own update UI.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sdk = RingDownloadSdk(
    const RingDownloadConfig(
      appId: String.fromEnvironment('RING_APP_ID', defaultValue: 'lifering'),
      allowSharing: bool.fromEnvironment('RING_ALLOW_SHARING'),
      onDiagnostic: reportDiagnostic,
    ),
  );
  try {
    final status = await sdk.inspect();
    debugPrint('RING_SDK_STATUS ${jsonEncode(status.toJson())}');
    const source = String.fromEnvironment('RING_DOWNLOAD_URL');
    const hostedLatest = bool.fromEnvironment('RING_DOWNLOAD_LATEST');
    if (source.isEmpty && !hostedLatest) {
      debugPrint(
        'RING_SDK_READY: use RING_DOWNLOAD_LATEST=true or immutable release metadata',
      );
      return;
    }
    final task = hostedLatest
        ? await sdk.downloadLatest()
        : sdk.download(
            RingDownloadRequest(
              releaseId: const String.fromEnvironment('RING_RELEASE_ID'),
              version: const String.fromEnvironment('RING_RELEASE_VERSION'),
              url: Uri.parse(source),
              fileSize: const int.fromEnvironment('RING_FILE_SIZE'),
              sha256: const String.fromEnvironment('RING_SHA256'),
            ),
          );
    debugPrint(
      'RING_SDK_RELEASE ${jsonEncode({'version': task.request.version, 'bytes': task.request.fileSize, 'sha256': task.request.sha256, 'discovery': hostedLatest ? 'hosted_latest' : 'business_selected'})}',
    );
    final subscription = task.progress.listen((p) {
      debugPrint(
        'RING_SDK_PROGRESS ${p.state.name} ${p.receivedBytes}/${p.totalBytes}',
      );
    });
    try {
      final receipt = await task.completed;
      debugPrint(
        'RING_SDK_COMPLETE ${receipt.fileSize} ${receipt.sha256} '
        '${receipt.verification.name}',
      );
      if (receipt.verification == RingDownloadVerification.sha256) {
        debugPrint('RING_SDK_VERIFIED ${receipt.fileSize} ${receipt.sha256}');
      }
      const hold = int.fromEnvironment('RING_HOLD_FOREGROUND_SECONDS');
      if (hold > 0) {
        debugPrint('RING_SDK_SHARING_PROBE_STARTED');
        await Future<void>.delayed(Duration(seconds: hold));
        debugPrint('RING_SDK_SHARING_PROBE_FINISHED');
      }
    } finally {
      await subscription.cancel();
    }
  } on RingDownloadException catch (e) {
    debugPrint('RING_SDK_FAILURE ${e.code.name}');
  } finally {
    await sdk.dispose();
  }
}

void reportDiagnostic(RingDownloadDiagnostic event) {
  debugPrint('RING_SDK_DIAGNOSTIC ${jsonEncode(event.toJson())}');
}
