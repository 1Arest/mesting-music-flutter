import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'netease_ad_probe_report.dart';

/// Export accepts the closed report type, never a raw string/map from upstream.
/// The native bridge permits only this fixed private file and a bounded size.
class NeteaseAdProbeExport {
  NeteaseAdProbeExport({
    Future<Directory> Function()? supportDirectory,
    Future<void> Function(String path)? shareFile,
  }) : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       _shareFile = shareFile ?? _nativeShare;

  static const fileName = 'mesting-netease-ad-report.json';
  final Future<Directory> Function() _supportDirectory;
  final Future<void> Function(String path) _shareFile;

  Future<void> share(
    NeteaseAdProbeReport report, {
    bool Function()? isCurrent,
  }) async {
    void check() {
      if (isCurrent?.call() == false) {
        throw StateError('Report no longer current');
      }
    }

    check();
    final bytes = utf8.encode(report.json);
    if (bytes.length > 65536) throw const FormatException('Report too large');
    final support = await _supportDirectory();
    check();
    final directory = Directory('${support.path}/netease_ad_diagnostics');
    await directory.create(recursive: true);
    final next = File('${directory.path}/report.next.json');
    final target = File('${directory.path}/$fileName');
    await next.writeAsBytes(bytes, flush: true);
    if (await target.exists()) await target.delete();
    await next.rename(target.path);
    check();
    await _shareFile(target.path);
  }

  static Future<void> _nativeShare(String path) => const MethodChannel(
    'com.mesting.music/share',
  ).invokeMethod<void>('shareNeteaseAdDiagnosticJson', {'path': path});
}
