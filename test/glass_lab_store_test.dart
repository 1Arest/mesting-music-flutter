import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/core/diagnostics/glass_lab_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late GlassLabReportStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('mesting-glass-lab-');
    store = GlassLabReportStore(root: () async => root);
  });
  tearDown(() async {
    // Only the newly created, explicitly named test directory may be removed.
    final parent = await root.parent.resolveSymbolicLinks();
    expect(parent, await Directory.systemTemp.resolveSymbolicLinks());
    expect(
      root.uri.pathSegments.where((p) => p.isNotEmpty).last,
      startsWith('mesting-glass-lab-'),
    );
    await root.delete(recursive: true);
  });
  test(
    'fixed isolated export preserves real-page reports and complete previous bytes',
    () async {
      final flow = File('${root.path}/mesting-flow-report.json');
      await flow.writeAsString('existing');
      await store.save({'schema': 1, 'records': <Object>[]});
      final file = await store.reportFile();
      final before = await file.readAsBytes();
      await store.save({
        'schema': 1,
        'records': [
          {'status': 'completed'},
        ],
      });
      expect(await flow.readAsString(), 'existing');
      expect(await File('${file.path}.previous').readAsBytes(), before);
      expect(
        (jsonDecode(await file.readAsString()) as Map)['records'],
        hasLength(1),
      );
      expect(file.uri.pathSegments.last, 'mesting-glass-lab-report.json');
    },
  );
  test(
    'an oversized export is rejected without replacing or truncating the prior report',
    () async {
      await store.save({'schema': 1, 'records': <Object>[]});
      final file = await store.reportFile();
      final before = await file.readAsBytes();
      await expectLater(
        store.save({'large': 'x' * GlassLabReportStore.maximumBytes}),
        throwsStateError,
      );
      expect(await file.readAsBytes(), before);
    },
  );
}
