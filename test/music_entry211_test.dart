import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/notifications/music_entry_dispatcher.dart';

void main() {
  test(
    'cold entry waits for restoration before navigating and acknowledging',
    () async {
      Map<String, dynamic>? pending = {'id': 'cold', 'action': 'search'};
      final ready = Completer<void>(), started = Completer<void>();
      final routes = <String>[], acks = <String>[];
      final dispatcher = MusicEntryDispatcher(
        peek: () async => pending,
        active: () => true,
        prepare: (entry) async {
          started.complete();
          await ready.future;
          return '/music/search';
        },
        navigate: routes.add,
        acknowledge: (id) async {
          acks.add(id);
          pending = null;
        },
      );
      final run = dispatcher.dispatch();
      await started.future;
      expect(routes, isEmpty);
      expect(acks, isEmpty);
      ready.complete();
      await run;
      expect(routes, ['/music/search']);
      expect(acks, ['cold']);
      expect(pending, isNull);
    },
  );
  test('second warm entry supersedes a pending account restoration', () async {
    Map<String, dynamic>? pending = {'id': 'A'};
    final ready = Completer<void>(), started = Completer<void>();
    final routes = <String>[], acks = <String>[];
    final dispatcher = MusicEntryDispatcher(
      peek: () async => pending,
      active: () => true,
      prepare: (entry) async {
        if (entry['id'] == 'A') {
          started.complete();
          await ready.future;
          return '/music/search';
        }
        return '/music/recognize';
      },
      navigate: routes.add,
      acknowledge: (id) async {
        acks.add(id);
        if (pending?['id'] == id) pending = null;
      },
    );
    final first = dispatcher.dispatch();
    await started.future;
    pending = {'id': 'B'};
    await dispatcher.dispatch();
    ready.complete();
    await first;
    expect(routes, ['/music/recognize']);
    expect(acks, ['B']);
    expect(pending, isNull);
  });
  test('deferred login keeps its entry until the user finishes', () async {
    Map<String, dynamic>? pending = {'id': 'login'};
    var loggedIn = false;
    final routes = <String>[];
    final dispatcher = MusicEntryDispatcher(
      peek: () async => pending,
      active: () => true,
      prepare: (_) async => loggedIn ? '/music/library?view=favorites' : null,
      navigate: routes.add,
      acknowledge: (_) async => pending = null,
    );
    await dispatcher.dispatch();
    expect(pending, isNotNull);
    expect(routes, isEmpty);
    loggedIn = true;
    await dispatcher.dispatch();
    expect(routes, ['/music/library?view=favorites']);
    expect(pending, isNull);
  });
  test(
    'disposed host retains the request instead of acknowledging unseen navigation',
    () async {
      Map<String, dynamic>? pending = {'id': 'dispose'};
      var mounted = true;
      final routes = <String>[];
      final dispatcher = MusicEntryDispatcher(
        peek: () async => pending,
        active: () => mounted,
        prepare: (_) async {
          mounted = false;
          return '/music/search';
        },
        navigate: routes.add,
        acknowledge: (_) async => pending = null,
      );
      await dispatcher.dispatch();
      expect(routes, isEmpty);
      expect(pending, isNotNull);
    },
  );
  test(
    'a request arriving during acknowledgement is drained immediately',
    () async {
      Map<String, dynamic>? pending = {'id': 'A'};
      final routes = <String>[];
      late MusicEntryDispatcher dispatcher;
      dispatcher = MusicEntryDispatcher(
        peek: () async => pending,
        active: () => true,
        prepare: (entry) async => '/music/${entry['id']}',
        navigate: (route) {
          routes.add(route);
          if (route == '/music/A') {
            pending = {'id': 'B'};
            unawaited(dispatcher.dispatch());
          }
        },
        acknowledge: (id) async {
          if (pending?['id'] == id) pending = null;
        },
      );
      await dispatcher.dispatch();
      expect(routes, ['/music/A', '/music/B']);
      expect(pending, isNull);
    },
  );
  test('failed preparation releases the dispatcher for a retry', () async {
    Map<String, dynamic>? pending = {'id': 'retry'};
    var failed = true;
    final routes = <String>[];
    final dispatcher = MusicEntryDispatcher(
      peek: () async => pending,
      active: () => true,
      prepare: (_) async {
        if (failed) throw StateError('restore');
        return '/music/search';
      },
      navigate: routes.add,
      acknowledge: (_) async => pending = null,
    );
    await expectLater(dispatcher.dispatch(), throwsStateError);
    expect(pending, isNotNull);
    failed = false;
    await dispatcher.dispatch();
    expect(routes, ['/music/search']);
  });
}
