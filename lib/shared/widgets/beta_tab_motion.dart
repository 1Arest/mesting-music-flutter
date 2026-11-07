/// Pure, bounded geometry for retained root navigation.
///
/// A distant shortcut travels one viewport, never through unrelated branches.
/// Retargeting uses the current two positions, so reversing an unfinished slide
/// does not snap either existing surface back to its original edge.
class BetaTabMotion {
  BetaTabMotion(this.target) : _from = {target: 0}, _to = {target: 0};

  int target;
  Map<int, double> _from, _to;

  Map<int, double> positions(double progress) => {
    for (final entry in _from.entries)
      entry.key: entry.value + (_to[entry.key]! - entry.value) * progress,
  };

  void retarget(int next, double progress) {
    if (next == target) return;
    final current = positions(progress).entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final rightward = next > target;
    final existing = current.where((entry) => entry.key == next).firstOrNull;
    final outgoing = existing == null
        ? (rightward ? current.first : current.last)
        : current.firstWhere((entry) => entry.key != next);
    final incomingStart =
        existing?.value ?? outgoing.value + (rightward ? 1.0 : -1.0);
    _from = {outgoing.key: outgoing.value, next: incomingStart};
    _to = {outgoing.key: incomingStart >= outgoing.value ? -1 : 1, next: 0};
    target = next;
  }

  void settle() {
    _from = {target: 0};
    _to = {target: 0};
  }
}
