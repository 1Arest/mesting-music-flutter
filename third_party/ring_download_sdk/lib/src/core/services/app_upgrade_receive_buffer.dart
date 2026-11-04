/// Optional local-only capability. No service, signal or public SDK contract.
abstract interface class AppUpgradeReceiveBufferOwner {
  void addCandidate(String? candidate);
  Future<void> close();
}

typedef AppUpgradeReceiveBufferFactory =
    AppUpgradeReceiveBufferOwner Function();
