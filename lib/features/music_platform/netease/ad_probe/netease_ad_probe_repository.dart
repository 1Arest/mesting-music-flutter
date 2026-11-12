import 'dart:async';
import 'dart:convert';

import '../../../../core/cache/browse_response_cache.dart';
import '../../../../core/network/music_network_diagnostics.dart';
import '../../../../core/network/music_reward_diagnostic.dart';
import '../netease_free_listen_entry.dart';
import '../netease_music_repository.dart';
import '../netease_request_exception.dart';
import '../netease_reward_requests.dart';
import 'netease_ad_probe_context.dart';
import 'netease_ad_probe_report.dart';

abstract interface class NeteaseAdProbeService {
  bool get isCurrent;
  Future<NeteaseAdProbeReport> inspect({required Future<void> cancelled});
}

/// A deliberately separate read-only request chain: progress -> ad/get. It
/// cannot call qualification, gain, tracking, media or a server-issued URL.
/// An unsupported existing eapi response stops here, without identity switching
/// or trying newer encryption/SDK contracts with the account's credentials.
class NeteaseAdProbeRepository implements NeteaseAdProbeService {
  NeteaseAdProbeRepository(
    this.music, {
    bool Function()? stillCurrent,
    DateTime Function()? clock,
  }) : _stillCurrent = stillCurrent ?? (() => true),
       _clock = clock ?? DateTime.now,
       _user = music.api.session?.userId;

  final NeteaseMusicRepository music;
  final bool Function() _stillCurrent;
  final DateTime Function() _clock;
  final String? _user;
  bool _running = false;
  static const progressPath = '/api/ad/homepage/free/tab/continuous_rights';
  static const adPath = '/api/ad/get';

  @override
  bool get isCurrent =>
      _stillCurrent() &&
      _user != null &&
      music.credential != null &&
      music.api.session?.credentialId == music.credential &&
      music.api.session?.userId == _user;

  String _day() {
    final now = _clock();
    return '${now.year}-${now.month}-${now.day}';
  }

  @override
  Future<NeteaseAdProbeReport> inspect({
    required Future<void> cancelled,
  }) async {
    var identity = NeteaseRewardRequests.identity(music.api);
    var stage = NeteaseAdProbeStage.entry;
    MusicRewardDiagnostic? entryDiagnostic;
    NeteaseAdProbeRequestInfo? requestInfo;
    NeteaseAdProbeReport stop(
      NeteaseAdProbeOutcome outcome, {
      int? httpStatus,
      int? businessCode,
      MusicNetworkOutcome? networkOutcome,
      Map<String, dynamic>? response,
    }) => NeteaseAdProbeReport.stopped(
      outcome: outcome,
      stage: stage,
      identity: identity,
      entry: entryDiagnostic,
      requestInfo: requestInfo,
      response: response,
      httpStatus: httpStatus,
      businessCode: businessCode,
      networkOutcome: networkOutcome,
    );
    if (!isCurrent) return stop(NeteaseAdProbeOutcome.noSession);
    if (_running) return stop(NeteaseAdProbeOutcome.cancelled);
    _running = true;
    final abort = Completer<void>();
    var stopped = false;
    void cancel() {
      stopped = true;
      if (!abort.isCompleted) abort.complete();
    }

    unawaited(cancelled.then((_) => cancel()));
    final timeout = Timer(const Duration(seconds: 20), cancel);
    final requestedDay = _day();
    NeteaseAdProbeOutcome? invalid() => !isCurrent
        ? NeteaseAdProbeOutcome.accountChanged
        : stopped
        ? NeteaseAdProbeOutcome.cancelled
        : requestedDay != _day()
        ? NeteaseAdProbeOutcome.dayChanged
        : null;

    Future<Map<String, dynamic>> read(String path, Map<String, Object?> data) =>
        BrowseResponseCache.live(
          () => music.api.request(
            path,
            data,
            expectedCredential: music.credential,
            allowBusinessError: true,
            abortTrigger: abort.future,
          ),
        );
    try {
      // Let an already completed cancellation win before sending the first POST.
      await Future<void>.value();
      if (invalid() case final reason?) return stop(reason);
      final progress = await read(progressPath, const {
        'entranceType': 'FREE_LISTEN',
      });
      if (invalid() case final reason?) return stop(reason);
      final code = NeteaseRewardRequests.code(progress);
      if (code == null) return stop(NeteaseAdProbeOutcome.receiptIncomplete);
      if (code != 200) {
        return stop(NeteaseAdProbeOutcome.businessRejected, businessCode: code);
      }
      final data = progress['data'];
      final inspection = NeteaseFreeListenEntry.inspect(
        data is Map ? data['actionUrl'] : null,
      );
      entryDiagnostic = inspection.diagnostic;
      final entry = inspection.entry;
      final position = entry?.parameters['adPosition'];
      final resource = entry?.parameters['resourceId'];
      if (position is! int ||
          position <= 0 ||
          resource is! String ||
          resource.isEmpty ||
          resource.length > 256 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(resource)) {
        return stop(NeteaseAdProbeOutcome.invalidEntry);
      }
      // Official 9.6.15 utils.k.j0(int,String) joins the exact issued values.
      // No hardcoded advertising slot or resource is used as a fallback.
      final slot = '${position}_$resource';
      final context = NeteaseAdProbeContext.fromEntry(entry!, entryDiagnostic);
      if (context == null) return stop(NeteaseAdProbeOutcome.invalidContext);
      stage = NeteaseAdProbeStage.adData;
      if (invalid() case final reason?) return stop(reason);
      // A legitimate Set-Cookie on the entry read may update the isolated jar.
      // Report the identity actually used for this next request, not the one
      // captured before the previous response, without overriding either jar.
      identity = NeteaseRewardRequests.identity(music.api);
      requestInfo = context.info;
      final response = await read(adPath, {
        'type_ids': jsonEncode([slot]),
        'adextjson': context.adextjson,
      });
      if (invalid() case final reason?) return stop(reason);
      final adCode = NeteaseRewardRequests.code(response);
      if (adCode == null) {
        return stop(
          NeteaseAdProbeOutcome.receiptIncomplete,
          response: response,
        );
      }
      if (adCode != 200) {
        return stop(
          NeteaseAdProbeOutcome.businessRejected,
          businessCode: adCode,
          response: response,
        );
      }
      return NeteaseAdProbeReport.observe(
        response: response,
        requestedSlot: slot,
        identity: identity,
        entry: entryDiagnostic,
        requestInfo: requestInfo,
      );
    } on Object catch (error) {
      if (invalid() case final reason?) return stop(reason);
      return stop(
        NeteaseAdProbeOutcome.requestFailed,
        httpStatus: error is NeteaseRequestException ? error.httpStatus : null,
        networkOutcome: error is NeteaseRequestException
            ? error.outcome
            : classifyMusicNetworkError(error),
      );
    } finally {
      timeout.cancel();
      _running = false;
      // Release transport listeners; this never resubmits the request.
      if (!abort.isCompleted) abort.complete();
    }
  }
}
