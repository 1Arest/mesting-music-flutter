import 'package:flutter/material.dart';
import 'release_151_qa.dart' as prior;
export 'release_151_qa.dart' show initialize151QA, capture151Builder, shot151;

/// Chip/segment text inherits primaryTextTheme separately from textTheme.
/// Keep the host-only CJK substitute in every themed label; no font enters APK.
ThemeData theme152(bool dark) {
  final value = prior.theme151(dark);
  if (!prior.capture151) return value;
  return value.copyWith(
    primaryTextTheme: value.primaryTextTheme.apply(fontFamily: 'MestingQA151'),
    chipTheme: value.chipTheme.copyWith(
      labelStyle: const TextStyle(fontFamily: 'MestingQA151'),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style:
          value.segmentedButtonTheme.style?.copyWith(
            textStyle: const WidgetStatePropertyAll(
              TextStyle(fontFamily: 'MestingQA151'),
            ),
          ) ??
          const ButtonStyle(
            textStyle: WidgetStatePropertyAll(
              TextStyle(fontFamily: 'MestingQA151'),
            ),
          ),
    ),
  );
}
