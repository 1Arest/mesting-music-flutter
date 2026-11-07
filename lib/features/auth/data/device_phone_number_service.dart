import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DataSimPhoneNumber {
  const DataSimPhoneNumber({
    required this.phoneNumber,
    required this.maskedPhoneNumber,
    required this.simSlot,
    required this.unavailableReason,
  });

  final String phoneNumber;
  final String maskedPhoneNumber;
  final int simSlot;
  final String unavailableReason;

  bool get available =>
      RegExp(r'^1\d{10}$').hasMatch(phoneNumber) &&
      maskedPhoneNumber.isNotEmpty;
}

class DevicePhoneNumberService {
  const DevicePhoneNumberService();

  static const _channel = MethodChannel('com.mesting.music/device_identity');

  Future<DataSimPhoneNumber> getDataSimPhoneNumber() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const DataSimPhoneNumber(
        phoneNumber: '',
        maskedPhoneNumber: '',
        simSlot: 0,
        unavailableReason: 'unsupported_platform',
      );
    }
    try {
      final payload = await _channel.invokeMapMethod<String, Object?>(
        'getDataSimPhoneNumber',
      );
      return DataSimPhoneNumber(
        phoneNumber: payload?['phoneNumber'] as String? ?? '',
        maskedPhoneNumber: payload?['maskedPhoneNumber'] as String? ?? '',
        simSlot: payload?['simSlot'] as int? ?? 0,
        unavailableReason: payload?['unavailableReason'] as String? ?? '',
      );
    } on PlatformException catch (error) {
      return DataSimPhoneNumber(
        phoneNumber: '',
        maskedPhoneNumber: '',
        simSlot: 0,
        unavailableReason: error.code,
      );
    } on MissingPluginException {
      return const DataSimPhoneNumber(
        phoneNumber: '',
        maskedPhoneNumber: '',
        simSlot: 0,
        unavailableReason: 'plugin_unavailable',
      );
    }
  }
}
