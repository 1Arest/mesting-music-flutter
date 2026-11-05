/// Native operations and individual transfers have separate deadlines.
/// Complete SDP and Trickle share the manifest startup budget through the
/// first verified piece. These limits may shorten, but never extend, that budget.
class AppUpgradeP2PTimeouts {
  const AppUpgradeP2PTimeouts({
    this.rtcOperation = const Duration(seconds: 3),
    this.iceGathering = const Duration(seconds: 15),
    this.answer = const Duration(seconds: 25),
    this.channel = const Duration(seconds: 10),
    this.transfer = const Duration(seconds: 8),
  });

  final Duration rtcOperation;
  final Duration iceGathering;
  // A provider must finish its own ICE gather and send its answer. The answer
  // budget therefore includes gathering, HTTP signaling and polling latency.
  final Duration answer;
  final Duration channel;
  final Duration transfer;
}
