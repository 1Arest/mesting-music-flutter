import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_diagnostic_export.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  QishuiDiagnostics buffer() =>
      QishuiDiagnostics(now: () => DateTime.utc(2026, 11, 8, 5, 30));

  void add(
    QishuiDiagnostics diagnostics, {
    QishuiDiagnosticFeature feature = QishuiDiagnosticFeature.following,
    QishuiDiagnosticOutcome outcome = QishuiDiagnosticOutcome.format,
    Object? response,
  }) => diagnostics.record(
    feature: feature,
    stage: QishuiDiagnosticStage.parse,
    outcome: outcome,
    response: response,
  );

  test(
    'response structure excludes values, arbitrary keys and nested secrets',
    () {
      final diagnostics = buffer();
      final response = {
        'data': {
          'follow_items': [
            {
              'item_type': 'private-value-178',
              'user': {
                'id': '9876543210987654321',
                'nickname': 'private-name-178',
                'cookie': 'private-cookie-178',
              },
            },
          ],
          'unknown-private-name-178': {'token': 'private-token-178'},
          'next_cursor': 'private-cursor-178',
        },
        'message': 'private-error-message-178',
        'headers': {'authorization': 'private-signature-178'},
        'https://private-host-178.example': 'private-url-178',
      };
      add(diagnostics, response: response);
      final text = diagnostics.export();
      expect(text, contains('follow_items'));
      expect(text, contains('fieldCount'));
      for (final private in [
        'private-',
        '9876543210987654321',
        'cookie',
        'authorization',
        'private-signature-178',
        'token',
        'https://',
      ]) {
        expect(text, isNot(contains(private)));
      }
      final root = jsonDecode(text) as Map;
      expect(root['appVersion'], '1.0.91');
      expect(root['appVersionCode'], 112);
      expect(root['platform'], 'qishui');
      expect(root['memoryOnly'], isTrue);
      expect(root['complete'], isTrue);
    },
  );

  test(
    'known codes are useful while malformed codes never become text sinks',
    () {
      final diagnostics = buffer();
      diagnostics.record(
        feature: QishuiDiagnosticFeature.coverUpload,
        stage: QishuiDiagnosticStage.apply,
        outcome: QishuiDiagnosticOutcome.http,
        httpStatus: 400,
        businessCode: '1000062',
        serviceCode: 'SignatureDoesNotMatch',
      );
      diagnostics.record(
        feature: QishuiDiagnosticFeature.coverUpload,
        stage: QishuiDiagnosticStage.helper,
        outcome: QishuiDiagnosticOutcome.refused,
        serviceCode: 'forbidden_query',
      );
      diagnostics.record(
        feature: QishuiDiagnosticFeature.coverUpload,
        stage: QishuiDiagnosticStage.apply,
        outcome: QishuiDiagnosticOutcome.http,
        httpStatus: 99999,
        businessCode: '400 secret-code-178',
        serviceCode: 'InvalidParameter secret-value-178',
      );
      final rows = diagnostics.events;
      expect(rows[0]['httpStatus'], 400);
      expect(rows[0]['businessCode'], 1000062);
      expect(rows[0]['serviceCode'], 'SignatureDoesNotMatch');
      expect(rows[1]['serviceCode'], 'forbidden_query');
      expect(rows[2]['serviceCode'], 'unknown');
      expect(rows[2]['serviceCodePresent'], isTrue);
      expect(rows[2].containsKey('businessCode'), isFalse);
      expect(rows[2].containsKey('httpStatus'), isFalse);
      expect(diagnostics.export(), isNot(contains('secret-')));
    },
  );

  test(
    'nested snapshots remain immutable after a caller mutates the response',
    () {
      final diagnostics = buffer();
      final response = <String, Object>{
        'listen_duration': {'total_duration': 42},
      };
      add(diagnostics, response: response);
      final snapshot = diagnostics.export();
      response['listen_duration'] = 'changed-later-178';
      expect(diagnostics.export(), snapshot);
      final shape = diagnostics.events.single['shape'] as Map;
      expect(() => shape['value'] = 'mutation', throwsUnsupportedError);
      expect(() => diagnostics.events.clear(), throwsUnsupportedError);
    },
  );

  test(
    'group exports do not mix an unrelated later failure into the issue',
    () {
      final diagnostics = buffer();
      add(diagnostics, feature: QishuiDiagnosticFeature.following);
      add(diagnostics, feature: QishuiDiagnosticFeature.officialListening);
      add(diagnostics, feature: QishuiDiagnosticFeature.listeningReport);
      add(diagnostics, feature: QishuiDiagnosticFeature.coverUpload);
      add(diagnostics, feature: QishuiDiagnosticFeature.playlistCover);
      expect(diagnostics.select(QishuiDiagnosticGroup.social), hasLength(1));
      expect(diagnostics.select(QishuiDiagnosticGroup.listening), hasLength(2));
      expect(diagnostics.select(QishuiDiagnosticGroup.cover), hasLength(2));
      final cover =
          jsonDecode(
                diagnostics.exportCompact(group: QishuiDiagnosticGroup.cover),
              )
              as Map;
      expect(cover['group'], 'cover');
      expect((cover['events'] as List).map((row) => (row as Map)['feature']), [
        'coverUpload',
        'playlistCover',
      ]);
    },
  );

  test(
    'bounded compact export retains complete JSON around the latest failure',
    () {
      final diagnostics = buffer();
      final wide = <String, Object>{
        'data': {
          for (final key in [
            'follow_items',
            'users',
            'items',
            'list',
            'my_info',
            'my_stats',
            'user_stats',
            'listen_duration',
            'music_wall',
            'Result',
          ])
            key: {
              'data': {
                'items': List.filled(200, {'user': 'private-wide-178'}),
              },
            },
        },
      };
      for (var index = 0; index < 180; index++) {
        add(
          diagnostics,
          outcome: QishuiDiagnosticOutcome.success,
          response: wide,
        );
      }
      diagnostics.record(
        feature: QishuiDiagnosticFeature.following,
        stage: QishuiDiagnosticStage.parse,
        outcome: QishuiDiagnosticOutcome.format,
        reason: QishuiDiagnosticReason.missingFields,
        response: wide,
      );
      add(diagnostics, outcome: QishuiDiagnosticOutcome.success);
      expect(diagnostics.events, hasLength(QishuiDiagnostics.maximumEvents));
      final text = diagnostics.exportCompact();
      expect(text.length, lessThanOrEqualTo(4096));
      final result = jsonDecode(text) as Map;
      expect(result['complete'], isTrue);
      expect((result['events'] as List).last['reason'], 'missingFields');
      expect(text, isNot(contains('private-wide-178')));
    },
  );

  test(
    'empty compact export is valid and does not invent a network observation',
    () {
      final result = jsonDecode(buffer().exportCompact()) as Map;
      expect(result['events'], isEmpty);
      expect(result['eventCount'], 0);
      expect(result['complete'], isTrue);
    },
  );

  test(
    'cover contract is fixed metadata and artist structure never copies IDs',
    () {
      final diagnostics = buffer();
      add(
        diagnostics,
        feature: QishuiDiagnosticFeature.artistCollection,
        response: {
          'artists': [
            {'id': '178-private-artist', 'name': '178-private-name'},
          ],
          'artist_ids': ['178-private-id'],
          'deleted_artists': ['178-private-deleted'],
          'follow_status': 2,
        },
      );
      final socialText = diagnostics.export(
        group: QishuiDiagnosticGroup.social,
      );
      final social = jsonDecode(socialText) as Map;
      expect(social.containsKey('imageUploadContract'), isFalse);
      expect(socialText, contains('artists'));
      expect(socialText, contains('artist_ids'));
      expect(socialText, contains('deleted_artists'));
      expect(socialText, contains('follow_status'));
      expect(socialText, isNot(contains('178-private-')));
      for (final group in [
        QishuiDiagnosticGroup.all,
        QishuiDiagnosticGroup.cover,
      ]) {
        final report = jsonDecode(diagnostics.export(group: group)) as Map;
        expect(report['imageUploadContract'], {
          'gatewayPath': '/top/v1',
          'signature': 'AWS4-HMAC-SHA256',
          'service': 'imagex',
          'regionMode': 'officialSdkDefault',
          'region': 'sdwdmwlll',
        });
      }
      final listening =
          jsonDecode(diagnostics.export(group: QishuiDiagnosticGroup.listening))
              as Map;
      expect(listening.containsKey('imageUploadContract'), isFalse);
    },
  );

  test(
    'file export freezes a filtered snapshot before asynchronous IO',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'qishui-diagnostic178-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final diagnostics = buffer();
      add(diagnostics, feature: QishuiDiagnosticFeature.coverUpload);
      add(diagnostics, feature: QishuiDiagnosticFeature.following);
      final support = Completer<Directory>();
      String? shared;
      final exporter = QishuiDiagnosticExport(
        supportDirectory: () => support.future,
        shareFile: (path) async {
          shared = path;
        },
      );
      final pending = exporter.share(
        diagnostics: diagnostics,
        group: QishuiDiagnosticGroup.cover,
      );
      add(diagnostics, feature: QishuiDiagnosticFeature.playlistCover);
      support.complete(directory);
      await pending;
      expect(
        shared,
        '${directory.path}/qishui_diagnostics/mesting-qishui-report.json',
      );
      final report = jsonDecode(await File(shared!).readAsString()) as Map;
      expect(report['group'], 'cover');
      expect(report['eventCount'], 1);
      expect(report['events'][0]['feature'], 'coverUpload');
    },
  );

  test(
    'native share uses the separate exact Qishui method and private filename',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'qishui-diagnostic178-',
      );
      addTearDown(() => directory.delete(recursive: true));
      const channel = MethodChannel('com.mesting.music/share');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final diagnostics = buffer();
      add(diagnostics);
      await QishuiDiagnosticExport(
        supportDirectory: () async => directory,
      ).share(diagnostics: diagnostics);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'shareQishuiDiagnosticJson');
      expect(calls.single.arguments, {
        'path':
            '${directory.path}/qishui_diagnostics/mesting-qishui-report.json',
      });
    },
  );
}
