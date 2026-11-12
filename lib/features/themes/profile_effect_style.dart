import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/persistence/app_preferences.dart';

enum ProfileEffectStyle {
  petals('花瓣流光', '保留金色光束与花瓣飘落'),
  rhythm('音律光环', '光环随音乐起伏，重拍带出飘落音符'),
  orbit('星轨流光', '紫蓝星屑沿光轨缓缓飘落'),
  fireflies('萤火光尘', '暖色萤光绕头像缓缓飘落'),
  none('关闭特效', '仅保留头像与个人资料');

  const ProfileEffectStyle(this.label, this.description);
  final String label, description;
}

class ProfileEffectController extends Notifier<ProfileEffectStyle> {
  @override
  ProfileEffectStyle build() => ProfileEffectStyle.values.firstWhere(
    (s) =>
        s.name ==
        ref.watch(sharedPreferencesProvider).getString('profile_effect_193'),
    orElse: () => ProfileEffectStyle.petals,
  );
  Future<void> select(ProfileEffectStyle value) async {
    if (!await ref
        .read(sharedPreferencesProvider)
        .setString('profile_effect_193', value.name)) {
      throw StateError('save failed');
    }
    state = value;
  }
}

final profileEffectProvider =
    NotifierProvider<ProfileEffectController, ProfileEffectStyle>(
      ProfileEffectController.new,
    );
