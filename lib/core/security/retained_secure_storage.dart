import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Both accounts share Android's encrypted preferences and cipher cache. The
/// plugin's resetOnError default calls deleteAll on storage exceptions. Keep
/// existing namespaces/ciphers, but propagate failures without erasing keys.
const retainedSecureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(resetOnError: false),
);
