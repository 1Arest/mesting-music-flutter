import 'package:flutter/services.dart';
import '../../../core/network/music_network_diagnostics.dart';
import '../../../core/security/credential_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/persistence/app_preferences.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/beta_success_feedback.dart';
import '../beta_entry_flow.dart';
import '../beta_entry_back_state.dart';
import '../../music_platform/music_platform_providers.dart';
import 'beta_welcome_page.dart';
import 'beta_onboarding_page.dart';
import '../../../core/audio/login_success_sound.dart';
import '../../../core/haptics/app_haptics.dart';

/// Owns entry presentation above the router, so a session publication cannot
/// unmount the login before its success HUD and tour have finished. Credentials
/// remain in their existing controllers; restoration never emits login events.
class BetaEntryCoordinator extends ConsumerStatefulWidget {
  const BetaEntryCoordinator({
    required this.child,
    this.onLogout,
    this.backDispatcher,
    super.key,
  });
  final Widget child;
  final VoidCallback? onLogout;
  final BackButtonDispatcher? backDispatcher;
  @override
  ConsumerState<BetaEntryCoordinator> createState() =>
      _BetaEntryCoordinatorState();
}

class _BetaEntryCoordinatorState extends ConsumerState<BetaEntryCoordinator> {
  final _navigator = GlobalKey<NavigatorState>();
  final _guide = GlobalKey<BetaOnboardingPageState>();
  ChildBackButtonDispatcher? _back;
  late final _backState = ref.read(betaEntryBackStateProvider);

  @override
  void initState() {
    super.initState();
    // This entry navigator lives above Router, so BackButtonListener cannot
    // discover its dispatcher. Inject a child dispatcher from the app boundary.
    _back = widget.backDispatcher?.createChildBackButtonDispatcher();
    _back?.addCallback(_handleBack);
    // MaterialApp.builder mounts this coordinator before its Router child.
    // Taking priority now asserts in debug and races router registration in
    // release. Claim it only after the owning Router has installed callbacks.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (widget.backDispatcher?.hasCallbacks ?? false)) {
        _back?.takePriority();
      }
    });
  }

  Future<bool> _handleBack() async {
    final stage = ref.read(betaEntryFlowProvider);
    if (stage == BetaEntryStage.success || stage == BetaEntryStage.guide) {
      _guide.currentState?.goBack();
      return true;
    }
    final navigator = _navigator.currentState;
    if (navigator != null && navigator.canPop()) return navigator.maybePop();
    return false;
  }

  @override
  void dispose() {
    _backState.update(active: false, guide: false);
    _back?.removeCallback(_handleBack);
    if (_back != null) widget.backDispatcher?.forget(_back!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(betaEntryFlowProvider, (previous, next) {
      if (next == BetaEntryStage.success && previous != next) {
        // An explicit authentication event owns the one-shot UI sound.
        // Restoration/refresh never enters this stage.
        LoginSuccessSound.play();
        appHaptic(context, AppHapticEvent.success);
      }
      if (next == BetaEntryStage.welcome && previous != next) {
        // Let the welcome surface cover the old route before its stack resets.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onLogout?.call();
        });
      }
    });
    final stage = ref.watch(betaEntryFlowProvider);
    final platform = ref.watch(platformAccountProvider);
    final completed =
        ref
            .read(sharedPreferencesProvider)
            .getBool(BetaEntryFlow.completedKey) ==
        true;
    final restored = platform.value != null;
    final first =
        stage == BetaEntryStage.idle &&
        !completed &&
        !restored &&
        !platform.hasError;
    Widget overlay = const SizedBox.shrink(key: ValueKey('entry-app'));
    if (stage == BetaEntryStage.welcome || first) {
      // Music login and guest entry depend only on their own local store. Only the platform's local credential read gates this frame.
      overlay = first && platform.isLoading
          ? const Center(
              key: ValueKey('entry-restoring'),
              child: BetaActivityIndicator(label: '正在恢复账号'),
            )
          : HeroControllerScope.none(
              // Entry owns a separate Navigator above the app's Router. It
              // must not claim MaterialApp's controller, which already belongs
              // to the app Navigator. Its spatial routes animate themselves.
              child: Navigator(
                key: _navigator,
                observers: [_backState],
                onGenerateRoute: (_) =>
                    betaEntryRoute<void>(const BetaWelcomePage()),
              ),
            );
    } else if (stage == BetaEntryStage.success ||
        stage == BetaEntryStage.guide) {
      // A single stable subtree owns success + guide. No outgoing/incoming
      // transparent cross-fade can expose the routed home for even one frame.
      overlay = Stack(
        fit: StackFit.expand,
        children: [
          // The guide is visible and interactive from the success event's
          // first frame. Keep this exact state across the HUD's dismissal so
          // early Next/Skip actions cannot be reset by a delayed callback.
          BetaOnboardingPage(
            key: _guide,
            onFinish: () => ref.read(betaEntryFlowProvider.notifier).finish(),
          ),
          if (stage == BetaEntryStage.success)
            Positioned.fill(
              child: IgnorePointer(
                child: BetaLoginSuccess(
                  key: const ValueKey('entry-success'),
                  onComplete: () =>
                      ref.read(betaEntryFlowProvider.notifier).showGuide(),
                ),
              ),
            ),
        ],
      );
    } else if (platform.isLoading || platform.hasError) {
      // An unreadable credential is not a guest account. Keep the music app
      // mounted, but expose an honest, retryable restoration state.
      overlay = _AccountRestoreSurface(
        loading: platform.isLoading,
        error: platform.error,
        onRetry: () => ref.invalidate(platformAccountProvider),
        onLogin: () => ref.read(betaEntryFlowProvider.notifier).welcome(),
      );
    }
    final active =
        stage == BetaEntryStage.welcome ||
        first ||
        stage == BetaEntryStage.success ||
        stage == BetaEntryStage.guide ||
        platform.isLoading ||
        platform.hasError;
    _backState.update(
      active: active,
      guide: stage == BetaEntryStage.success || stage == BetaEntryStage.guide,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        TickerMode(
          enabled: !active,
          child: ExcludeFocus(
            excluding: active,
            child: ExcludeSemantics(
              excluding: active,
              child: IgnorePointer(ignoring: active, child: widget.child),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !active,
            child: active
                ? ColoredBox(
                    key: ValueKey(
                      stage == BetaEntryStage.success ||
                              stage == BetaEntryStage.guide
                          ? 'tour'
                          : stage == BetaEntryStage.idle
                          ? 'first'
                          : stage.name,
                    ),
                    color: Theme.of(context).colorScheme.surface,
                    child: overlay,
                  )
                : overlay,
          ),
        ),
      ],
    );
  }
}

/// This overlay sits above the Router's Material/Scaffold. Own its text and
/// safe-area context so a failed cold restore never inherits WidgetsApp's large
/// red diagnostic text style. Storage recovery remains controller-owned.
class _AccountRestoreSurface extends StatelessWidget {
  const _AccountRestoreSurface({
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onLogin,
  });

  final bool loading;
  final Object? error;
  final VoidCallback onRetry, onLogin;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: loading
              ? const BetaActivityIndicator(label: '正在恢复账号')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      error is CredentialStoreException
                          ? (error as CredentialStoreException).message
                          : '账号暂未恢复，登录信息已保留',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    if (!(error is CredentialStoreException &&
                        (error as CredentialStoreException)
                            .requiresReauthentication)) ...[
                      BetaGlassButton(
                        onPressed: onRetry,
                        child: const Text('重试恢复'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    BetaGlassButton(
                      onPressed: onLogin,
                      child: const Text('重新登录'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Clipboard.setData(
                        ClipboardData(
                          text: MusicNetworkDiagnostics.shared.export(),
                        ),
                      ),
                      child: const Text('复制恢复诊断'),
                    ),
                  ],
                ),
        ),
      ),
    ),
  );
}
