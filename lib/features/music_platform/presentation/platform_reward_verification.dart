import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../shared/widgets/beta_glass_popover.dart';
import '../domain/platform_rewards.dart';
import '../retained_kugou_scope.dart';
import '../../../core/diagnostics/diagnostic_activity.dart';

/// Adapted from md3Music's verify_captcha_dialog.dart (a69503b, AGPL-3.0).
/// The Tencent SDK supplies the proof. Cancellation, account changes and page
/// load failures return null; none can be converted into verification success.
Future<String?> showPlatformRewardVerification(
  BuildContext context,
  WidgetRef ref,
  RewardVerification challenge,
) async {
  final owner = ref.read(retainedKugouSessionProvider);
  if (owner == null) return null;
  BuildContext? dialog;
  Timer? timeout;
  var finished = false, initialized = false;
  var terminalPending = false;
  String? pendingProof;
  void finish(String? proof) {
    if (finished) return;
    final current = dialog;
    // A fast SDK error may arrive before the route's first frame.
    if (current == null) {
      terminalPending = true;
      pendingProof = proof;
      return;
    }
    if (!current.mounted || ModalRoute.of(current)?.isCurrent != true) {
      return;
    }
    finished = true;
    Navigator.of(current).pop(proof);
  }

  final controller = WebViewController();
  void initialize() {
    if (initialized || finished) return;
    initialized = true;
    unawaited(
      controller
          .runJavaScript(
            'window.initCaptcha && initCaptcha(${jsonEncode(challenge.appId)})',
          )
          .catchError((Object _) {
            finish(null);
          }),
    );
  }

  controller
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..addJavaScriptChannel(
      'CaptchaChannel',
      onMessageReceived: (message) {
        final value = message.message;
        if (value == '__READY__') {
          initialize();
        } else if (value == '__CANCEL__' || value == '__ERROR__') {
          finish(null);
        } else if (value.startsWith('KGCodeTX|') && value.length < 16384) {
          finish(value);
        }
      },
    )
    ..setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) => initialize(),
        onWebResourceError: (error) {
          if (error.isForMainFrame == true) finish(null);
        },
      ),
    );
  try {
    await controller.loadFlutterAsset('assets/web/verify_captcha.html');
    if (!context.mounted) return null;
    return await showBetaGlassDialog<String>(
      context: context,
      barrierDismissible: false,
      label: '安全验证',
      builder: (ctx) {
        dialog = ctx;
        if (terminalPending) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => finish(pendingProof),
          );
        }
        timeout ??= Timer(const Duration(minutes: 3), () => finish(null));
        return Consumer(
          builder: (context, ref, _) {
            ref.listen(diagnosticActivityProvider, (_, running) {
              if (running) finish(null);
            });
            ref.listen(retainedKugouSessionProvider, (_, next) {
              if (next?.userId != owner.userId || next?.token != owner.token) {
                finish(null);
              }
            });
            return Dialog(
              backgroundColor: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              clipBehavior: Clip.antiAlias,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 390),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 8, 8),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '安全验证',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '取消验证',
                            onPressed: () => finish(null),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: (MediaQuery.sizeOf(context).height - 180).clamp(
                        180,
                        420,
                      ),
                      child: WebViewWidget(controller: controller),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  } finally {
    finished = true;
    timeout?.cancel();
    // Remove the callback before the native view is released.
    unawaited(
      controller
          .removeJavaScriptChannel('CaptchaChannel')
          .catchError((Object _) {}),
    );
  }
}
