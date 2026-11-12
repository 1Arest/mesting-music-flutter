import '../../../shared/widgets/beta_page_motion.dart';
import '../../../shared/widgets/artwork_scroll_frontier.dart';
import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/app_preferences.dart';
import '../../../core/platform/distribution_channel.dart';
import '../../../shared/widgets/liquid_glass_sheet.dart';
import '../../themes/music_theme_tokens.dart';
import '../domain/legal_documents.dart';
import 'legal_documents_page.dart';
import '../../player/presentation/music_page_transition.dart';
import '../../themes/music_typography.dart';

const disclaimerAcceptedPreferenceKey = 'mesting_disclaimer_accepted_v1';
const disclaimerReadPreferenceKey = 'mesting_disclaimer_read_v1';
const userAgreementAcceptedPreferenceKey = 'mesting_user_agreement_accepted_v1';
const privacyPolicyAcceptedPreferenceKey = 'mesting_privacy_policy_accepted_v1';
const legalDocumentsReadPreferenceKey = 'mesting_legal_documents_read_v1';
const liquidGlassDisclaimerSurfaceKey = ValueKey<String>(
  'liquid-glass-disclaimer-surface',
);
const liquidGlassDisclaimerCloseActionKey = ValueKey<String>(
  'liquid-glass-disclaimer-close-action',
);

bool hasAcceptedLegalDocuments(SharedPreferences preferences) {
  return preferences.getBool(userAgreementAcceptedPreferenceKey) == true &&
      preferences.getBool(privacyPolicyAcceptedPreferenceKey) == true;
}

Future<void> saveLegalDocumentConsent(SharedPreferences preferences) async {
  await Future.wait([
    preferences.setBool(userAgreementAcceptedPreferenceKey, true),
    preferences.setBool(privacyPolicyAcceptedPreferenceKey, true),
    preferences.setBool(legalDocumentsReadPreferenceKey, true),
    // Keep the old acknowledgement keys for existing local flows and update
    // scheduling. They are not used to infer consent to the new documents.
    preferences.setBool(disclaimerAcceptedPreferenceKey, true),
    preferences.setBool(disclaimerReadPreferenceKey, true),
  ]);
}

class FirstLaunchDisclaimerCoordinator extends ConsumerStatefulWidget {
  const FirstLaunchDisclaimerCoordinator({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<FirstLaunchDisclaimerCoordinator> createState() =>
      _FirstLaunchDisclaimerCoordinatorState();
}

class _FirstLaunchDisclaimerCoordinatorState
    extends ConsumerState<FirstLaunchDisclaimerCoordinator> {
  late bool _visible;

  @override
  void initState() {
    super.initState();
    // Beta's welcome page owns explicit, unchecked first-use consent. Removing
    // this second blocking card must never manufacture acceptance in storage.
    _visible =
        !DistributionChannel.isBeta &&
        !hasAcceptedLegalDocuments(ref.read(sharedPreferencesProvider));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_visible,
      child: Stack(
        children: [
          widget.child,
          if (_visible)
            Positioned.fill(
              child: _DisclaimerOverlay(
                animation: const AlwaysStoppedAnimation<double>(1),
                reduceMotion: true,
                requiredAcceptance: true,
                onResult: _accept,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _accept(bool accepted) async {
    if (!accepted) return;
    final preferences = ref.read(sharedPreferencesProvider);
    await saveLegalDocumentConsent(preferences);
    if (mounted) setState(() => _visible = false);
  }
}

Future<void> showDisclaimerDialog(
  BuildContext context, {
  bool useMusicHubPanelTransition = false,
}) {
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  final animateLikeMusicHub = useMusicHubPanelTransition && !reduceMotion;
  return showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: '关闭免责声明',
    barrierColor: Colors.transparent,
    transitionDuration: reduceMotion
        ? Duration.zero
        : animateLikeMusicHub
        ? musicHubDestinationTransitionDuration
        : const Duration(milliseconds: 360),
    pageBuilder: (context, animation, secondaryAnimation) => _DisclaimerOverlay(
      animation: animation,
      // The outer route owns this entrance when it comes from the music hub.
      // Leaving the card static avoids layering a second fade/scale over the
      // shared drawer motion.
      reduceMotion: reduceMotion || animateLikeMusicHub,
      requiredAcceptance: false,
      onResult: (_) => Navigator.of(context).pop(),
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) =>
        animateLikeMusicHub
        ? MusicHubDestinationLayerHandoff(
            primaryAnimation: animation,
            secondaryAnimation: secondaryAnimation,
            blockUnderlyingContent: true,
            child: child,
          )
        : child,
  );
}

Future<bool> showRequiredDisclaimerReading(
  BuildContext context, {
  Duration minimumReadDuration = const Duration(seconds: 5),
}) async {
  final result = await showLiquidGlassBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (context) =>
        _TimedDisclaimerSheet(minimumReadDuration: minimumReadDuration),
  );
  return result == true;
}

class _TimedDisclaimerSheet extends StatefulWidget {
  const _TimedDisclaimerSheet({required this.minimumReadDuration});

  final Duration minimumReadDuration;

  @override
  State<_TimedDisclaimerSheet> createState() => _TimedDisclaimerSheetState();
}

class _TimedDisclaimerSheetState extends State<_TimedDisclaimerSheet> {
  Timer? _timer;
  late int _secondsRemaining;

  @override
  void initState() {
    super.initState();
    _secondsRemaining = widget.minimumReadDuration.inSeconds;
    if (_secondsRemaining > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        setState(() => _secondsRemaining -= 1);
        if (_secondsRemaining <= 0) timer.cancel();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: tokens.textMuted.withValues(alpha: .35),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '用户协议与隐私政策',
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: MusicTypography.sectionTitleSize,
                            fontWeight: MusicTypography.titleWeight,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '请了解服务规则与数据处理方式',
                          style: TextStyle(
                            color: tokens.textSecondary,
                            fontSize: MusicTypography.captionSize,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '暂不阅读',
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: tokens.border),
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                physics: BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(18, 16, 18, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '继续前，请分别查看以下文件。阅读后返回本页确认即可；不同意时可关闭并停止登录或注册。',
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: MusicTypography.captionSize,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _TimedLegalDocumentLink(
                      document: legalDocumentFor(
                        LegalDocumentType.userAgreement,
                      ),
                      onTap: () =>
                          _openDocument(LegalDocumentType.userAgreement),
                    ),
                    const SizedBox(height: 9),
                    _TimedLegalDocumentLink(
                      document: legalDocumentFor(
                        LegalDocumentType.privacyPolicy,
                      ),
                      onTap: () =>
                          _openDocument(LegalDocumentType.privacyPolicy),
                    ),
                    const SizedBox(height: 16),
                    const _DisclaimerIntro(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  key: const ValueKey('disclaimer-read-confirm'),
                  onPressed: _secondsRemaining <= 0
                      ? () => Navigator.pop(context, true)
                      : null,
                  child: Text(
                    _secondsRemaining > 0
                        ? '请继续阅读 $_secondsRemaining 秒'
                        : '我已阅读并理解',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDocument(LegalDocumentType type) async {
    await Navigator.of(context).push<void>(
      MestingPageRoute<void>(
        builder: (_) => Material(
          color: Theme.of(context).colorScheme.surface,
          child: LegalDocumentPage(documentType: type),
        ),
      ),
    );
  }
}

class _DisclaimerOverlay extends StatelessWidget {
  const _DisclaimerOverlay({
    required this.animation,
    required this.reduceMotion,
    required this.requiredAcceptance,
    required this.onResult,
  });

  final Animation<double> animation;
  final bool reduceMotion;
  final bool requiredAcceptance;
  final ValueChanged<bool> onResult;

  @override
  Widget build(BuildContext context) {
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final scrimMotion = reduceMotion
        ? const AlwaysStoppedAnimation<double>(1)
        : CurvedAnimation(
            parent: animation,
            curve: const Interval(0, .55, curve: Curves.easeOutCubic),
            reverseCurve: const Interval(.3, 1, curve: Curves.easeInCubic),
          );
    final cardMotion = reduceMotion
        ? const AlwaysStoppedAnimation<double>(1)
        : CurvedAnimation(
            parent: animation,
            curve: const Interval(.05, 1, curve: Curves.easeOutCubic),
            reverseCurve: const Interval(.3, 1, curve: Curves.easeInCubic),
          );

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: FadeTransition(
              key: const ValueKey('disclaimer-scrim-transition'),
              opacity: scrimMotion,
              child: const ColoredBox(color: Color(0x730A0D14)),
            ),
          ),
          SafeArea(
            minimum: EdgeInsets.fromLTRB(
              14,
              requiredAcceptance ? 22 : 14,
              14,
              viewPadding.bottom > 0 ? 8 : 14,
            ),
            child: Center(
              child: FadeTransition(
                key: const ValueKey('disclaimer-card-transition'),
                opacity: cardMotion,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, .018),
                    end: Offset.zero,
                  ).animate(cardMotion),
                  child: ScaleTransition(
                    scale: Tween<double>(
                      begin: .985,
                      end: 1,
                    ).animate(cardMotion),
                    child: requiredAcceptance
                        ? _RequiredLegalConsentCard(onResult: onResult)
                        : _DisclaimerCard(
                            requiredAcceptance: false,
                            onResult: onResult,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequiredLegalConsentCard extends StatefulWidget {
  const _RequiredLegalConsentCard({required this.onResult});

  final ValueChanged<bool> onResult;

  @override
  State<_RequiredLegalConsentCard> createState() =>
      _RequiredLegalConsentCardState();
}

class _RequiredLegalConsentCardState extends State<_RequiredLegalConsentCard> {
  LegalDocumentType? _reading;
  bool _acceptedUserAgreement = false;
  bool _acceptedPrivacyPolicy = false;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 430, maxHeight: size.height - 68),
      child: LiquidGlassSurface(
        key: liquidGlassDisclaimerSurfaceKey,
        child: Material(
          type: MaterialType.transparency,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _reading == null
                ? _buildConsent(context)
                : _buildReader(context, legalDocumentFor(_reading!)),
          ),
        ),
      ),
    );
  }

  Widget _buildConsent(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final canContinue = _acceptedUserAgreement && _acceptedPrivacyPolicy;
    return Column(
      key: const ValueKey('legal-consent-landing'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.textPrimary.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.music_note_rounded,
                  color: tokens.textPrimary,
                  size: 25,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '使用前请先了解',
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: MusicTypography.sectionTitleSize,
                        fontWeight: MusicTypography.titleWeight,
                        letterSpacing: -.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '请分别阅读并确认两份法律文件',
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: MusicTypography.smallCaptionSize,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: tokens.border),
        Flexible(
          fit: FlexFit.loose,
          child: SingleChildScrollView(
            physics: const ArtworkFrontierPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '为提供账号、音乐同步与社交服务，我们需要按《隐私政策》处理必要的信息；使用服务还应遵守《用户协议》。不同意时，你可以退出应用。',
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: MusicTypography.captionSize,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 17),
                _LegalConsentChoice(
                  document: legalDocumentFor(LegalDocumentType.userAgreement),
                  checked: _acceptedUserAgreement,
                  onChanged: (value) =>
                      setState(() => _acceptedUserAgreement = value),
                  onRead: () => setState(
                    () => _reading = LegalDocumentType.userAgreement,
                  ),
                ),
                const SizedBox(height: 10),
                _LegalConsentChoice(
                  document: legalDocumentFor(LegalDocumentType.privacyPolicy),
                  checked: _acceptedPrivacyPolicy,
                  onChanged: (value) =>
                      setState(() => _acceptedPrivacyPolicy = value),
                  onRead: () => setState(
                    () => _reading = LegalDocumentType.privacyPolicy,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  key: const ValueKey('legal-consent-confirm'),
                  onPressed: canContinue ? () => widget.onResult(true) : null,
                  child: const Text('同意并继续使用'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '之后可在“设置 > 隐私与协议”中再次查看',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: MusicTypography.smallCaptionSize,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReader(BuildContext context, LegalDocument document) {
    final tokens = context.musicThemeTokens;
    return Column(
      key: ValueKey('legal-consent-reader-${document.type.name}'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 18, 12),
          child: Row(
            children: [
              IconButton(
                key: const ValueKey('legal-consent-reader-back'),
                tooltip: '返回同意页',
                onPressed: () => setState(() => _reading = null),
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.title,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: MusicTypography.headingSize,
                        fontWeight: MusicTypography.titleWeight,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      document.effectiveDate,
                      style: TextStyle(
                        color: tokens.textMuted,
                        fontSize: MusicTypography.smallCaptionSize,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: tokens.border),
        Flexible(
          child: SingleChildScrollView(
            physics: const ArtworkFrontierPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: LegalDocumentContent(document: document),
          ),
        ),
      ],
    );
  }
}

class _TimedLegalDocumentLink extends StatelessWidget {
  const _TimedLegalDocumentLink({required this.document, required this.onTap});

  final LegalDocument document;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Material(
      color: tokens.glassSubtle,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: ValueKey('timed-legal-${document.type.name}-open'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '查看《${document.title}》',
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: MusicTypography.footnoteSize,
                        fontWeight: MusicTypography.bodyWeight,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      document.summary,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: MusicTypography.smallCaptionSize,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.open_in_new_rounded,
                color: tokens.textMuted,
                size: 19,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegalConsentChoice extends StatelessWidget {
  const _LegalConsentChoice({
    required this.document,
    required this.checked,
    required this.onChanged,
    required this.onRead,
  });

  final LegalDocument document;
  final bool checked;
  final ValueChanged<bool> onChanged;
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Material(
      color: tokens.glassSubtle,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 11, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              key: ValueKey('legal-consent-${document.type.name}-checkbox'),
              value: checked,
              onChanged: (value) => onChanged(value ?? false),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: InkWell(
                key: ValueKey('legal-consent-${document.type.name}-open'),
                onTap: onRead,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(3, 3, 0, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '我已阅读并同意《${document.title}》',
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: MusicTypography.footnoteSize,
                          fontWeight: MusicTypography.bodyWeight,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        document.summary,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: MusicTypography.smallCaptionSize,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: tokens.textMuted),
          ],
        ),
      ),
    );
  }
}

class _DisclaimerCard extends StatelessWidget {
  const _DisclaimerCard({
    required this.requiredAcceptance,
    required this.onResult,
  });

  final bool requiredAcceptance;
  final ValueChanged<bool> onResult;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconBackground = isDark
        ? const Color(0xFF232833)
        : const Color(0xFFEFF2F7);
    final iconForeground = isDark
        ? const Color(0xFFCFD7E6)
        : const Color(0xFF4D5E7A);
    final iconBorder = isDark
        ? const Color(0xFF48505E)
        : const Color(0xFFD5DBE5);
    final size = MediaQuery.sizeOf(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 430,
        maxHeight: size.height - (requiredAcceptance ? 68 : 44),
      ),
      child: LiquidGlassSurface(
        key: liquidGlassDisclaimerSurfaceKey,
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 18, 13),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: iconBackground,
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(color: iconBorder),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? .18 : .07,
                            ),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.music_note_rounded,
                        color: iconForeground,
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            requiredAcceptance ? '使用前请先了解' : '免责声明',
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontSize: MusicTypography.sectionTitleSize,
                              fontWeight: MusicTypography.titleWeight,
                              letterSpacing: -.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '关于在线音乐、版权与账号数据',
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: MusicTypography.smallCaptionSize,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!requiredAcceptance)
                      _DisclaimerCloseButton(onTap: () => onResult(false)),
                  ],
                ),
              ),
              Divider(height: 1, color: tokens.border),
              Flexible(
                child: SingleChildScrollView(
                  physics: const ArtworkFrontierPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 13),
                  child: Column(
                    children: const [
                      _DisclaimerIntro(),
                      SizedBox(height: 12),
                      _DisclaimerItem(
                        number: '01',
                        title: '项目性质',
                        content:
                            'Mesting Music 是个人学习与作品展示项目，并非任何音乐平台的官方客户端，不提供破解会员、规避付费或版权限制的服务。',
                      ),
                      _DisclaimerItem(
                        number: '02',
                        title: '音乐与素材版权',
                        content:
                            '歌曲、歌词、封面及角色素材可能来自本地文件或第三方公开接口，相关权利归原权利人所有，仅供个人体验与功能展示，请勿下载后再次传播或用于商业用途。',
                      ),
                      _DisclaimerItem(
                        number: '03',
                        title: '在线服务可用性',
                        content:
                            '第三方音乐接口可能因网络、地区、会员或版权规则发生变化，应用不保证所有内容持续可搜索、播放或拥有完整歌词。',
                      ),
                      _DisclaimerItem(
                        number: '04',
                        title: '账号与隐私',
                        content:
                            '邮箱和手机号仅用于账号验证；登录凭证会安全保存在当前设备。登录后，收藏、歌单和个人资料会同步到账号云端；网络暂不可用时先保存在本机，恢复连接后继续同步。',
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                child: Column(
                  children: [
                    _DisclaimerAction(
                      label: requiredAcceptance ? '我已阅读，继续使用' : '关闭',
                      icon: requiredAcceptance
                          ? Icons.arrow_forward_rounded
                          : null,
                      liquidGlass: !requiredAcceptance,
                      onTap: () => onResult(requiredAcceptance),
                    ),
                    if (requiredAcceptance) ...[
                      const SizedBox(height: 9),
                      Text(
                        '之后可在左上角菜单的“免责声明”中再次查看',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: tokens.textMuted,
                          fontSize: MusicTypography.smallCaptionSize,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisclaimerIntro extends StatelessWidget {
  const _DisclaimerIntro();

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF222731) : const Color(0xFFF4F6F9);
    final border = isDark ? const Color(0xFF48505E) : const Color(0xFFD4DAE4);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Text(
        '继续使用即表示你已了解以下内容，并同意仅在合法、个人体验的范围内使用本应用。',
        style: TextStyle(
          color: tokens.textSecondary,
          fontSize: MusicTypography.smallCaptionSize,
          height: 1.55,
          fontWeight: MusicTypography.bodyWeight,
        ),
      ),
    );
  }
}

class _DisclaimerItem extends StatelessWidget {
  const _DisclaimerItem({
    required this.number,
    required this.title,
    required this.content,
  });

  final String number;
  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final marker = isDark ? const Color(0xFFC8D2E2) : const Color(0xFF536889);
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: marker.withValues(alpha: isDark ? .13 : .1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: marker.withValues(alpha: .2)),
            ),
            child: Text(
              number,
              style: TextStyle(
                color: marker,
                fontSize: MusicTypography.smallCaptionSize,
                fontWeight: MusicTypography.bodyWeight,
                letterSpacing: .5,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: MusicTypography.captionSize,
                    fontWeight: MusicTypography.bodyWeight,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: MusicTypography.smallCaptionSize,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DisclaimerAction extends StatelessWidget {
  const _DisclaimerAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.liquidGlass = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool liquidGlass;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (liquidGlass) {
      final tokens = context.musicThemeTokens;
      final radius = BorderRadius.circular(17);
      final foreground = isDark
          ? const Color(0xFFF7F9FC)
          : const Color(0xFF34435D);
      return RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: tokens.shadow.withValues(alpha: isDark ? .76 : .6),
                blurRadius: 20,
                spreadRadius: -5,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: const Color(
                  0xFF6072A3,
                ).withValues(alpha: isDark ? .13 : .18),
                blurRadius: 26,
                spreadRadius: -10,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              key: liquidGlassDisclaimerCloseActionKey,
              filter: ImageFilter.blur(
                sigmaX: 16,
                sigmaY: 16,
                tileMode: TileMode.decal,
              ),
              child: DecoratedBox(
                key: const ValueKey('disclaimer-close-action-glass-fill'),
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: isDark ? .22 : .62),
                    width: .9,
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? const [Color(0xC4475268), Color(0xB828303F)]
                        : const [Color(0xD9E2E8F5), Color(0xC8CCD7EA)],
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: const ValueKey('disclaimer-close-action'),
                    onTap: onTap,
                    child: SizedBox(
                      height: 50,
                      child: _DisclaimerActionContent(
                        label: label,
                        icon: icon,
                        color: foreground,
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
    final buttonColor = isDark
        ? const Color(0xFFD0D7E4)
        : const Color(0xFF41526F);
    final contentColor = isDark
        ? const Color(0xFF1D222C)
        : const Color(0xFFFAFBFD);
    final borderColor = isDark
        ? const Color(0xFFCBD4E3)
        : const Color(0xFF637391);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Ink(
          height: 50,
          decoration: BoxDecoration(
            color: buttonColor,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? .2 : .1),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: _DisclaimerActionContent(
            label: label,
            icon: icon,
            color: contentColor,
          ),
        ),
      ),
    );
  }
}

class _DisclaimerActionContent extends StatelessWidget {
  const _DisclaimerActionContent({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: MusicTypography.footnoteSize,
            fontWeight: MusicTypography.bodyWeight,
          ),
        ),
        if (icon case final icon?) ...[
          const SizedBox(width: 8),
          Icon(icon, color: color, size: 18),
        ],
      ],
    );
  }
}

class _DisclaimerCloseButton extends StatelessWidget {
  const _DisclaimerCloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Tooltip(
      message: '关闭免责声明',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tokens.glassSubtle,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: tokens.border),
            ),
            child: Icon(
              Icons.close_rounded,
              color: tokens.textPrimary,
              size: 21,
            ),
          ),
        ),
      ),
    );
  }
}
