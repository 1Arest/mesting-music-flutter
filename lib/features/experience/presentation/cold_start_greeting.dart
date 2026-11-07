import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/persistence/app_preferences.dart';
import '../../auth/beta_entry_flow.dart';
import '../../auth/auth_providers.dart';
import '../../music_platform/music_platform_providers.dart';

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

class _ColdStartGreetingState extends ConsumerState<ColdStartGreeting> {
  Timer? _timer;
  bool _visible = false, _scheduled = false;
  @override
  void dispose() {
    _timer?.cancel();
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
        _timer = Timer(const Duration(seconds: 5), () {
          if (mounted) setState(() => _visible = false);
        });
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
    final name =
        account.value?.nickname ??
        ref.watch(currentUserProvider)?.nickname ??
        '';
    final ink = Theme.of(context).colorScheme.onSurface;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return AnimatedSize(
      duration: reduced ? Duration.zero : const Duration(milliseconds: 320),
      alignment: Alignment.centerLeft,
      child: AnimatedSwitcher(
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
            ? const SizedBox.shrink()
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
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
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
                            fontSize: 13,
                            color: ink,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
