import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/music_http_client.dart';
import 'qishui_request_signer.dart';
import 'qishui_signer_settings.dart';

typedef QishuiSignerProbe =
    Future<void> Function(QishuiSignerConfig config, Future<void> abort);

/// A test has its own transport lifetime. Closing the settings page aborts it
/// without disposing the shared, authenticated official API client.
final qishuiSignerProbeProvider = Provider<QishuiSignerProbe>(
  (ref) => (config, abort) async {
    final client = MusicHttpClient();
    try {
      await testQishuiSignerConnection(client, config, abort);
    } finally {
      client.close();
    }
  },
);
