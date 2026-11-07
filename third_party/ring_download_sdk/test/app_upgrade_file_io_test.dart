import 'dart:io';
import 'dart:typed_data';

import 'package:ring_download_sdk/compat.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File source, target;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('app-upgrade-file-io-');
    source = File('${directory.path}/bootstrap');
    target = File('${directory.path}/part');
  });
  tearDown(() => directory.delete(recursive: true));

  test('HTTPS file diagnostics survive the closed export vocabulary', () {
    for (final code in [
      'https_file_promoted',
      'https_file_copied',
      'verified_https_hash_reused',
    ]) {
      expect(
        AppUpgradeP2PDiagnostic(stage: 'https', code: code).toJson()['code'],
        code,
      );
    }
    expect(
      AppUpgradeP2PDiagnostic.safeCode('private-file-path'),
      'unknown_error',
    );
  });

  test(
    'background hash handles many stream chunks and leaves file unlocked',
    () async {
      final bytes = Uint8List.fromList(
        List.generate(3 * 1048576 + 37, (i) => i % 251),
      );
      await source.writeAsBytes(bytes, flush: true);
      expect(
        await appUpgradeFileSha256(source.path),
        sha256.convert(bytes).toString(),
      );
      await source.rename(target.path);
      expect(await target.length(), bytes.length);
    },
  );

  test(
    'every hash reads disk again even when path and size are unchanged',
    () async {
      await source.writeAsBytes([1, 2, 3], flush: true);
      final original = await appUpgradeFileSha256(source.path);
      await source.writeAsBytes([1, 2, 4], flush: true);
      expect(await appUpgradeFileSha256(source.path), isNot(original));
    },
  );

  test(
    'empty file has its real digest and missing file propagates failure',
    () async {
      await source.writeAsBytes([]);
      expect(
        await appUpgradeFileSha256(source.path),
        sha256.convert([]).toString(),
      );
      await source.delete();
      await expectLater(
        appUpgradeFileSha256(source.path),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test(
    'rename replaces the old prefix with the exact verified source',
    () async {
      await source.writeAsBytes([1, 2, 3], flush: true);
      await target.writeAsBytes([9, 9, 9, 9], flush: true);
      final digest = await appUpgradeFileSha256(source.path);
      expect(await promoteAppUpgradeHttpsFile(source, target), true);
      expect(source.existsSync(), false);
      expect(await appUpgradeFileSha256(target.path), digest);
    },
  );

  test(
    'rename failure copies bytes but cannot transfer hash verification',
    () async {
      await source.writeAsBytes([1, 2, 3], flush: true);
      expect(
        await promoteAppUpgradeHttpsFile(_RenameRejectedFile(source), target),
        false,
      );
      expect(await target.readAsBytes(), [1, 2, 3]);
      expect(source.existsSync(), true);
    },
  );

  test(
    'copy failure is propagated rather than reporting a promoted file',
    () async {
      await expectLater(
        promoteAppUpgradeHttpsFile(_RenameRejectedFile(source), target),
        throwsA(isA<FileSystemException>()),
      );
      expect(target.existsSync(), false);
    },
  );
}

class _RenameRejectedFile implements File {
  _RenameRejectedFile(this.actual);
  final File actual;
  @override
  Future<File> rename(String newPath) async =>
      throw const FileSystemException('rename rejected');
  @override
  Future<File> copy(String newPath) => actual.copy(newPath);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
