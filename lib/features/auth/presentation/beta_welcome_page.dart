import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/persistence/app_preferences.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../../../shared/widgets/music_notice.dart';
import '../../../shared/widgets/beta_page_motion.dart';
import '../../legal/presentation/disclaimer_dialog.dart';
import '../../legal/presentation/legal_documents_page.dart';
import '../../legal/domain/legal_documents.dart';
import '../../music_platform/presentation/platform_login_options_page.dart';
import '../../music_platform/domain/platform_session.dart';
import '../beta_account_choice.dart';
import '../beta_entry_flow.dart';
import 'mesting_music_companions.dart';
import 'beta_consent_row.dart';
import '../../themes/music_typography.dart';

/// Every entry/form uses a painted page with reversible spatial movement.
Route<T> betaEntryRoute<T>(Widget page) => betaContentRoute<T>(page);

class BetaWelcomePage extends ConsumerStatefulWidget {
  const BetaWelcomePage({this.onExperience, super.key});
  final VoidCallback? onExperience;
  @override
  ConsumerState<BetaWelcomePage> createState() => _BetaWelcomePageState();
}

class _BetaWelcomePageState extends ConsumerState<BetaWelcomePage> {
  late bool _accepted = hasAcceptedLegalDocuments(
    ref.read(sharedPreferencesProvider),
  );
  bool _opening = false;
  Future<bool> _consent() async {
    if (!_accepted) {
      showMusicNotice(
        context,
        icon: Icons.info_outline,
        title: '请先阅读并同意协议与隐私政策',
        message: '',
      );
      return false;
    }
    await saveLegalDocumentConsent(ref.read(sharedPreferencesProvider));
    return mounted;
  }

  Future<void> _platform(MusicPlatform platform) async {
    if (_opening || !await _consent() || !mounted) return;
    setState(() => _opening = true);
    final result = await Navigator.of(
      context,
    ).push<bool>(betaEntryRoute(PlatformLoginOptionsPage(platform: platform)));
    if (!mounted) return;
    setState(() => _opening = false);
    if (result == true) widget.onExperience?.call();
  }

  Future<void> _guest() async {
    await ref
        .read(betaAccountChoiceProvider.notifier)
        .select(BetaAccountChoice.guest);
    await ref.read(betaEntryFlowProvider.notifier).finish();
    if (mounted) widget.onExperience?.call();
  }

  void _legal(LegalDocumentType type) => Navigator.of(
    context,
  ).push(betaEntryRoute(Scaffold(body: LegalDocumentPage(documentType: type))));
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      key: const ValueKey('beta10-welcome-page'),
      body: ColoredBox(
        color: dark ? const Color(0xFF0C0D0F) : const Color(0xFFF5F5F7),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, bounds) => Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: SingleChildScrollView(
                  padding: EdgeInsets.zero,
                  child: ColoredBox(
                    // Backdrop sampling must see the welcome surface inside
                    // the scroll pass as well as behind the Scaffold.
                    color: dark
                        ? const Color(0xFF0C0D0F)
                        : const Color(0xFFF5F5F7),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: (bounds.maxHeight - 40).clamp(
                            0,
                            double.infinity,
                          ),
                        ),
                        child: IntrinsicHeight(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Spacer(flex: 2),
                              MestingMusicCompanions(
                                height: (bounds.maxHeight * .32).clamp(
                                  180,
                                  260,
                                ),
                              ),
                              const Text(
                                'Mesting Music',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: MusicTypography.largeTitleSize,
                                  fontWeight: MusicTypography.titleWeight,
                                  letterSpacing: -1,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '让喜欢的音乐，陪你多一会儿。',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: MusicTypography.subheadlineSize,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withValues(alpha: .7),
                                ),
                              ),
                              const Spacer(flex: 3),
                              const SizedBox(height: 38),
                              BetaGlassButton(
                                key: const ValueKey('welcome-kugou-login'),
                                blue: true,
                                onPressed: _opening
                                    ? null
                                    : () => _platform(MusicPlatform.kugou),
                                child: const Text('酷狗登录'),
                              ),
                              const SizedBox(height: 14),
                              BetaGlassButton(
                                key: const ValueKey('welcome-netease-login'),
                                onPressed: _opening
                                    ? null
                                    : () => _platform(MusicPlatform.netease),
                                child: const Text('网易云登录'),
                              ),
                              const SizedBox(height: 14),
                              BetaGlassButton(
                                key: const ValueKey('welcome-qishui-login'),
                                onPressed: _opening
                                    ? null
                                    : () => _platform(MusicPlatform.qishui),
                                child: const Text('汽水登录'),
                              ),
                              const SizedBox(height: 18),
                              BetaGlassButton(
                                onPressed: _opening ? null : _guest,
                                child: const Text('游客体验'),
                              ),
                              const SizedBox(height: 24),
                              BetaConsentRow(
                                accepted: _accepted,
                                onChanged: (value) =>
                                    setState(() => _accepted = value),
                                onAgreement: () =>
                                    _legal(LegalDocumentType.userAgreement),
                                onPrivacy: () =>
                                    _legal(LegalDocumentType.privacyPolicy),
                              ),
                              const Spacer(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
