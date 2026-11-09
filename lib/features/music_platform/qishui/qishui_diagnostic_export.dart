import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'qishui_diagnostics.dart';

/// Writes only a generated, credential-free report to the one private path
/// accepted by Android. Directory and share dependencies are injectable so
/// host verification does not open an OS chooser or inspect account storage.
class QishuiDiagnosticExport {
  QishuiDiagnosticExport({
    Future<Directory> Function()? supportDirectory,
    Future<void> Function(String path)? shareFile,
  }) : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       _shareFile = shareFile ?? _nativeShare;

  static const maximumFileBytes = 1024 * 1024;
  static const fileName = 'mesting-qishui-report.json';
  static const _channel = MethodChannel('com.mesting.music/share');
  final Future<Directory> Function() _supportDirectory;
  final Future<void> Function(String path) _shareFile;

  Future<void> share({
    required QishuiDiagnostics diagnostics,
    QishuiDiagnosticGroup group = QishuiDiagnosticGroup.all,
  }) async {
    // Freeze before the first await. Exporting cannot trigger a network call
    // and new observations cannot change the file while it is being written.
    final bytes = utf8.encode(diagnostics.export(group: group));
    if (bytes.length > maximumFileBytes) {
      throw const FormatException('Qishui diagnostic report exceeds bound');
    }
    final support = await _supportDirectory();
    final directory = Directory('${support.path}/qishui_diagnostics');
    await directory.create(recursive: true);
    final temporary = File('${directory.path}/report.next.json');
    final report = File('${directory.path}/$fileName');
    await temporary.writeAsBytes(bytes, flush: true);
    // This generated report is replaceable; it contains no replayable event
    // body or account state. Keep arbitrary paths out of the bridge contract.
    if (await report.exists()) await report.delete();
    await temporary.rename(report.path);
    await _shareFile(report.path);
  }

  static Future<void> _nativeShare(String path) =>
      _channel.invokeMethod<void>('shareQishuiDiagnosticJson', {'path': path});
}
