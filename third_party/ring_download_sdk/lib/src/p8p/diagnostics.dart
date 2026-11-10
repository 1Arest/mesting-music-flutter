/// Closed local vocabulary. No exception text or wire identity leaves an owner.
enum P8PDiagnosticCode {
  checksumMismatch('piece_checksum_mismatch'),
  lengthMismatch('piece_length_mismatch'),
  invalidFrame('invalid_piece_frame'),
  invalidSize('invalid_piece_size'),
  identityMismatch('piece_identity_mismatch'),
  protocolError('protocol_error'),
  sourceTimeout('source_timeout'),
  sourceBusy('source_busy'),
  sourceFailed('source_failed'),
  requestCancelled('request_cancelled'),
  requestDeadlineExceeded('request_deadline_exceeded'),
  stopGraceExceeded('stop_grace_exceeded'),
  cleanupFailed('source_cleanup_failed'),
  sourceCompleted('source_completed'),
  sourceStopped('source_stopped'),
  prefixRescued('prefix_rescued');

  const P8PDiagnosticCode(this.code);
  final String code;
}

class P8PSourceDiagnostic {
  P8PSourceDiagnostic(
    this.reason, {
    String? alias,
    int? actualBytes,
    int? expectedBytes,
  }) : alias =
           const {
             'peer1',
             'peer2',
             'peer3',
             'peer4',
             'seed',
             'https',
           }.contains(alias)
           ? alias
           : null,
       actualBytes = actualBytes?.clamp(0, 1024 * 1024),
       expectedBytes = expectedBytes?.clamp(0, 1024 * 1024);

  final P8PDiagnosticCode reason;
  final String? alias;
  final int? actualBytes, expectedBytes;
}

typedef P8PDiagnosticObserver = void Function(P8PSourceDiagnostic event);

void observeP8P(P8PDiagnosticObserver? observer, P8PSourceDiagnostic event) {
  try {
    observer?.call(event);
  } catch (_) {
    // Optional observation cannot interrupt transfer or physical retirement.
  }
}
