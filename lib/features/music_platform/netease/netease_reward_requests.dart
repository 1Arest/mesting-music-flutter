import '../../../core/cache/browse_response_cache.dart';
import '../../../core/network/music_network_diagnostics.dart';
import 'netease_api.dart';
import 'netease_request_exception.dart';
import 'netease_rewards.dart';

/// Fixed stages describe the reward workflow without exposing request URLs,
/// account IDs, entry links or platform response text in logs and notices.
enum NeteaseRewardStage {
  signState('签到状态', MusicNetworkOperation.rewardSignIn),
  balance('免费听余额', MusicNetworkOperation.rewardBalance),
  progress('领取进度', MusicNetworkOperation.rewardProgress),
  qualification('领取资格', MusicNetworkOperation.rewardQualification),
  claim('奖励领取', MusicNetworkOperation.rewardClaim, writes: true),
  signIn('每日签到', MusicNetworkOperation.rewardSignIn, writes: true);

  const NeteaseRewardStage(this.label, this.operation, {this.writes = false});
  final String label;
  final MusicNetworkOperation operation;
  final bool writes;

  static NeteaseRewardStage forPath(String path) => switch (path) {
    '/api/ad/homepage/free/tab/asset' => balance,
    '/api/ad/homepage/free/tab/continuous_rights' => progress,
    '/api/ad/listening/rights/qualification' => qualification,
    '/api/ad/listening/rights/gain' => claim,
    '/api/point/dailyTask' => signIn,
    _ when path.startsWith('/api/v1/user/detail/') => signState,
    _ => throw ArgumentError('Unsupported reward request stage'),
  };
}

/// A stage-labelled transport failure carries only fixed categories and a
/// numeric HTTP status. It cannot accidentally surface a server error body.
class NeteaseRewardRequestFailure implements Exception {
  const NeteaseRewardRequestFailure(this.stage, this.outcome, this.httpStatus);
  final NeteaseRewardStage stage;
  final MusicNetworkOutcome outcome;
  final int? httpStatus;

  NeteaseRewardResult get result {
    final detail = httpStatus != null
        ? 'HTTP $httpStatus'
        : switch (outcome) {
            MusicNetworkOutcome.timeout => '连接超时',
            MusicNetworkOutcome.dns => '地址解析失败',
            MusicNetworkOutcome.tls => '安全连接失败',
            MusicNetworkOutcome.format => '回执格式异常',
            MusicNetworkOutcome.cancelled => '请求已取消',
            _ => '连接未完成',
          };
    return NeteaseRewardResult(
      success: false,
      // A qualification/read failure cannot itself award any listening time.
      // A dispatched write may have applied before its response was lost.
      uncertain: stage.writes,
      message:
          '网易云${stage.label}未完成（$detail）；'
          '${stage.writes ? '结果尚未确认，不会重复提交' : '尚未提交奖励领取，已停止'}',
    );
  }
}

/// Executes one request only. Both HTTP and business outcomes are recorded at
/// the actual reward stage, rather than an HTTP-200 business error appearing
/// merely as a successful generic read in the connection diagnostics.
abstract final class NeteaseRewardRequests {
  static int? code(Map<String, dynamic> value) =>
      int.tryParse('${value['code']}');

  /// A local validation stop is visibly separate from an upstream response.
  /// Only its fixed stage/outcome are exported, never the rejected entry URL.
  static void recordLocalStop(
    NeteaseRewardStage stage, {
    MusicNetworkOutcome outcome = MusicNetworkOutcome.format,
  }) => MusicNetworkDiagnostics.shared.record(
    platform: 'netease',
    operation: stage.operation,
    outcome: outcome,
    phase: MusicDiagnosticPhase.responseValidate,
    transport: 'local',
  );

  /// Only classified login/security refusals clear a write-ahead marker. An
  /// opaque numeric code (including 500) does not prove a write was unapplied.
  static bool definiteRefusal(Map<String, dynamic> value) {
    return const {301, 302, 405, 415, 460}.contains(code(value));
  }

  static NeteaseRewardResult refused(
    NeteaseRewardStage stage,
    Map<String, dynamic> value,
  ) {
    final status = code(value);
    final verification = {405, 415, 460}.contains(status);
    final uncertain = stage.writes && !definiteRefusal(value);
    final message = switch (status) {
      301 || 302 => '网易云${stage.label}失败：登录已失效，请重新登录',
      405 || 415 || 460 => '网易云${stage.label}要求安全验证，本次已停止',
      null => '网易云${stage.label}回执不完整，本次已停止',
      _ => '网易云${stage.label}失败（业务码 $status），本次已停止',
    };
    return NeteaseRewardResult(
      success: false,
      needsVerification: verification,
      uncertain: uncertain,
      message: uncertain ? '$message；结果尚未确认，不会重复提交' : message,
    );
  }

  static Future<Map<String, dynamic>> send({
    required NeteaseApi api,
    required String? credential,
    required String path,
    Map<String, Object?> data = const {},
  }) async {
    final stage = NeteaseRewardStage.forPath(path);
    final watch = Stopwatch()..start();
    try {
      final result = await BrowseResponseCache.live(
        () => api.request(
          path,
          data,
          expectedCredential: credential,
          allowBusinessError: true,
        ),
      );
      final status = code(result);
      var accepted =
          status == 200 || stage == NeteaseRewardStage.signIn && status == -2;
      var outcome = accepted
          ? MusicNetworkOutcome.success
          : status == null
          ? MusicNetworkOutcome.format
          : MusicNetworkOutcome.business;
      if (accepted && stage == NeteaseRewardStage.claim) {
        final data = result['data'];
        final gained = data is Map ? data['gainFlag'] : null;
        accepted = const {true, 1, '1', 'true'}.contains(gained);
        outcome = accepted
            ? MusicNetworkOutcome.success
            : const {false, 0, '0', 'false'}.contains(gained)
            ? MusicNetworkOutcome.business
            : MusicNetworkOutcome.format;
      }
      MusicNetworkDiagnostics.shared.record(
        platform: 'netease',
        operation: stage.operation,
        outcome: outcome,
        phase: MusicDiagnosticPhase.responseValidate,
        elapsedMs: watch.elapsedMilliseconds,
        status: status,
      );
      return result;
    } on Object catch (error) {
      final outcome = error is NeteaseRequestException
          ? error.outcome
          : classifyMusicNetworkError(error);
      final httpStatus = error is NeteaseRequestException
          ? error.httpStatus
          : null;
      MusicNetworkDiagnostics.shared.record(
        platform: 'netease',
        operation: stage.operation,
        outcome: outcome,
        phase: outcome == MusicNetworkOutcome.format
            ? MusicDiagnosticPhase.responseDecode
            : MusicDiagnosticPhase.networkSend,
        elapsedMs: watch.elapsedMilliseconds,
        status: httpStatus,
      );
      throw NeteaseRewardRequestFailure(stage, outcome, httpStatus);
    }
  }
}
