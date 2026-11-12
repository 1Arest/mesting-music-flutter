import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/diagnostics/diagnostic_run.dart';

/// Host widgets use a real temporary store without asking an Android plugin for
/// its application directory. Production still owns the path_provider boundary.
DiagnosticRunController diagnosticFixture() {
  final directory = Directory.systemTemp.createTempSync('mesting-diagnostics-');
  final controller = DiagnosticRunController(DiagnosticRunStore(directory));
  addTearDown(() async {
    controller.dispose();
    await directory.delete(recursive: true);
  });
  return controller;
}
