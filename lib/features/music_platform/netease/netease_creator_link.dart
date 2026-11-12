import 'package:flutter/services.dart';

/// Opens only NetEase's known creator page for the selected catalogue song.
Future<bool> openNeteaseCreatorPage(String songId) async {
  if (int.tryParse(songId) == null) return false;
  const channel = MethodChannel('com.mesting.music/netease_creator');
  try {
    return await channel.invokeMethod<bool>('open', {'songId': songId}) ??
        false;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}
