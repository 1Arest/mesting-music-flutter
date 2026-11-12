import 'package:shared_preferences/shared_preferences.dart';

/// Confirmed daily progress belongs to one retained Kugou account. It contains
/// no credential or inferred reward; only a successful platform response moves
/// the counter. Persisting the last success also preserves the 30s gap on restart.
class PlatformAdProgress {
  const PlatformAdProgress({
    this.count = 0,
    this.lastSuccessMs = 0,
    this.done = false,
  });
  final int count, lastSuccessMs;
  final bool done;
  static String key(String owner, String day) => 'md3_rewards.ads.$owner.$day';
  static PlatformAdProgress read(
    SharedPreferences prefs,
    String owner,
    String day,
  ) {
    final values = prefs.getStringList(key(owner, day)) ?? const [];
    return PlatformAdProgress(
      count: values.isEmpty ? 0 : (int.tryParse(values[0]) ?? 0).clamp(0, 8),
      lastSuccessMs: values.length < 2 ? 0 : int.tryParse(values[1]) ?? 0,
      done: values.length > 2 && values[2] == 'done',
    );
  }

  Future<bool> save(SharedPreferences prefs, String owner, String day) =>
      prefs.setStringList(key(owner, day), [
        '$count',
        '$lastSuccessMs',
        done ? 'done' : 'pending',
      ]);
}
