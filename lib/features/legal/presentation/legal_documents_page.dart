import '../../../shared/widgets/artwork_scroll_frontier.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../themes/music_theme_tokens.dart';
import '../domain/legal_documents.dart';
import '../../themes/music_typography.dart';

class LegalDocumentsPage extends StatelessWidget {
  const LegalDocumentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final tokens = context.musicThemeTokens;
    return CustomScrollView(
      physics: const ArtworkFrontierPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            20,
            top + 14,
            20,
            BetaContentInsets.bottomOf(context, 42),
          ),
          sliver: SliverList.list(
            children: [
              _LegalPageHeader(
                title: '隐私与协议',
                subtitle: '清楚了解服务规则与数据处理方式',
                onBack: () => _goBack(context),
              ),
              const SizedBox(height: 30),
              Text(
                '你有权知道自己的信息如何被处理，也可以随时回到这里查看最新版本。',
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: MusicTypography.subheadlineSize,
                  height: 1.65,
                ),
              ),
              const SizedBox(height: 24),
              _LegalDocumentLink(
                document: legalDocumentFor(LegalDocumentType.userAgreement),
                icon: Icons.menu_book_rounded,
                onTap: () => context.push('/legal/user-agreement'),
              ),
              const SizedBox(height: 12),
              _LegalDocumentLink(
                document: legalDocumentFor(LegalDocumentType.privacyPolicy),
                icon: Icons.verified_user_outlined,
                onTap: () => context.push('/legal/privacy-policy'),
              ),
              const SizedBox(height: 30),
              Text(
                '协议更新',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: MusicTypography.bodySize,
                  fontWeight: MusicTypography.titleWeight,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '若协议或数据处理方式发生重要变化，应用会在需要时提示你重新确认。',
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: MusicTypography.captionSize,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({required this.documentType, super.key});

  final LegalDocumentType documentType;

  @override
  Widget build(BuildContext context) {
    final document = legalDocumentFor(documentType);
    final top = MediaQuery.paddingOf(context).top;
    final tokens = context.musicThemeTokens;
    return CustomScrollView(
      physics: const ArtworkFrontierPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            20,
            top + 14,
            20,
            BetaContentInsets.bottomOf(context, 48),
          ),
          sliver: SliverList.list(
            children: [
              _LegalPageHeader(
                title: document.title,
                subtitle: document.effectiveDate,
                onBack: () => _goBack(context),
              ),
              const SizedBox(height: 28),
              Text(
                document.summary,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: MusicTypography.subheadlineSize,
                  height: 1.65,
                ),
              ),
              const SizedBox(height: 28),
              LegalDocumentContent(document: document),
            ],
          ),
        ),
      ],
    );
  }
}

class LegalDocumentContent extends StatelessWidget {
  const LegalDocumentContent({required this.document, super.key});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final section in document.sections) ...[
          Text(
            section.title,
            style: TextStyle(
              color: tokens.textPrimary,
              fontSize: MusicTypography.bodySize,
              height: 1.35,
              fontWeight: MusicTypography.titleWeight,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            section.body,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: MusicTypography.footnoteSize,
              height: 1.72,
            ),
          ),
          const SizedBox(height: 26),
        ],
      ],
    );
  }
}

class _LegalPageHeader extends StatelessWidget {
  const _LegalPageHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Row(
      children: [
        Material(
          color: tokens.glassStrong,
          borderRadius: BorderRadius.circular(17),
          child: InkWell(
            key: const ValueKey('legal-page-back'),
            onTap: onBack,
            borderRadius: BorderRadius.circular(17),
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: tokens.borderStrong),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: tokens.textPrimary,
                size: 21,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontSize: MusicTypography.titleSize,
                  height: 1.05,
                  fontWeight: MusicTypography.titleWeight,
                  letterSpacing: -.7,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: TextStyle(
                  color: tokens.textSecondary,
                  fontSize: MusicTypography.smallCaptionSize,
                  fontWeight: MusicTypography.bodyWeight,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LegalDocumentLink extends StatelessWidget {
  const _LegalDocumentLink({
    required this.document,
    required this.icon,
    required this.onTap,
  });

  final LegalDocument document;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.musicThemeTokens;
    return Material(
      color: tokens.glassStrong,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: ValueKey('legal-document-${document.type.name}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
          child: Row(
            children: [
              Icon(icon, color: tokens.textPrimary, size: 25),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.title,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: MusicTypography.calloutSize,
                        fontWeight: MusicTypography.bodyWeight,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      document.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
                Icons.chevron_right_rounded,
                color: tokens.textMuted,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _goBack(BuildContext context) {
  // Legal pages can belong to the entry Navigator, outside GoRouter's stack.
  // Pop the actual owning navigator before considering a deep-link fallback.
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop();
  } else {
    context.go('/music/settings');
  }
}
