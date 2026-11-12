/// NetEase reward facts are independent of presentation and local animations.
/// Nullable values mean that the platform has not supplied that fact; a failed
/// read must never become a zero balance, an unsigned day or a completed ad.
class NeteaseFreeListenSnapshot {
  const NeteaseFreeListenSnapshot({
    this.remainingSeconds,
    this.adCount,
    this.adTarget,
    this.adLimit,
    this.todayFree,
    this.claimInterval,
    this.message,
    this.progressTitle,
    this.progressSubtitle,
    this.milestones = const [],
  });

  final int? remainingSeconds, adCount, adTarget, adLimit;
  final bool? todayFree;
  final Duration? claimInterval;
  final String? message;
  final String? progressTitle, progressSubtitle;
  final List<NeteaseRewardMilestone> milestones;
}

/// Server milestones are displayed verbatim as task labels. A stride, a reward
/// duration and a completed-task count are not interchangeable daily quotas.
class NeteaseRewardMilestone {
  const NeteaseRewardMilestone({required this.label, this.done, this.count});
  final String label;
  final bool? done;
  final int? count;
}

class NeteaseRewardSnapshot {
  const NeteaseRewardSnapshot({
    required this.now,
    this.signedDates = const {},
    this.signedToday,
    this.recordsAvailable = false,
    this.freeListen,
    this.message,
  });

  final DateTime now;
  final Set<String> signedDates;
  final bool? signedToday;
  final bool recordsAvailable;
  final NeteaseFreeListenSnapshot? freeListen;
  final String? message;
}

enum NeteaseRewardAction { signIn, ad }

class NeteaseRewardResult {
  const NeteaseRewardResult({
    required this.success,
    required this.message,
    this.signed = false,
    this.quotaDone = false,
    this.uncertain = false,
    this.needsVerification = false,
    this.nextClaimAfter,
    this.signedDate,
  });

  final bool success, signed, quotaDone, uncertain, needsVerification;
  final String message;
  final Duration? nextClaimAfter;

  /// Exact platform-confirmed day, when a response crosses a day boundary.
  final String? signedDate;
}

/// A service owns one immutable account identity. Implementations must pass the
/// captured credential to every request and never replay an ambiguous write.
abstract interface class NeteaseRewardService {
  String get ownerId;
  Future<NeteaseRewardSnapshot> load();
  Future<NeteaseRewardResult> signIn();
  Future<NeteaseRewardResult> claimAd({bool Function()? stillCurrent});
}
