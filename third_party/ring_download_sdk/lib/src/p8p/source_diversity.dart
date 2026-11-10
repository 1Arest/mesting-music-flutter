import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Optional request for the coordinator's node-side source-port experiment.
/// This creates no sockets and grants no authority. The coordinator supplies
/// the actual attempt identity and authenticated peer/release context.
class P8PSourceDiversity {
  static const strategy = 'source_port_diversity_v1';

  static Map<String, Object>? offer(Object? capability, String sdp) {
    if (capability is! Map ||
        capability['version'] is! int ||
        capability['version'] != 1 ||
        capability['strategy'] != strategy) {
      return null;
    }
    final count = capability['max_sockets'];
    if (count is! int || count < 2 || count > 4) return null;
    final generation = iceGeneration(sdp);
    if (generation == null) return null;
    return {
      'version': 1,
      'strategy': strategy,
      'max_sockets': count,
      'ice_generation': generation,
    };
  }

  /// Same data-only ICE credential digest as the server's opt-in validator.
  /// Unsupported or malformed native SDP retains the existing connection path.
  static String? iceGeneration(String sdp) {
    if (sdp.length > 65536 || utf8.encode(sdp).length > 65536) return null;
    final session = <String, String>{};
    final media = <Map<String, String>>[];
    var scope = session;
    for (final line in const LineSplitter().convert(sdp)) {
      if (line.startsWith('m=')) {
        final fields = line.substring(2).trim().split(RegExp(r'\s+'));
        if (fields.first.isEmpty) return null;
        scope = {'kind': fields.first};
        media.add(scope);
      }
      for (final name in ['ice-ufrag', 'ice-pwd']) {
        final prefix = 'a=$name:';
        if (!line.startsWith(prefix)) continue;
        final value = line.substring(prefix.length);
        if (scope.containsKey(name) && scope[name] != value) return null;
        scope[name] = value;
      }
    }
    if (media.length != 1 || media.single['kind'] != 'application') return null;
    final values = <String>[];
    for (final entry in {'ice-ufrag': 4, 'ice-pwd': 22}.entries) {
      final value = media.single[entry.key] ?? session[entry.key];
      if (value == null) return null;
      final match = RegExp(
        '[A-Za-z0-9+/]{${entry.value},256}',
      ).matchAsPrefix(value);
      if (match == null || match.end != value.length) return null;
      values.add(value);
    }
    return sha256.convert(utf8.encode(values.join('\u0000'))).toString();
  }
}
