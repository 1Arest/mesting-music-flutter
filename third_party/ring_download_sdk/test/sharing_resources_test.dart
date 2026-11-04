import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ring_download_sdk/src/sdk/sharing_resources.dart';

Map<String, Object?> facts({
  int battery = 43,
  int temperature = 286,
  bool powerSave = false,
  bool healthy = true,
  int thermal = 0,
  String network = 'wifi_unmetered',
  bool observing = true,
}) => {
  'observing': observing,
  'network': network,
  'battery_percent': battery,
  'temperature_deci_c': temperature,
  'battery_healthy': healthy,
  'power_save': powerSave,
  'thermal_status': thermal,
  'thermal_supported': true,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late StreamController<dynamic> resourceEvents, networkEvents;
  late RingSharingResourcesOwner owner;
  late Map<String, Object?> current;
  late List<bool> changes;
  Future<Object?> Function()? read;
  var reads = 0;
  setUp(() {
    resourceEvents = StreamController<dynamic>.broadcast(sync: true);
    networkEvents = StreamController<dynamic>.broadcast(sync: true);
    current = facts();
    changes = [];
    reads = 0;
    read = null;
    owner = RingSharingResourcesOwner(
      onAllowedChanged: changes.add,
      read: () {
        reads++;
        return read == null ? Future.value(current) : read!();
      },
      resourceEvents: resourceEvents.stream,
      networkEvents: networkEvents.stream,
      pollEvery: const Duration(milliseconds: 30),
    );
  });
  tearDown(() async {
    await owner.close();
    await resourceEvents.close();
    await networkEvents.close();
  });

  test(
    'observations require consent and foreground and pause synchronously',
    () async {
      await Future<void>.delayed(Duration.zero);
      expect(reads, 0);
      owner.setForeground(false);
      owner.setEnabled(true);
      expect(await owner.ensureCurrent(), false);
      expect(reads, 0);
      owner.setForeground(true);
      expect(await owner.ensureCurrent(), true);
      expect(resourceEvents.hasListener, true);
      owner.setForeground(false);
      expect(owner.allowed, false);
      expect(changes.last, false);
      final atPause = reads;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(reads, atPause);
      expect(resourceEvents.hasListener, false);
    },
  );

  test('battery and temperature recover with bounded hysteresis', () async {
    owner.setEnabled(true);
    expect(await owner.ensureCurrent(), true);
    current = facts(battery: 29);
    resourceEvents.add(current);
    expect(owner.allowed, false);
    current = facts(battery: 31);
    resourceEvents.add(current);
    expect(owner.allowed, false);
    current = facts(battery: 32);
    resourceEvents.add(current);
    expect(owner.allowed, true);
    current = facts(temperature: 400);
    resourceEvents.add(current);
    expect(owner.allowed, false);
    current = facts(temperature: 390);
    resourceEvents.add(current);
    expect(owner.allowed, false);
    current = facts(temperature: 380);
    resourceEvents.add(current);
    expect(owner.allowed, true);
  });

  test(
    'power saver unhealthy battery and system thermal state stop admission',
    () async {
      owner.setEnabled(true);
      expect(await owner.ensureCurrent(), true);
      for (final bad in [
        facts(powerSave: true),
        facts(healthy: false),
        facts(thermal: 2),
        facts(observing: false),
      ]) {
        current = bad;
        resourceEvents.add(current);
        expect(owner.allowed, false);
        current = facts();
        resourceEvents.add(current);
        expect(owner.allowed, true);
      }
    },
  );

  test('cellular metered and unknown events never grant sharing', () async {
    owner.setEnabled(true);
    expect(await owner.ensureCurrent(), true);
    for (final value in ['cellular', 'wifi_metered', 'unknown']) {
      networkEvents.add(value);
      expect(owner.allowed, false);
    }
    networkEvents.add('wifi_unmetered');
    expect(owner.allowed, true);
  });

  test('late read cannot overwrite a newer power saver event', () async {
    final gate = Completer<Object?>();
    final entered = Completer<void>();
    read = () {
      if (!entered.isCompleted) {
        entered.complete();
        return gate.future;
      }
      return Future.value(current);
    };
    owner.setEnabled(true);
    await entered.future;
    current = facts(powerSave: true);
    resourceEvents.add(current);
    networkEvents.add('wifi_unmetered');
    gate.complete(facts());
    expect(await owner.ensureCurrent(), false);
    // Any coalesced follow-up also sees the current resource state.
    read = () async => current;
    await owner.refresh();
    expect(owner.allowed, false);
  });

  test('late Wi-Fi read cannot overwrite a newer cellular event', () async {
    owner.setEnabled(true);
    expect(await owner.ensureCurrent(), true);
    await Future<void>.delayed(Duration.zero);
    final gate = Completer<Object?>(), entered = Completer<void>();
    read = () {
      if (!entered.isCompleted) entered.complete();
      return gate.future;
    };
    final refreshing = owner.refresh();
    await entered.future;
    networkEvents.add('cellular');
    gate.complete(facts());
    expect(await refreshing, false);
    expect(owner.allowed, false);
  });

  test('rapid pause and resume do not revive an older generation', () async {
    final gate = Completer<Object?>(), entered = Completer<void>();
    read = () {
      if (!entered.isCompleted) entered.complete();
      return gate.future;
    };
    owner.setEnabled(true);
    await entered.future;
    owner.setForeground(false);
    owner.setForeground(true);
    current = facts(powerSave: true);
    read = () async => current;
    gate.complete(facts());
    expect(await owner.ensureCurrent(), false);
    expect(owner.allowed, false);
  });

  test(
    'closed owner releases subscriptions and performs no background poll',
    () async {
      owner.setEnabled(true);
      expect(await owner.ensureCurrent(), true);
      await owner.close();
      final stoppedAt = reads;
      resourceEvents.add(facts());
      networkEvents.add('wifi_unmetered');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(reads, stoppedAt);
      expect(owner.allowed, false);
      expect(resourceEvents.hasListener, false);
      expect(networkEvents.hasListener, false);
    },
  );

  test('malformed or missing facts never become an upload grant', () {
    for (final value in [
      null,
      {},
      {...facts(), 'battery_percent': '43'},
      {...facts(), 'temperature_deci_c': 0},
      {...facts(), 'thermal_status': 99},
      {...facts(), 'observing': false},
      {...facts(), 'power_save': null},
    ]) {
      expect(RingSharingFacts.parse(value).known, false);
    }
  });
}
