import 'dart:async';

import 'package:flutter/services.dart';

enum MusicDiagnosticCopyResult { verified, mismatch, unavailable }

/// The copied snapshot is immutable throughout set/readback. A failed readback
/// must never be presented as verified success, and it never auto-recopies.
class MusicDiagnosticClipboard {
  static Future<MusicDiagnosticCopyResult> copy(String snapshot) async {
    const bound = Duration(seconds: 3);
    try {
      await Clipboard.setData(ClipboardData(text: snapshot)).timeout(bound);
      final result = await Clipboard.getData(
        Clipboard.kTextPlain,
      ).timeout(bound);
      if (result?.text == null) return MusicDiagnosticCopyResult.unavailable;
      return result!.text == snapshot
          ? MusicDiagnosticCopyResult.verified
          : MusicDiagnosticCopyResult.mismatch;
    } on Object {
      return MusicDiagnosticCopyResult.unavailable;
    }
  }
}
