import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A process-local safety latch, deliberately separate from persisted progress.
/// Reading a crash checkpoint must never suppress normal product behaviour.
final diagnosticRunActive = ValueNotifier<bool>(false);

final diagnosticActivityProvider = NotifierProvider<DiagnosticActivity, bool>(
  DiagnosticActivity.new,
);

class DiagnosticActivity extends Notifier<bool> {
  @override
  bool build() => false;

  void setRunning(bool running) {
    diagnosticRunActive.value = running;
    // Timing drains may finish after the hosting ProviderScope has exited.
    // Release the process latch without updating an already retired provider.
    if (ref.mounted) state = running;
  }
}
