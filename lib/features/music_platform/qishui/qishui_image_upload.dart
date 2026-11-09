import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../../core/network/music_http_client.dart';
import '../../../core/network/music_network_diagnostics.dart';
import 'qishui_api.dart';
import 'qishui_models.dart';
import 'qishui_diagnostics.dart';
import 'qishui_http_diagnostics.dart';
import 'qishui_image_upload_contract.dart';

/// The application API issues an ephemeral ImageX grant. Only that grant goes
/// to the vendor upload service; music Cookies, CSRF and NAS tokens stay in
/// QishuiApi. None of these objects is serializable or included in diagnostics.
class QishuiImageGrant {
  // The shipped Soda uploader uses this private ImageX gateway for BOTH its
  // HTTP request and AWSV4 canonical URI. Signing/requesting '/' is a different
  // operation even when the host, temporary credentials and query are equal.
  static const apiPath = QishuiImageUploadContract.apiPath;
  QishuiImageGrant._(
    this.endpoint,
    this.serviceId,
    this.accessKey,
    this.secretKey,
    this.sessionToken,
  );
  final Uri endpoint;
  final String serviceId, accessKey, secretKey, sessionToken;

  static QishuiImageGrant parse(Map<String, dynamic> response) {
    final data = sodaMap(response['data']);
    final row = sodaMap(response['uploader_info'] ?? data['uploader_info']);
    final security = sodaMap(row['security_token']);
    String field(Map<String, dynamic> map, String name, int max) {
      final value = '${map[name] ?? ''}';
      if (value.isEmpty ||
          value.length > max ||
          RegExp(r'[\x00-\x20\x7f]').hasMatch(value)) {
        throw const QishuiException(
          '汽水图片上传授权不完整',
          kind: QishuiFailureKind.format,
        );
      }
      return value;
    }

    final host = field(row, 'image_host', 512);
    final endpoint = Uri.tryParse(
      host.contains('://') ? host : 'https://$host',
    );
    if (endpoint == null ||
        !qishuiImageUploadUriAllowed(endpoint) ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        !{'', '/', apiPath}.contains(endpoint.path)) {
      throw const QishuiException(
        '汽水未返回可信的图片上传服务',
        kind: QishuiFailureKind.format,
      );
    }
    return QishuiImageGrant._(
      endpoint.replace(path: apiPath),
      field(row, 'service_id', 128),
      field(security, 'access_key_id', 256),
      field(security, 'secret_access_key', 512),
      field(security, 'session_token', 16384),
    );
  }
}

bool qishuiImageUploadUriAllowed(Uri uri) {
  if (uri.scheme != 'https' ||
      uri.port != 443 ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    return false;
  }
  return const [
    'bytedanceapi.com',
    'byteimg.com',
    'ibytedtos.com',
    'bytedtos.com',
    'volcengineapi.com',
    'imagex.cn',
    'pstatp.com',
  ].any((domain) => uri.host == domain || uri.host.endsWith('.$domain'));
}

/// Matches the shipped AWSV4Auth/BDAuthHelper canonical algorithm and private
/// gateway path and native default region. The static contract is shared with
/// diagnostic metadata, which contains only fixed public protocol constants.
/// Do not log canonical requests, temporary credentials or signatures.
class QishuiImageSignature {
  static Map<String, String> headers({
    required String method,
    required Uri uri,
    required String body,
    required QishuiImageGrant grant,
    required DateTime now,
  }) {
    if (uri.path != QishuiImageGrant.apiPath) {
      throw const QishuiException(
        '图片上传请求路径无效，请重新打开后重试',
        kind: QishuiFailureKind.format,
      );
    }
    String two(int n) => '$n'.padLeft(2, '0');
    final time = now.toUtc();
    final date = '${time.year}${two(time.month)}${two(time.day)}';
    final stamp =
        '${date}T${two(time.hour)}${two(time.minute)}${two(time.second)}Z';
    final headers = <String, String>{
      'x-amz-date': stamp,
      'x-amz-security-token': grant.sessionToken,
    };
    String hash(String value) => sha256.convert(utf8.encode(value)).toString();
    String escaped(String value) => Uri.encodeComponent(value)
        .replaceAll("'", '%27')
        .replaceAll('(', '%28')
        .replaceAll(')', '%29')
        .replaceAll('!', '%21')
        .replaceAll('*', '%2A');
    final queries = [
      for (final entry in uri.queryParametersAll.entries)
        for (final value in entry.value)
          '${escaped(entry.key)}=${escaped(value)}',
    ]..sort();
    final names = headers.keys.toList()..sort();
    final canonical = [
      method,
      uri.path.isEmpty ? '/' : uri.path,
      queries.join('&'),
      '${names.map((key) => '$key:${headers[key]!.trim()}').join('\n')}\n',
      names.join(';'),
      hash(body),
    ].join('\n');
    const region = QishuiImageUploadContract.region;
    const service = QishuiImageUploadContract.service;
    final scope = '$date/$region/$service/aws4_request';
    List<int> hmac(List<int> key, String data) =>
        Hmac(sha256, key).convert(utf8.encode(data)).bytes;
    var key = hmac(utf8.encode('AWS4${grant.secretKey}'), date);
    for (final part in [region, service, 'aws4_request']) {
      key = hmac(key, part);
    }
    final signature = hmac(
      key,
      'AWS4-HMAC-SHA256\n$stamp\n$scope\n${hash(canonical)}',
    ).map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    return {
      ...headers,
      'authorization':
          'AWS4-HMAC-SHA256 Credential=${grant.accessKey}/$scope,'
          'SignedHeaders=${names.join(';')},Signature=$signature',
    };
  }

  static String crc32(List<int> bytes) {
    var crc = 0xffffffff;
    for (final byte in bytes) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0);
      }
    }
    return ((crc ^ 0xffffffff) & 0xffffffff).toRadixString(16).padLeft(8, '0');
  }
}

class QishuiImageUploader {
  QishuiImageUploader(this.api, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final QishuiApi api;
  final DateTime Function() _clock;
  static const maximumBytes = 10 * 1024 * 1024;

  Future<String> upload(
    Uint8List bytes, {
    required Future<void> abort,
    required bool Function() current,
  }) async {
    if (bytes.isEmpty || bytes.length > maximumBytes) {
      throw const QishuiException('请选择10 MB以内的有效图片');
    }
    var cancelled = false;
    var finished = false;
    var activeStage = QishuiDiagnosticStage.grant;
    void record(
      QishuiDiagnosticStage stage,
      QishuiDiagnosticOutcome outcome, {
      int? httpStatus,
      Object? response,
      Object? serviceCode,
      Object? businessCode,
      QishuiDiagnosticReason? reason,
      bool? receiptAccepted,
    }) => QishuiDiagnostics.shared.record(
      feature: QishuiDiagnosticFeature.coverUpload,
      stage: stage,
      outcome: outcome,
      httpStatus: httpStatus,
      serviceCode: serviceCode,
      businessCode: businessCode,
      response: response,
      reason: reason,
      receiptAccepted: receiptAccepted,
    );
    Object? serviceCode(Object? response) {
      if (response is! Map) return null;
      final metadata = response['ResponseMetadata'];
      final error = metadata is Map ? metadata['Error'] : null;
      return error is Map ? error['Code'] : null;
    }

    unawaited(
      abort.then((_) {
        if (!finished) cancelled = true;
      }),
    );
    void guard() {
      if (cancelled || !current()) {
        throw const QishuiException(
          '账号已变化或上传已取消',
          kind: QishuiFailureKind.cancelled,
        );
      }
    }

    Future<http.Response> send(
      Uri uri,
      String method,
      String body,
      Map<String, String> headers, {
      required QishuiDiagnosticStage stage,
      List<int>? binary,
    }) async {
      activeStage = stage;
      guard();
      if (!qishuiImageUploadUriAllowed(uri)) {
        record(
          stage,
          QishuiDiagnosticOutcome.format,
          reason: QishuiDiagnosticReason.uploadAddressInvalid,
        );
        throw const QishuiException(
          '图片上传地址不受支持',
          kind: QishuiFailureKind.format,
        );
      }
      late final http.Response response;
      try {
        response = await sendMusicRequest(
          client: api.client,
          platform: 'qishui',
          operation: MusicNetworkOperation.other,
          abortTrigger: abort,
          retryRead: false,
          timeout: const Duration(seconds: 40),
          maximumResponseBytes: 512 * 1024,
          build: (cancel) =>
              http.AbortableRequest(method, uri, abortTrigger: cancel)
                ..followRedirects = false
                ..headers.addAll(headers)
                ..bodyBytes = binary ?? utf8.encode(body),
        );
      } on Object {
        record(
          stage,
          cancelled || !current()
              ? QishuiDiagnosticOutcome.cancelled
              : QishuiDiagnosticOutcome.network,
          reason: cancelled || !current()
              ? QishuiDiagnosticReason.accountChanged
              : QishuiDiagnosticReason.networkFailure,
        );
        rethrow;
      }
      guard();
      final decoded = qishuiDiagnosticJson(response.bodyBytes);
      record(
        stage,
        response.statusCode == 200
            ? QishuiDiagnosticOutcome.success
            : QishuiDiagnosticOutcome.http,
        httpStatus: response.statusCode,
        response: decoded,
        serviceCode: serviceCode(decoded),
        businessCode: qishuiDiagnosticBusinessCode(decoded),
        reason: response.statusCode == 200
            ? null
            : QishuiDiagnosticReason.httpRejected,
      );
      if (response.statusCode != 200) {
        throw QishuiException(
          '图片上传未完成（HTTP ${response.statusCode}）',
          kind: QishuiFailureKind.refused,
        );
      }
      return response;
    }

    Map<String, dynamic> result(
      http.Response response,
      QishuiDiagnosticStage stage,
    ) {
      final json = sodaMap(jsonDecode(utf8.decode(response.bodyBytes)));
      if (sodaMap(json['ResponseMetadata'])['Error'] != null) {
        record(
          stage,
          QishuiDiagnosticOutcome.refused,
          httpStatus: response.statusCode,
          response: json,
          serviceCode: serviceCode(json),
          reason: QishuiDiagnosticReason.receiptRejected,
        );
        throw const QishuiException(
          '图片服务未接受本次上传',
          kind: QishuiFailureKind.refused,
        );
      }
      return sodaMap(json['Result']);
    }

    try {
      guard();
      final credential = api.credential;
      Map<String, dynamic> authorization;
      try {
        authorization = await api.request(
          '/luna/video/uploader',
          get: true,
          query: const {'track_id': '', 'upload_type': '0', 'scene': '0'},
          expectedCredential: credential,
          abortTrigger: abort,
        );
      } on QishuiException catch (error) {
        // The uploader grant comes before any file bytes or playlist update.
        // Give the user an actionable stage while preserving a definite
        // helper refusal; it must not become an unknown playlist mutation.
        throw QishuiException(
          '图片上传授权未取得：${error.message}',
          code: error.code,
          kind: error.kind,
        );
      }
      late final QishuiImageGrant grant;
      try {
        grant = QishuiImageGrant.parse(authorization);
      } on QishuiException {
        record(
          QishuiDiagnosticStage.grant,
          QishuiDiagnosticOutcome.format,
          reason: QishuiDiagnosticReason.grantInvalid,
          response: authorization,
        );
        rethrow;
      }
      record(QishuiDiagnosticStage.grant, QishuiDiagnosticOutcome.success);
      guard();
      final apply = grant.endpoint.replace(
        queryParameters: {
          'Action': 'ApplyImageUpload',
          'Version': '2018-08-01',
          'ServiceId': grant.serviceId,
          'FileType': 'image',
          'UploadNum': '1',
        },
      );
      final applied = result(
        await send(
          apply,
          'GET',
          '',
          QishuiImageSignature.headers(
            method: 'GET',
            uri: apply,
            body: '',
            grant: grant,
            now: _clock(),
          ),
          stage: QishuiDiagnosticStage.apply,
        ),
        QishuiDiagnosticStage.apply,
      );
      final address = sodaMap(
        applied['UploadAddress'] ?? applied['InnerUploadAddress'],
      );
      final stores = sodaRows(address['StoreInfos']);
      final hosts = address['UploadHosts'];
      if (stores.length != 1 || hosts is! List || hosts.isEmpty) {
        record(
          QishuiDiagnosticStage.apply,
          QishuiDiagnosticOutcome.format,
          response: applied,
          reason: QishuiDiagnosticReason.uploadAddressInvalid,
        );
        throw const QishuiException(
          '图片上传地址资料不完整',
          kind: QishuiFailureKind.format,
        );
      }
      final store = stores.single;
      final storeUri = '${store['StoreUri'] ?? ''}';
      final auth = '${store['Auth'] ?? ''}';
      final session = '${address['SessionKey'] ?? ''}';
      if (!validQishuiImageKey(storeUri) ||
          auth.isEmpty ||
          auth.length > 16384 ||
          RegExp(r'[\r\n\x00]').hasMatch(auth) ||
          session.isEmpty ||
          session.length > 8192) {
        record(
          QishuiDiagnosticStage.apply,
          QishuiDiagnosticOutcome.format,
          response: applied,
          reason: QishuiDiagnosticReason.invalidFields,
        );
        throw const QishuiException(
          '图片上传授权资料无效',
          kind: QishuiFailureKind.format,
        );
      }
      final host = '${hosts.first}';
      final uploadHost = Uri.tryParse(
        host.contains('://') ? host : 'https://$host',
      );
      if (uploadHost == null ||
          uploadHost.hasQuery ||
          !{'', '/'}.contains(uploadHost.path)) {
        record(
          QishuiDiagnosticStage.apply,
          QishuiDiagnosticOutcome.format,
          response: applied,
          reason: QishuiDiagnosticReason.uploadAddressInvalid,
        );
        throw const QishuiException('图片存储地址无效', kind: QishuiFailureKind.format);
      }
      final uploadUri = uploadHost.replace(path: '/upload/v1/$storeUri');
      final uploaded = await send(
        uploadUri,
        'POST',
        '',
        {
          'authorization': auth,
          'content-type': 'application/octet-stream',
          'x-upload-content-crc32': QishuiImageSignature.crc32(bytes),
        },
        stage: QishuiDiagnosticStage.storage,
        binary: bytes,
      );
      final receipt = sodaMap(jsonDecode(utf8.decode(uploaded.bodyBytes)));
      if (receipt['code'] != 2000 &&
          receipt['code'] != 0 &&
          receipt['code'] != '2000') {
        record(
          QishuiDiagnosticStage.storage,
          QishuiDiagnosticOutcome.refused,
          response: receipt,
          businessCode: receipt['code'],
          reason: QishuiDiagnosticReason.storageReceiptInvalid,
          receiptAccepted: false,
        );
        throw const QishuiException(
          '图片内容尚未被存储服务确认',
          kind: QishuiFailureKind.refused,
        );
      }
      final commit = grant.endpoint.replace(
        queryParameters: {
          'Action': 'CommitImageUpload',
          'Version': '2018-08-01',
          'ServiceId': grant.serviceId,
        },
      );
      final body = jsonEncode({
        'SessionKey': session,
        'SuccessActionStatus': '200',
      });
      final committed = result(
        await send(commit, 'POST', body, {
          ...QishuiImageSignature.headers(
            method: 'POST',
            uri: commit,
            body: body,
            grant: grant,
            now: _clock(),
          ),
          'content-type': 'application/json',
        }, stage: QishuiDiagnosticStage.commit),
        QishuiDiagnosticStage.commit,
      );
      final returned = sodaRows(committed['Results']);
      final uri = returned.length == 1 ? '${returned.single['Uri'] ?? ''}' : '';
      if (uri != storeUri || !validQishuiImageKey(uri)) {
        record(
          QishuiDiagnosticStage.commit,
          QishuiDiagnosticOutcome.format,
          response: committed,
          reason: QishuiDiagnosticReason.commitReceiptInvalid,
          receiptAccepted: false,
        );
        throw const QishuiException(
          '图片上传尚未取得一致的云端凭据，请重试',
          kind: QishuiFailureKind.format,
        );
      }
      guard();
      record(
        QishuiDiagnosticStage.commit,
        QishuiDiagnosticOutcome.success,
        receiptAccepted: true,
      );
      return uri;
    } on QishuiException {
      rethrow;
    } on FormatException {
      guard();
      record(
        activeStage,
        QishuiDiagnosticOutcome.format,
        reason: QishuiDiagnosticReason.invalidJson,
      );
      throw const QishuiException('图片上传回执无法读取，请重新选择保存');
    } on Object {
      guard();
      // Never surface response JSON, upload endpoints or ephemeral secrets.
      throw const QishuiException('图片上传未完成，请重新选择保存；原歌单封面未改动');
    } finally {
      finished = true;
    }
  }
}

bool validQishuiImageKey(String value) =>
    value.length <= 1024 &&
    RegExp(r'^[A-Za-z0-9_\-/\.]+$').hasMatch(value) &&
    !value.startsWith('/') &&
    !value.split('/').contains('..');
