import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/persistence/app_preferences.dart';
import '../../auth/beta_entry_flow.dart';
import '../../music_platform/music_platform_providers.dart';
import '../../themes/music_typography.dart';
import '../../themes/personal_style.dart';

/// Not auto-disposed: route changes and background/foreground must not replay
/// a cold-process greeting. A new ProviderScope on cold start gets a fresh flag.
final coldGreetingUsedProvider = NotifierProvider<_GreetingUsed, bool>(
  _GreetingUsed.new,
);

class _GreetingUsed extends Notifier<bool> {
  @override
  bool build() => false;
  void consume() => state = true;
}

class ColdStartGreeting extends ConsumerStatefulWidget {
  const ColdStartGreeting({super.key});
  @override
  ConsumerState<ColdStartGreeting> createState() => _ColdStartGreetingState();
}

class _ColdStartGreetingState extends ConsumerState<ColdStartGreeting>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _visible = false, _scheduled = false, _notes = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _timer?.cancel();
      if (mounted) {
        setState(() {
          _visible = false;
          _notes = false;
        });
      }
    }
  }

  void _finishGreeting() {
    if (!mounted) return;
    setState(() => _visible = false);
    _timer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted ||
          !ref.read(personalStyleProvider).discoveryNotes ||
          MediaQuery.disableAnimationsOf(context) ||
          !TickerMode.valuesOf(context).enabled ||
          !(ModalRoute.isCurrentOf(context) ?? true)) {
        return;
      }
      setState(() => _notes = true);
      _timer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _notes = false);
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stage = ref.watch(betaEntryFlowProvider);
    final account = ref.watch(platformAccountProvider);
    final completed =
        ref
            .read(sharedPreferencesProvider)
            .getBool(BetaEntryFlow.completedKey) ==
        true;
    final ready =
        stage == BetaEntryStage.app ||
        stage == BetaEntryStage.idle && completed;
    if (!_scheduled &&
        ready &&
        !account.isLoading &&
        !account.hasError &&
        !ref.read(coldGreetingUsedProvider)) {
      _scheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || ref.read(coldGreetingUsedProvider)) return;
        ref.read(coldGreetingUsedProvider.notifier).consume();
        setState(() => _visible = true);
        _timer = Timer(const Duration(seconds: 5), _finishGreeting);
      });
    }
    final hour = DateTime.now().hour;
    final greeting = hour < 5
        ? '夜深了'
        : hour < 11
        ? '早上好'
        : hour < 14
        ? '中午好'
        : hour < 18
        ? '下午好'
        : '晚上好';
    final name = account.value?.nickname ?? '';
    final ink = Theme.of(context).colorScheme.onSurface;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final content = AnimatedSwitcher(
      duration: reduced ? Duration.zero : const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(.06, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: !_visible
          ? (_notes &&
                    ref.watch(personalStyleProvider).discoveryNotes &&
                    !reduced
                ? Padding(
                    padding: const EdgeInsets.only(left: 14),
                    child: TweenAnimationBuilder<double>(
                      key: const ValueKey('discovery-note-flourish'),
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(seconds: 2),
                      builder: (context, t, _) => ExcludeSemantics(
                        child: Opacity(
                          opacity: (1 - (2 * t - 1).abs()).clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: Offset(0, -6 * t),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.music_note_rounded,
                                  size: 21,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                Icon(
                                  Icons.music_note_rounded,
                                  size: 14,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: .6),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink())
          : Padding(
              key: const ValueKey('beta13-cold-greeting'),
              padding: const EdgeInsets.only(left: 14, right: 8),
              child: Semantics(
                label: name.isEmpty ? greeting : '$greeting，$name',
                excludeSemantics: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greeting,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      style: TextStyle(
                        color: ink.withValues(alpha: .65),
                        fontSize: MusicTypography.smallCaptionSize,
                        fontWeight: MusicTypography.bodyWeight,
                        height: 1.25,
                      ),
                    ),
                    if (name.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: MusicTypography.footnoteSize,
                          color: ink,
                          fontWeight: MusicTypography.bodyWeight,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
    return reduced
        ? content
        : AnimatedSize(
            duration: const Duration(milliseconds: 320),
            alignment: Alignment.centerLeft,
            child: content,
          );
  }
}
