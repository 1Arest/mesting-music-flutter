import 'package:flutter/material.dart';

/// Mesting Music 的应用级功能色。
///
/// 颜色按用途命名，页面不再把同一枚玫瑰色同时当作品牌、收藏、错误和
/// 装饰色使用。主题皮肤仍可生成自己的 [ColorScheme]，但通用功能状态应
/// 优先从这里或当前 [ColorScheme] 取色。
abstract final class MestingPalette {
  // Brand / focus
  static const primary = Color(0xFF465CC7);
  static const primaryStrong = Color(0xFF31439E);
  static const primaryBright = Color(0xFF91A5FF);
  static const primarySoft = Color(0xFFE9EDFF);

  // Supporting accents
  static const azure = Color(0xFF4A86D8);
  static const cyan = Color(0xFF3F9FB0);
  static const teal = Color(0xFF2E9B82);
  static const amber = Color(0xFFD18B22);
  static const violet = Color(0xFF745CC7);

  // Semantic roles
  static const heart = Color(0xFFCC3F56);
  static const heartBright = Color(0xFFFF7C8A);
  static const heartSoft = Color(0xFFFFE9ED);
  static const favorite = heart;
  static const positive = Color(0xFF218A70);
  static const warning = Color(0xFFB87512);
  static const danger = Color(0xFFC24A34);
  static const dangerBright = Color(0xFFE06B4E);
  static const dangerSoft = Color(0xFFFFECE6);

  // Neutral canvas
  static const lightSurface = Color(0xFFFCFCFD);
  static const darkSurface = Color(0xFF11141B);
  static const darkInk = Color(0xFF10131D);
}
