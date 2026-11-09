/// Closed diagnostic values for reward workflows. This file deliberately has
/// no Flutter, HTTP or account dependencies so parsers can describe a failure
/// without retaining the URL, query values or a platform response object.
enum MusicRewardStep {
  entry,
  balance,
  progress,
  qualification,
  claim,
  signState,
  signIn,
}

enum MusicRewardReason {
  accepted,
  entryMissing,
  entryWrongType,
  entryTooLong,
  entryMalformedUri,
  entryUnsupportedRoute,
  entryDuplicateField,
  entryMissingField,
  entryInvalidPosition,
  entryInvalidExt,
  entryInvalidEncoding,
  qualificationNotRequested,
  qualificationDenied,
  sourceUnavailable,
  businessRejected,
  receiptIncomplete,
  gainDenied,
  httpFailure,
  transportFailure,
}

enum MusicRewardEntryRoute { officialNm, officialNe, legacyHost, unsupported }

enum MusicRewardValueType {
  missing,
  text,
  number,
  boolean,
  list,
  object,
  other,
}

/// The transport currently keeps its established Android-style User-Agent.
/// These categories describe only the effective os cookie at dispatch time;
/// they never claim that it is a complete official Android identity.
enum MusicRewardIdentity {
  defaultPc,
  sessionPc,
  sessionAndroid,
  sessionOsx,
  sessionOther,
}

final class MusicRewardDiagnostic {
  const MusicRewardDiagnostic({
    required this.step,
    required this.reason,
    this.route,
    this.valueType,
    this.hasAdPosition,
    this.hasResourceId,
    this.hasSource,
    this.hasExt,
    this.qualificationRequested,
    this.identity,
  });

  final MusicRewardStep step;
  final MusicRewardReason reason;
  final MusicRewardEntryRoute? route;
  final MusicRewardValueType? valueType;
  final bool? hasAdPosition, hasResourceId, hasSource, hasExt;
  final bool? qualificationRequested;
  final MusicRewardIdentity? identity;

  MusicRewardDiagnostic withContext({
    MusicRewardReason? reason,
    MusicRewardIdentity? identity,
  }) => MusicRewardDiagnostic(
    step: step,
    reason: reason ?? this.reason,
    route: route,
    valueType: valueType,
    hasAdPosition: hasAdPosition,
    hasResourceId: hasResourceId,
    hasSource: hasSource,
    hasExt: hasExt,
    qualificationRequested: qualificationRequested,
    identity: identity ?? this.identity,
  );

  /// Only enums and presence bits can reach the shared JSON export. Keeping
  /// this projection here prevents future callers from forwarding raw fields.
  Map<String, Object> toMap() => {
    'rewardStep': step.name,
    'rewardReason': reason.name,
    if (route != null) 'entryRoute': route!.name,
    if (valueType != null) 'entryValueType': valueType!.name,
    'entryHasAdPosition': ?hasAdPosition,
    'entryHasResourceId': ?hasResourceId,
    'entryHasSource': ?hasSource,
    'entryHasExt': ?hasExt,
    'qualificationRequested': ?qualificationRequested,
    if (identity != null) 'rewardIdentity': identity!.name,
  };
}
