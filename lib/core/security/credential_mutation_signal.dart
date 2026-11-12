/// Optional runtime observer. Storage has no dependency on notifications or UI;
/// consumers may invalidate asynchronous work before encrypted bytes change.
abstract final class CredentialMutationSignal {
  static Future<void> Function(String key)? beforeMutation;

  static Future<void> emit(String key) async {
    await beforeMutation?.call(key);
  }
}
