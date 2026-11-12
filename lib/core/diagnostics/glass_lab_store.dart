import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'glass_lab_run.dart';

/// A separate fixed file preserves the existing real-page diagnostic reports.
class GlassLabReportStore implements GlassLabReportSink {
  GlassLabReportStore({Future<Directory> Function()? root})
    : _root = root ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _root;
  static const maximumBytes = 16 * 1024 * 1024;

  Future<File> reportFile() async {
    final root = await _root();
    return File(
      '${root.path}/glass_lab_diagnostics/mesting-glass-lab-report.json',
    );
  }

  @override
  Future<void> save(Map<String, Object?> report) async {
    final data = utf8.encode(jsonEncode(report));
    if (data.isEmpty || data.length > maximumBytes) {
      throw StateError('report_size');
    }
    final file = await reportFile();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.next');
    await temporary.writeAsBytes(data, flush: true);
    // Android/POSIX rename replaces atomically. Windows needs explicit removal
    // for host validation; the previous completed export remains on failure.
    final previous = File('${file.path}.previous');
    if (await previous.exists()) await previous.delete();
    if (await file.exists()) await file.rename(previous.path);
    try {
      await temporary.rename(file.path);
    } on Object {
      if (await previous.exists() && !await file.exists()) {
        await previous.rename(file.path);
      }
      rethrow;
    }
  }
}
