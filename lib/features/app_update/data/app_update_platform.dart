import 'package:flutter/services.dart';

import '../domain/app_update_models.dart';

class AppUpdatePlatform {
  AppUpdatePlatform({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'com.mesting.music/app_update';
  final MethodChannel _channel;

  Future<AppVersionInfo> currentVersion() async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'getAppInfo',
    );
    final packageName = result?['packageName'];
    final versionName = result?['versionName'];
    final versionCode = result?['versionCode'];
    if (packageName is! String ||
        packageName.isEmpty ||
        versionName is! String ||
        versionName.isEmpty ||
        versionCode is! int ||
        versionCode <= 0) {
      throw const AppUpdateException('无法读取当前应用版本', code: 'app_info');
    }
    return AppVersionInfo(
      packageName: packageName,
      versionName: versionName,
      versionCode: versionCode,
    );
  }

  Future<bool> canRequestPackageInstalls() async {
    return await _channel.invokeMethod<bool>('canRequestPackageInstalls') ??
        false;
  }

  Future<void> openInstallPermission() {
    return _channel.invokeMethod<void>('openInstallPermission');
  }

  Future<void> installApk(String path) {
    return _channel.invokeMethod<void>('installApk', {'path': path});
  }
}
