import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Java/MySQL test channel is isolated from stable and beta feeds', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final testLabel = File(
      'android/app/src/javaMysqlTest/res/values/app_name.xml',
    ).readAsStringSync();
    final builder = File(
      'tool/build_android_java_mysql_test_apk.ps1',
    ).readAsStringSync();
    final publisher = File(
      'tool/publish_android_java_mysql_test_update.ps1',
    ).readAsStringSync();
    final settings = File(
      'lib/features/settings/presentation/settings_page.dart',
    ).readAsStringSync();
    final externalInstaller = File(
      'android/app/src/main/kotlin/com/mesting/mesting_music/MainActivity.kt',
    ).readAsStringSync();

    expect(gradle, contains('create("javaMysqlTest")'));
    expect(gradle, contains('applicationIdSuffix = ".javatest"'));
    expect(manifest, contains('android:label="@string/app_name"'));
    expect(manifest, isNot(contains('android:label="Mesting 音乐"')));
    expect(testLabel, contains('Mesting 音乐 Java + MySQL 测试版'));
    expect(builder, contains("--flavor 'javaMysqlTest'"));
    expect(builder, contains('--debug'));
    expect(builder, contains(r'APP_UPDATE_PACKAGE_NAME=$packageName'));
    expect(builder, contains('releases/android/java-mysql-test/latest.json'));
    expect(publisher, contains("'releases/android/java-mysql-test'"));
    expect(publisher, contains("packageName = 'com.mesting.music.javatest'"));
    expect(publisher, contains('JAVA_MYSQL_TEST_ONLY'));
    expect(publisher, isNot(contains("'releases/android'\n")));
    expect(settings, contains('settings-java-mysql-test-channel'));
    expect(settings, contains('Java + MySQL 测试版'));
    expect(externalInstaller, contains('installExternalApk'));
    expect(externalInstaller, contains('JAVA_MYSQL_TEST_PACKAGE'));
  });

  test('Java/MySQL test-channel documentation exposes blocking risks', () {
    final documentation = File(
      'docs/java-mysql-test-channel.md',
    ).readAsStringSync();

    expect(documentation, contains('HTTP 不安全'));
    expect(documentation, contains('旧账户密码不能直接迁移'));
    expect(documentation, contains('头像跨设备尚未完成验证'));
    expect(documentation, contains('自动异机灾备'));
    expect(documentation, contains('releases/android/latest.json'));
    expect(documentation, contains('releases/android/java-mysql-test/latest.json'));
  });
}
