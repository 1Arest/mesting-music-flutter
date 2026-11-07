import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'models.dart';

/// The business-selected external URL has no hosted-service dependency. Resume
/// state is scoped to the exact source; without a digest it requires a strong
/// ETag, so unsigned metadata cannot accidentally splice two different files.
class DirectHttpsDownload {
  DirectHttpsDownload(this.config, this.http);
  final RingDownloadConfig config;
  final Dio http;

  Future<File> download(
    RingDownloadRequest request,
    void Function(int, int) progress,
    CancelToken token,
  ) async {
    final parent =
        config.storageDirectory ?? await getApplicationSupportDirectory();
    final directory = Directory(
      path.join(parent.path, 'ring_download_sdk', config.appId, 'direct-https'),
    );
    await directory.create(recursive: true);
    final identity = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              config.appId, request.releaseId, request.version,
              request.sha256.trim().toLowerCase(), request.fileSize,
              // With no independent digest, a new signed URL starts a fresh artifact.
              if (!request.hasExpectedSha256) request.url.toString(),
            ]),
          ),
        )
        .toString();
    final partial = File(path.join(directory.path, '$identity.apk.part'));
    final stateFile = File('${partial.path}.json');
    final target = File(path.join(directory.path, '$identity.apk'));
    final sources = [
      request.url,
      if (request.backupUrl != null &&
          !RingDownloadRequest.hostedHosts.contains(
            request.backupUrl!.host.toLowerCase(),
          ))
        request.backupUrl!,
    ];
    Object? failure;
    var refreshed = false;
    for (var source = 0; source < sources.length; source++) {
      var current = sources[source];
      for (var attempt = 0; attempt < 3; attempt++) {
        if (token.isCancelled) throw token.cancelError!;
        try {
          await _transfer(
            request,
            current,
            partial,
            stateFile,
            progress,
            token,
          );
          if (token.isCancelled) throw token.cancelError!;
          if (await target.exists()) await target.delete();
          await partial.rename(target.path);
          if (await stateFile.exists()) await stateFile.delete();
          return target;
        } on _HttpStatus catch (error) {
          failure = const RingDownloadException(RingDownloadError.network);
          if ((error.status == 401 || error.status == 403) &&
              !refreshed &&
              config.refreshRelease != null) {
            refreshed = true;
            final next = await config.refreshRelease!(request).timeout(
              const Duration(seconds: 10),
            );
            if (next != null) {
              next.validate(appId: config.appId);
              if (next.usesHostedService ||
                  next.releaseId != request.releaseId ||
                  next.version != request.version ||
                  next.androidVersionCode != request.androidVersionCode ||
                  next.fileSize != request.fileSize ||
                  next.sha256.trim().toLowerCase() !=
                      request.sha256.trim().toLowerCase()) {
                throw const RingDownloadException(
                  RingDownloadError.invalidMetadata,
                );
              }
              current = next.url;
              // Source-scoped resume validation resets an expired URL's bytes.
              continue;
            }
          }
          // No polling or unbounded quota retries. Another explicitly supplied
          // external source may still be used, without contacting our service.
          if (error.status < 500 && error.status != 408) break;
        } on DioException catch (error) {
          if (token.isCancelled) rethrow;
          failure = error;
        } on _IncompleteBody {
          failure = const RingDownloadException(RingDownloadError.network);
        }
      }
    }
    throw failure ?? const RingDownloadException(RingDownloadError.network);
  }

  Future<void> _transfer(
    RingDownloadRequest request,
    Uri initial,
    File partial,
    File stateFile,
    void Function(int, int) progress,
    CancelToken token,
  ) async {
    var current = initial;
    var redirects = 0;
    var rangeReset = false;
    for (var segment = 0; segment < 256; segment++) {
      if (token.isCancelled) throw token.cancelError!;
      _validateUrl(current);
      final sourceKey = sha256
          .convert(utf8.encode(current.toString()))
          .toString();
      var state = await _readState(stateFile);
      var offset = await partial.exists() ? await partial.length() : 0;
      final etag = state['etag'] as String? ?? '';
      if (state['source'] != sourceKey ||
          (offset > 0 && !request.hasExpectedSha256 && !_strongEtag(etag)) ||
          offset > RingDownloadRequest.maxFileSize) {
        offset = 0;
        state = {};
      }
      if (offset == 0 && await partial.exists()) await partial.writeAsBytes([]);
      final response = await http.get<ResponseBody>(
        current.toString(),
        cancelToken: token,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: false,
          validateStatus: (_) => true,
          headers: {
            'Accept':
                'application/vnd.android.package-archive, application/octet-stream',
            'Accept-Encoding': 'identity',
            if (offset > 0) 'Range': 'bytes=$offset-',
            if (offset > 0 && _strongEtag(etag)) 'If-Range': etag,
          },
        ),
      );
      final body = response.data;
      if (body == null) throw const _IncompleteBody();
      final status = response.statusCode ?? 0;
      if (const {301, 302, 303, 307, 308}.contains(status)) {
        await _discard(body);
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null || ++redirects > 5) {
          throw const RingDownloadException(RingDownloadError.network);
        }
        current = current.resolve(location);
        _validateUrl(current);
        continue;
      }
      if (status == 416 && offset > 0 && !rangeReset) {
        await _discard(body);
        rangeReset = true;
        await partial.writeAsBytes([]);
        await stateFile.writeAsString('{}', flush: true);
        continue;
      }
      if (status != 200 && status != 206) {
        await _discard(body);
        throw _HttpStatus(status);
      }
      final contentLength = _length(response.headers);
      int? responseBytes = contentLength;
      var total = contentLength ?? 0;
      if (status == 206) {
        final range = RegExp(
          r'^bytes (\d+)-(\d+)/(\d+)$',
        ).firstMatch(response.headers.value('content-range') ?? '');
        if (range == null) {
          await _discard(body);
          throw const RingDownloadException(RingDownloadError.integrity);
        }
        final start = int.parse(range[1]!);
        final end = int.parse(range[2]!);
        total = int.parse(range[3]!);
        responseBytes = end - start + 1;
        final responseEtag = response.headers.value('etag') ?? '';
        if (start != offset ||
            end < start ||
            end >= total ||
            (contentLength != null && contentLength != responseBytes) ||
            (offset > 0 && _strongEtag(etag) && responseEtag != etag) ||
            (offset > 0 && state['total'] is int && state['total'] != total)) {
          await _discard(body);
          throw const RingDownloadException(RingDownloadError.integrity);
        }
      } else {
        // A source ignoring Range sent a fresh full response. Never append it.
        offset = 0;
      }
      if (total > RingDownloadRequest.maxFileSize ||
          (request.fileSize > 0 && total > 0 && total != request.fileSize)) {
        await _discard(body);
        throw const RingDownloadException(RingDownloadError.integrity);
      }
      if (request.fileSize > 0) total = request.fileSize;
      final responseEtag = response.headers.value('etag') ?? '';
      await stateFile.writeAsString(
        jsonEncode({
          'source': sourceKey,
          'etag': _strongEtag(responseEtag) ? responseEtag : '',
          if (total > 0) 'total': total,
        }),
        flush: true,
      );
      final output = await partial.open(
        mode: offset == 0 ? FileMode.write : FileMode.append,
      );
      final chunks = StreamIterator<Uint8List>(body.stream);
      var bodyBytes = 0;
      final cancelled = token.whenCancel.then<bool>((error) => throw error);
      cancelled.ignore();
      try {
        progress(offset, total);
        while (await Future.any([chunks.moveNext(), cancelled])) {
          if (token.isCancelled) throw token.cancelError!;
          final chunk = chunks.current;
          if (offset + bodyBytes + chunk.length >
                  RingDownloadRequest.maxFileSize ||
              (responseBytes != null &&
                  bodyBytes + chunk.length > responseBytes) ||
              (total > 0 && offset + bodyBytes + chunk.length > total)) {
            throw const RingDownloadException(RingDownloadError.integrity);
          }
          await output.writeFrom(chunk);
          bodyBytes += chunk.length;
          progress(offset + bodyBytes, total);
        }
      } finally {
        await chunks.cancel();
        await output.close();
      }
      if (token.isCancelled) throw token.cancelError!;
      if (responseBytes != null && bodyBytes != responseBytes) {
        throw const _IncompleteBody();
      }
      final received = offset + bodyBytes;
      if (received == 0) throw const _IncompleteBody();
      if (status == 206 && received < total) continue;
      if (total > 0 && received != total) throw const _IncompleteBody();
      return;
    }
    throw const RingDownloadException(RingDownloadError.network);
  }

  static void _validateUrl(Uri url) {
    if (url.scheme != 'https' ||
        url.host.isEmpty ||
        url.port != 443 ||
        url.userInfo.isNotEmpty ||
        url.fragment.isNotEmpty) {
      throw const RingDownloadException(RingDownloadError.invalidRequest);
    }
  }

  static bool _strongEtag(String value) =>
      value.startsWith('"') &&
      value.endsWith('"') &&
      value.length > 2 &&
      !value.contains('\r') &&
      !value.contains('\n');

  static int? _length(Headers headers) {
    final value = headers.value(HttpHeaders.contentLengthHeader);
    if (value == null) return null;
    final length = int.tryParse(value);
    if (length == null || length < 0) {
      throw const RingDownloadException(RingDownloadError.integrity);
    }
    return length;
  }

  static Future<Map<String, dynamic>> _readState(File file) async {
    try {
      if (await file.length() > 8192) return {};
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> _discard(ResponseBody body) async {
    await body.stream.listen((_) {}).cancel();
  }
}

class _HttpStatus implements Exception {
  const _HttpStatus(this.status);
  final int status;
}

class _IncompleteBody implements Exception {
  const _IncompleteBody();
}
