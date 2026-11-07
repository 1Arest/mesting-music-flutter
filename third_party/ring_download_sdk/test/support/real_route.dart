import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'loopback_payload.dart';

/// Real Flask admission/Range/session handling in a separate, isolated process.
/// The payload adapter maps logical HTTPS to this loopback HTTP listener.
class RealRouteServer extends LoopbackPayload {
  RealRouteServer._(
    super.bytes,
    this.process,
    this.output,
    this.info,
    this.errorsSubscription,
    this.stderrBuffer,
  );
  final Process process;
  final StreamIterator<String> output;
  final Map<String, dynamic> info;
  final StreamSubscription<String> errorsSubscription;
  final StringBuffer stderrBuffer;

  static Future<RealRouteServer> launch(
    String python,
    String script,
    double delay,
  ) async {
    final process = await Process.start(python, [
      '-X',
      'utf8',
      script,
      '$delay',
    ]);
    final stderrBuffer = StringBuffer();
    final errorsSubscription = process.stderr
        .transform(utf8.decoder)
        .listen(stderrBuffer.write);
    final output = StreamIterator(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    try {
      final available = await output.moveNext().timeout(
        const Duration(seconds: 30),
      );
      if (!available) throw StateError('Route fixture failed: $stderrBuffer');
      final info = jsonDecode(output.current) as Map<String, dynamic>;
      if (info['type'] != 'ready') throw StateError('Unexpected fixture reply');
      final bytes = await File(info['payload_path'] as String).readAsBytes();
      expect(sha256.convert(bytes).toString(), info['sha256']);
      return RealRouteServer._(
        bytes,
        process,
        output,
        info,
        errorsSubscription,
        stderrBuffer,
      );
    } catch (_) {
      await process.stdin.close();
      try {
        await process.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        process.kill();
        await process.exitCode;
      }
      await output.cancel();
      await errorsSubscription.cancel();
      rethrow;
    }
  }

  @override
  Uri get uri =>
      Uri.parse('http://127.0.0.1:${info['port']}/lifering/download');

  Future<Map<String, dynamic>> stats() async {
    process.stdin.writeln('{"type":"stats"}');
    final available = await output.moveNext().timeout(
      const Duration(seconds: 5),
    );
    if (!available) throw StateError('Route fixture exited: $stderrBuffer');
    final reply = jsonDecode(output.current) as Map<String, dynamic>;
    if (reply['type'] != 'stats') throw StateError('Unexpected stats reply');
    return reply;
  }

  @override
  Future<void> waitIdle() async {
    final deadline = Stopwatch()..start();
    while (deadline.elapsed < const Duration(seconds: 5)) {
      final state = await stats();
      if (state['active_handlers'] == 0 && state['active_rows'] == 0) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    throw StateError('Real HTTP response ownership did not finish');
  }

  @override
  Future<void> close() async {
    process.stdin.writeln('{"type":"close"}');
    await process.stdin.close();
    final code = await process.exitCode.timeout(const Duration(seconds: 10));
    await output.cancel();
    await errorsSubscription.cancel();
    expect(code, 0, reason: stderrBuffer.toString());
  }
}
