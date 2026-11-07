import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

// Private example fixture is deliberately outside the SDK's production lib.
// ignore: avoid_relative_lib_imports
import '../example/lib/p8p_lifecycle_file_io.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('p8p-io-owner-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
    'piece read holds an actual regular-file owner across retirement',
    () async {
      final real = File('${root.path}/verified.apk');
      final payload = Uint8List.fromList(
        List<int>.generate(131089, (i) => i % 251),
      );
      await real.writeAsBytes(payload, flush: true);
      final sentinel = File('${root.path}/unrelated.txt');
      await sentinel.writeAsString('keep');
      final gate = NativeFileIoGate()..armRead(real.path);
      await IOOverrides.runWithIOOverrides(() async {
        var returned = false;
        final bytes = BytesBuilder(copy: false);
        final reading = File(real.path)
            .openRead(13, 100019)
            .forEach(bytes.add)
            .then((_) {
              returned = true;
            });
        reading.ignore();
        await gate.entered.timeout(const Duration(seconds: 5));
        final held = gate.snapshot();
        expect(held['target_handles'], 1);
        expect(held['pending_operations'], 1);
        expect(held['native_bytes'], greaterThan(0));
        expect(real.statSync().type, FileSystemEntityType.file);
        gate.retire();
        expect(returned, isFalse);
        expect(gate.snapshot()['target_handles'], 1);
        await reading.timeout(const Duration(seconds: 6));
        expect(bytes.takeBytes(), payload.sublist(13, 100019));
        final done = gate.snapshot();
        expect(done['target_handles'], 0);
        expect(done['all_wrapped_handles'], 0);
        expect(done['pending_operations'], 0);
        expect(done['valid'], isTrue);
        expect(done['hold_duration_ms'], 3000);
        expect(done['hold_is_after_native_io'], isTrue);
        final events = (done['events'] as List).cast<Map<String, Object?>>();
        final entered = events.singleWhere(
          (e) => e['event'] == 'native_io_completed_with_handle_open',
        );
        final released = events.singleWhere(
          (e) => e['event'] == 'hold_ended_with_handle_open',
        );
        final closed = events.singleWhere((e) => e['event'] == 'closed');
        expect(
          (released['at_us'] as int) - (entered['at_us'] as int),
          greaterThanOrEqualTo(2900000),
        );
        expect(
          closed['at_us'] as int,
          greaterThanOrEqualTo(released['at_us'] as int),
        );
      }, gate);
      expect(await sentinel.readAsString(), 'keep');
    },
  );

  test(
    'write has real persisted bytes and keeps its handle until return',
    () async {
      final real = File('${root.path}/download.part');
      final payload = List<int>.generate(1048589, (i) => i % 239);
      final gate = NativeFileIoGate()..armWrite(real.path);
      await IOOverrides.runWithIOOverrides(() async {
        final handle = await File(real.path).open(mode: FileMode.write);
        try {
          var returned = false;
          final writing = handle.writeFrom(payload).then((value) {
            returned = true;
            expect(identical(value, handle), isTrue);
          });
          writing.ignore();
          await gate.entered.timeout(const Duration(seconds: 5));
          expect(await real.readAsBytes(), payload);
          expect(gate.snapshot()['target_handles'], 1);
          expect(gate.snapshot()['pending_operations'], 1);
          gate.retire();
          expect(returned, isFalse);
          await writing.timeout(const Duration(seconds: 6));
        } finally {
          await handle.close();
        }
        final done = gate.snapshot();
        expect(done['valid'], isTrue);
        expect(done['target_handles'], 0);
        expect(done['pending_operations'], 0);
        expect(done['premature_close_calls'], 0);
      }, gate);
      expect(await real.length(), payload.length);
    },
  );

  test(
    'premature close is observed, never hidden by a helper close wait',
    () async {
      final real = File('${root.path}/premature.part');
      final gate = NativeFileIoGate()..armWrite(real.path);
      await IOOverrides.runWithIOOverrides(() async {
        final handle = await File(real.path).open(mode: FileMode.write);
        final writing = handle.writeFrom([1, 2, 3, 4]);
        writing.ignore();
        await gate.entered.timeout(const Duration(seconds: 5));
        gate.retire();
        await handle.close();
        expect(gate.snapshot()['premature_close_calls'], 1);
        expect(gate.snapshot()['target_handles'], 0);
        expect(gate.snapshot()['pending_operations'], 1);
        await expectLater(writing, throwsStateError);
        expect(gate.snapshot()['valid'], isFalse);
        expect(gate.snapshot()['pending_operations'], 0);
        expect(gate.snapshot()['all_wrapped_handles'], 0);
      }, gate);
      expect(await real.readAsBytes(), [1, 2, 3, 4]);
    },
  );

  test(
    'late transfer IO is counted while its real behavior stays visible',
    () async {
      final real = File('${root.path}/late.apk');
      await real.writeAsBytes([1, 2, 3, 4]);
      final gate = NativeFileIoGate()
        ..armRead(real.path)
        ..retire();
      await IOOverrides.runWithIOOverrides(() async {
        final actual = await File(
          real.path,
        ).openRead(1, 3).fold<List<int>>([], (a, b) => a..addAll(b));
        expect(actual, [2, 3]);
        expect(gate.snapshot()['claimed'], isFalse);
        expect(gate.snapshot()['new_read_streams_after_retire'], 1);
        expect(gate.snapshot()['valid'], isFalse);
        expect(gate.snapshot()['target_handles'], 0);
      }, gate);
    },
  );

  test('unrelated native files are never delayed by an armed gate', () async {
    final selected = File('${root.path}/selected.part');
    final other = File('${root.path}/other.part');
    final gate = NativeFileIoGate()..armWrite(selected.path);
    await IOOverrides.runWithIOOverrides(() async {
      final handle = await File(other.path).open(mode: FileMode.write);
      try {
        await handle.writeFrom([9, 8, 7]).timeout(const Duration(seconds: 1));
      } finally {
        await handle.close();
      }
      expect(gate.snapshot()['claimed'], isFalse);
      expect(gate.snapshot()['valid'], isTrue);
      expect(gate.snapshot()['all_wrapped_handles'], 0);
    }, gate);
    expect(await other.readAsBytes(), [9, 8, 7]);
    expect(await selected.exists(), isFalse);
  });

  test(
    'native open failure reaches the caller without a fabricated owner',
    () async {
      final missing = File('${root.path}/missing.apk');
      final gate = NativeFileIoGate()..armRead(missing.path);
      await IOOverrides.runWithIOOverrides(() async {
        await expectLater(
          File(missing.path).openRead(0, 1).drain<void>(),
          throwsA(isA<FileSystemException>()),
        );
        expect(gate.snapshot()['valid'], isFalse);
        expect(gate.snapshot()['all_wrapped_handles'], 0);
        expect(gate.snapshot()['pending_operations'], 0);
      }, gate);
    },
  );
}
