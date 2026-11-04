import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mesting_music/shared/media/persistent_network_image_cache.dart';

void main() {
  test(
    'image startup removes only its own interrupted download staging file',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'mesting-cover-interrupted-126-',
      );
      addTearDown(() => root.delete(recursive: true));
      final folder = await Directory(
        '${root.path}/mesting_network_image_cache',
      ).create();
      final unfinished = File('${folder.path}/${'a' * 64}.avatar.1234567.tmp');
      final unrelated = File('${folder.path}/unrelated.tmp');
      await unfinished.writeAsString('unfinished');
      await unrelated.writeAsString('keep');
      await PersistentNetworkImageCache(
        directoryProvider: () async => root,
      ).initialize();
      expect(await unfinished.exists(), isFalse);
      expect(await unrelated.exists(), isTrue);
    },
  );
  test('startup index exposes a saved cover before another request', () async {
    final root = await Directory.systemTemp.createTemp('mesting-cover-126-');
    addTearDown(() => root.delete(recursive: true));
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response.bytes([0xff, 0xd8, 0xff, 0], 200);
    });
    final first = PersistentNetworkImageCache(
      client: client,
      directoryProvider: () async => root,
    );
    await first.resolve(
      cacheKey: 'public-artwork-v1',
      url: 'https://cdn.example/cover?id=1',
    );
    final restarted = PersistentNetworkImageCache(
      client: client,
      directoryProvider: () async => root,
    );
    await restarted.initialize();
    expect(
      restarted.peek(
        cacheKey: 'public-artwork-v1',
        url: 'https://cdn.example/cover?id=1',
      ),
      isNotNull,
    );
    expect(calls, 1);
    expect(
      restarted.peek(
        cacheKey: 'public-artwork-v1',
        url: 'https://cdn.example/cover?id=2',
      ),
      isNull,
    );
  });
  test(
    'cover cache capacity is bounded and semantic versions remain distinct',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'mesting-cover-capacity-126-',
      );
      addTearDown(() => root.delete(recursive: true));
      final cache = PersistentNetworkImageCache(
        client: MockClient(
          (_) async => http.Response.bytes([0xff, 0xd8, 0xff, 0], 200),
        ),
        directoryProvider: () async => root,
        maxFiles: 2,
        maxBytes: 8,
      );
      for (var version = 1; version <= 3; version++) {
        await cache.resolve(
          cacheKey: 'cover',
          url: 'https://cdn.example/cover?version=$version',
        );
      }
      expect(
        cache.peek(
          cacheKey: 'cover',
          url: 'https://cdn.example/cover?version=1',
        ),
        isNull,
      );
      expect(
        cache.peek(
          cacheKey: 'cover',
          url: 'https://cdn.example/cover?version=3',
        ),
        isNotNull,
      );
      final files = await Directory(
        '${root.path}/mesting_network_image_cache',
      ).list().toList();
      expect(files.where((f) => f.path.endsWith('.avatar')).length, 2);
    },
  );
  test(
    'persists a social avatar and reuses it after a signed URL refresh',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'mesting-network-image-cache-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount += 1;
        return http.Response.bytes(const <int>[0xFF, 0xD8, 0xFF, 0x00], 200);
      });
      final firstCache = PersistentNetworkImageCache(
        client: client,
        directoryProvider: () async => root,
      );

      final first = await firstCache.resolve(
        cacheKey: 'social-avatar-friend-1',
        url: 'https://cdn.example/avatars/friend-1.jpg?sign=first',
      );

      expect(first, isNotNull);
      expect(await first!.exists(), isTrue);
      expect(requestCount, 1);

      final restartedCache = PersistentNetworkImageCache(
        client: client,
        directoryProvider: () async => root,
      );
      final later = await restartedCache.resolve(
        cacheKey: 'social-avatar-friend-1',
        url: 'https://cdn.example/avatars/friend-1.jpg?sign=renewed',
      );

      expect(later, isNotNull);
      expect(later!.path, first.path);
      expect(requestCount, 1);
    },
  );

  test('does not persist a response that is not an image', () async {
    final root = await Directory.systemTemp.createTemp(
      'mesting-network-image-cache-test-',
    );
    addTearDown(() => root.delete(recursive: true));
    final cache = PersistentNetworkImageCache(
      client: MockClient((_) async => http.Response.bytes(<int>[1, 2, 3], 200)),
      directoryProvider: () async => root,
    );

    final result = await cache.resolve(
      cacheKey: 'social-avatar-friend-2',
      url: 'https://cdn.example/avatars/friend-2.jpg',
    );

    expect(result, isNull);
    final cacheDirectory = Directory(
      '${root.path}${Platform.pathSeparator}mesting_network_image_cache',
    );
    expect(await cacheDirectory.list().isEmpty, isTrue);
  });
}
