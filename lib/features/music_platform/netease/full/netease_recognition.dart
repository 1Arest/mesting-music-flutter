import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../../core/audio/playback_providers.dart';
import '../../../../shared/widgets/beta_glass_controls.dart';

/// Decode only the mono 8 kHz PCM16 format requested from the recorder. RIFF
/// chunks are walked instead of assuming every WAV has a 44-byte header.
Float32List neteaseFingerprintPcm(Uint8List wav) {
  final data = ByteData.sublistView(wav);
  if (wav.length < 12 ||
      ascii.decode(wav.sublist(0, 4), allowInvalid: true) != 'RIFF') {
    throw const FormatException('录音格式不正确');
  }
  int? offset, length;
  bool format = false;
  for (var at = 12; at + 8 <= wav.length;) {
    final kind = ascii.decode(wav.sublist(at, at + 4), allowInvalid: true);
    final size = data.getUint32(at + 4, Endian.little);
    if (at + 8 + size > wav.length) throw const FormatException('录音数据不完整');
    if (kind == 'fmt ' && size >= 16) {
      format =
          data.getUint16(at + 8, Endian.little) == 1 &&
          data.getUint16(at + 10, Endian.little) == 1 &&
          data.getUint32(at + 12, Endian.little) == 8000 &&
          data.getUint16(at + 22, Endian.little) == 16;
    }
    if (kind == 'data') {
      offset = at + 8;
      length = size;
      break;
    }
    at += 8 + size + (size % 2);
  }
  if (!format || offset == null || length == null || length < 16000) {
    throw const FormatException('请至少录制一秒声音');
  }
  final count = (length ~/ 2).clamp(0, 8000 * 8);
  return Float32List.fromList([
    for (var i = 0; i < count; i++)
      data.getInt16(offset + i * 2, Endian.little) / 32768,
  ]);
}

/// The pinned upstream AFP computes locally inside an isolated WebView. This
/// view has no music cookies and performs no API requests. Only its fingerprint
/// returns to Dart, which calls the existing direct HTTPS transport.
class NeteaseRecognitionCapture extends ConsumerStatefulWidget {
  const NeteaseRecognitionCapture({
    required this.isCurrent,
    required this.onFingerprint,
    super.key,
  });
  final bool Function() isCurrent;
  final void Function(String, int) onFingerprint;
  @override
  ConsumerState<NeteaseRecognitionCapture> createState() =>
      _NeteaseRecognitionCaptureState();
}

class _NeteaseRecognitionCaptureState
    extends ConsumerState<NeteaseRecognitionCapture>
    with WidgetsBindingObserver {
  final _recorder = AudioRecorder();
  WebViewController? _controller;
  Completer<void>? _cancel;
  Completer<String>? _result;
  bool _busy = false;
  String? _error;
  int _epoch = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _stop();
  }

  void _stop() {
    _epoch++;
    if (_cancel?.isCompleted == false) _cancel!.complete();
  }

  @override
  void dispose() {
    _stop();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy || !widget.isCurrent()) return;
    final epoch = ++_epoch;
    _cancel = Completer<void>();
    setState(() {
      _busy = true;
      _error = null;
    });
    File? temporary;
    try {
      if (!await _recorder.hasPermission()) {
        throw const FormatException('请允许麦克风权限后重试');
      }
      if (!mounted || epoch != _epoch || !widget.isCurrent()) return;
      await ref.read(audioHandlerProvider).pause();
      final folder = await getTemporaryDirectory();
      temporary = File(
        '${folder.path}/mesting-netease-recognition-${DateTime.now().microsecondsSinceEpoch}.wav',
      );
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 8000,
          numChannels: 1,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
        ),
        path: temporary.path,
      );
      await Future.any([
        Future<void>.delayed(const Duration(seconds: 5)),
        _cancel!.future,
      ]);
      await _recorder.stop();
      if (!mounted || epoch != _epoch || !widget.isCurrent()) return;
      final pcm = neteaseFingerprintPcm(await temporary.readAsBytes());
      final ready = Completer<void>();
      _result = Completer<String>();
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          'FingerprintResult',
          onMessageReceived: (message) {
            if (_result?.isCompleted == false) {
              if (message.message.startsWith('error:')) {
                _result!.completeError(const FormatException('声音指纹处理失败，请重试'));
              } else {
                _result!.complete(message.message);
              }
            }
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) =>
                request.url.startsWith('about:') ||
                    request.url.startsWith('data:')
                ? NavigationDecision.navigate
                : NavigationDecision.prevent,
            onPageFinished: (_) {
              if (!ready.isCompleted) ready.complete();
            },
          ),
        );
      final wasm = await rootBundle.loadString(
        'third_party/netease_protocol/afp/afp.wasm.js',
      );
      final runtime = await rootBundle.loadString(
        'third_party/netease_protocol/afp/afp.js',
      );
      if (!mounted || epoch != _epoch) return;
      setState(() => _controller = controller);
      await controller.loadHtmlString(
        '<!doctype html><html><head><meta name="viewport" content="width=device-width"><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; script-src \'unsafe-inline\' \'unsafe-eval\' \'wasm-unsafe-eval\'; connect-src \'none\'"></head><body><script>$wasm</script><script>$runtime</script></body></html>',
      );
      await ready.future.timeout(const Duration(seconds: 20));
      if (!mounted || epoch != _epoch || !widget.isCurrent()) return;
      final bytes = Uint8List(pcm.length * 4);
      final view = ByteData.sublistView(bytes);
      for (var i = 0; i < pcm.length; i++) {
        view.setFloat32(i * 4, pcm[i], Endian.little);
      }
      await controller.runJavaScript(
        '(() => {const s=atob("${base64Encode(bytes)}");const b=Uint8Array.from(s,c=>c.charCodeAt(0));GenerateFP(new Float32Array(b.buffer)).then(fp=>FingerprintResult.postMessage(fp)).catch(()=>FingerprintResult.postMessage("error:fp"));})();',
      );
      final fingerprint = await _result!.future.timeout(
        const Duration(seconds: 30),
      );
      if (mounted && epoch == _epoch && widget.isCurrent()) {
        widget.onFingerprint(fingerprint, pcm.length ~/ 8000);
      }
    } catch (error) {
      if (mounted && epoch == _epoch) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : '录音或声音分析未能完成，请重试',
        );
      }
    } finally {
      try {
        if (await _recorder.isRecording()) await _recorder.stop();
      } catch (_) {
        /* Recorder may already be disposed. */
      }
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _controller = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('靠近音源录制5秒声音。声音指纹在设备本地生成，再交给网易云匹配。'),
      const SizedBox(height: 18),
      BetaGlassButton(
        onPressed: _busy ? null : _start,
        loading: _busy,
        child: Text(_busy ? '正在听取和识别…' : '开始识曲'),
      ),
      if (_busy) BetaGlassButton(onPressed: _stop, child: const Text('取消')),
      if (_error != null)
        Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
      if (_controller != null)
        ExcludeSemantics(
          child: IgnorePointer(
            child: SizedBox(
              width: 1,
              height: 1,
              child: WebViewWidget(controller: _controller!),
            ),
          ),
        ),
      const SizedBox(height: 22),
    ],
  );
}
