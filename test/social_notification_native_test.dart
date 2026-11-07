import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Android social notifications use a dedicated high-priority channel',
    () {
      final source = File(
        'android/app/src/main/kotlin/com/mesting/mesting_music/MainActivity.kt',
      ).readAsStringSync();
      final icon = File(
        'android/app/src/main/res/drawable/ic_stat_social_notification.xml',
      ).readAsStringSync();

      expect(source, contains('"showSocialNotification"'));
      expect(source, contains('SOCIAL_NOTIFICATION_CHANNEL'));
      expect(source, contains('NotificationCompat.CATEGORY_MESSAGE'));
      expect(source, contains('NotificationManager.IMPORTANCE_HIGH'));
      expect(source, contains('R.drawable.ic_stat_social_notification'));
      expect(icon, contains('android:fillColor="#FFFFFFFF"'));
    },
  );
}
