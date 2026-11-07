import 'dart:io';

import 'package:flutter/material.dart';

import '../profile_background_controller.dart';

class ProfileBackgroundPreset {
  const ProfileBackgroundPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.colors,
    required this.accent,
  });

  final String id;
  final String name;
  final String description;
  final List<Color> colors;
  final Color accent;
}

const profileBackgroundPresets = <ProfileBackgroundPreset>[
  ProfileBackgroundPreset(
    id: 'rose-cloud',
    name: '雾蓝星云',
    description: '钴蓝雾光与远空',
    colors: [Color(0xFF24345C), Color(0xFF6179BE), Color(0xFF9BCAD8)],
    accent: Color(0xFFD9E6FF),
  ),
  ProfileBackgroundPreset(
    id: 'midnight',
    name: '午夜唱片',
    description: '深蓝黑胶与微光',
    colors: [Color(0xFF090C18), Color(0xFF172950), Color(0xFF455A8D)],
    accent: Color(0xFF8CB7FF),
  ),
  ProfileBackgroundPreset(
    id: 'aurora',
    name: '极光律动',
    description: '青绿流光与夜空',
    colors: [Color(0xFF071B25), Color(0xFF0D776D), Color(0xFF66D6B6)],
    accent: Color(0xFF9FFFE3),
  ),
  ProfileBackgroundPreset(
    id: 'sunset',
    name: '日落磁带',
    description: '靛青与琥珀色的晚风',
    colors: [Color(0xFF172949), Color(0xFF5268A8), Color(0xFFE3A05A)],
    accent: Color(0xFFFFD39C),
  ),
];

ProfileBackgroundPreset profileBackgroundPresetById(String? id) {
  return profileBackgroundPresets.firstWhere(
    (preset) => preset.id == id,
    orElse: () => profileBackgroundPresets.first,
  );
}

class ProfileBackgroundVisual extends StatelessWidget {
  const ProfileBackgroundVisual({
    super.key,
    required this.background,
    this.fit = BoxFit.cover,
    this.dim = false,
    this.borderRadius,
  });

  final ProfileBackgroundState background;
  final BoxFit fit;
  final bool dim;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    Widget visual;
    if (background.isImage && background.imagePath != null) {
      visual = Image.file(
        File(background.imagePath!),
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, _, _) => const _DefaultProfileBackground(),
      );
    } else if (background.isPreset) {
      visual = _PresetProfileBackground(
        preset: profileBackgroundPresetById(background.presetId),
      );
    } else {
      visual = const _DefaultProfileBackground();
    }

    visual = Stack(
      fit: StackFit.expand,
      children: [
        visual,
        if (dim)
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x33000000),
                  Color(0x66000000),
                  Color(0xB8000000),
                ],
              ),
            ),
          ),
      ],
    );
    if (borderRadius == null) return visual;
    return ClipRRect(borderRadius: borderRadius!, child: visual);
  }
}

class _DefaultProfileBackground extends StatelessWidget {
  const _DefaultProfileBackground();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF17223A), Color(0xFF11141B)]
              : const [Color(0xFFE1E8F8), Color(0xFFF7F9FD)],
        ),
      ),
    );
  }
}

class _PresetProfileBackground extends StatelessWidget {
  const _PresetProfileBackground({required this.preset});

  final ProfileBackgroundPreset preset;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: preset.colors,
            ),
          ),
        ),
        Positioned(
          right: -54,
          top: -62,
          child: _GlowOrb(color: preset.accent, size: 190),
        ),
        Positioned(
          left: -42,
          bottom: -76,
          child: _GlowOrb(
            color: preset.colors.last.withValues(alpha: .75),
            size: 210,
          ),
        ),
        Align(
          alignment: const Alignment(.42, .16),
          child: Container(
            width: 118,
            height: 118,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: .10),
                width: 18,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: .68), color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}
