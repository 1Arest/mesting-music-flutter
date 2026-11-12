import 'package:flutter/material.dart';

/// Shared iOS-inspired type scale for application text. System text scaling
/// remains responsible for the user's accessibility size preference.
abstract final class MusicTypography {
  static const titleWeight = FontWeight.w500;
  static const bodyWeight = FontWeight.w400;

  // Weight-only styles inherit native dialog sizes, colors and line heights.
  static const titleEmphasis = TextStyle(fontWeight: titleWeight);
  static const regularText = TextStyle(fontWeight: bodyWeight);

  static const double largeTitleSize = 34;
  static const double titleSize = 28;
  static const double sectionTitleSize = 22;
  static const double headingSize = 20;
  static const double bodySize = 17;
  static const double calloutSize = 16;
  static const double subheadlineSize = 15;
  static const double footnoteSize = 13;
  static const double captionSize = 12;
  static const double smallCaptionSize = 11;

  static const largeTitle = TextStyle(
    fontSize: largeTitleSize,
    fontWeight: titleWeight,
    height: 41 / 34,
  );
  static const title = TextStyle(
    fontSize: titleSize,
    fontWeight: titleWeight,
    height: 34 / 28,
  );
  static const sectionTitle = TextStyle(
    fontSize: sectionTitleSize,
    fontWeight: titleWeight,
    height: 28 / 22,
  );
  static const heading = TextStyle(
    fontSize: headingSize,
    fontWeight: titleWeight,
    height: 25 / 20,
  );
  static const headline = TextStyle(
    fontSize: bodySize,
    fontWeight: titleWeight,
    height: 22 / 17,
  );
  static const body = TextStyle(
    fontSize: bodySize,
    fontWeight: bodyWeight,
    height: 22 / 17,
  );
  static const callout = TextStyle(
    fontSize: calloutSize,
    fontWeight: bodyWeight,
    height: 21 / 16,
  );
  static const subheadline = TextStyle(
    fontSize: subheadlineSize,
    fontWeight: bodyWeight,
    height: 20 / 15,
  );
  static const footnote = TextStyle(
    fontSize: footnoteSize,
    fontWeight: bodyWeight,
    height: 18 / 13,
  );
  static const caption = TextStyle(
    fontSize: captionSize,
    fontWeight: bodyWeight,
    height: 16 / 12,
  );
  static const smallCaption = TextStyle(
    fontSize: smallCaptionSize,
    fontWeight: bodyWeight,
    height: 13 / 11,
  );

  static TextTheme textTheme({
    required Color primary,
    required Color secondary,
  }) {
    return TextTheme(
      displayLarge: largeTitle.copyWith(color: primary),
      displayMedium: largeTitle.copyWith(color: primary),
      displaySmall: title.copyWith(color: primary),
      headlineLarge: title.copyWith(color: primary),
      headlineMedium: sectionTitle.copyWith(color: primary),
      headlineSmall: heading.copyWith(color: primary),
      titleLarge: heading.copyWith(color: primary),
      titleMedium: headline.copyWith(color: primary),
      titleSmall: subheadline.copyWith(color: primary, fontWeight: titleWeight),
      bodyLarge: body.copyWith(color: primary),
      bodyMedium: body.copyWith(color: primary),
      bodySmall: footnote.copyWith(color: secondary),
      labelLarge: body.copyWith(color: primary),
      labelMedium: caption.copyWith(color: secondary),
      labelSmall: smallCaption.copyWith(color: secondary),
    );
  }
}
