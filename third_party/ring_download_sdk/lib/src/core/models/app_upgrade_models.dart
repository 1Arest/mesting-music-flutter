class AppUpgradeInfo {
  AppUpgradeInfo({
    required this.releaseId,
    required this.versionName,
    required this.versionCode,
    required this.releaseNotes,
    required this.forceUpdate,
    required this.downloadUrl,
    required this.fileSize,
    required this.sha256,
    this.downloadProtocol = '',
    this.downloadSlug = '',
    this.downloadBackupUrl = '',
    this.downloadEtag = '',
    this.downloadVersionCode,
    this.requiresEligibilityCheck = false,
    this.audienceUserId,
  });

  factory AppUpgradeInfo.fromJson(
    Map<String, dynamic> json, {
    String? audienceUserId,
  }) {
    return AppUpgradeInfo(
      releaseId: (json['releaseId'] ?? '').toString(),
      versionName: (json['versionName'] ?? '').toString(),
      versionCode: (json['versionCode'] as num?)?.toInt() ?? 0,
      releaseNotes: (json['releaseNotes'] ?? '').toString(),
      forceUpdate: json['forceUpdate'] == true,
      downloadUrl: (json['downloadUrl'] ?? '').toString(),
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      sha256: (json['sha256'] ?? '').toString(),
      downloadProtocol: (json['downloadProtocol'] ?? '').toString(),
      downloadSlug: (json['downloadSlug'] ?? '').toString(),
      downloadBackupUrl: (json['downloadBackupUrl'] ?? '').toString(),
      downloadEtag: (json['downloadEtag'] ?? '').toString(),
      downloadVersionCode: json['downloadVersionCode'] is int
          ? json['downloadVersionCode'] as int
          : null,
      requiresEligibilityCheck: json['requiresEligibilityCheck'] == true,
      audienceUserId: audienceUserId,
    );
  }

  final String releaseId;
  final String versionName;
  final int versionCode;
  final String releaseNotes;
  final bool forceUpdate;
  final String downloadUrl;
  final int fileSize;
  final String sha256;
  final String downloadProtocol;
  final String downloadSlug;
  final String downloadBackupUrl;
  final String downloadEtag;

  /// Actual Android APK build from health, never inferred from the business
  /// release's versionCode (which controls update eligibility and ordering).
  /// Null means an older download service did not publish a build identity.
  final int? downloadVersionCode;
  final bool requiresEligibilityCheck;
  final String? audienceUserId;
}
