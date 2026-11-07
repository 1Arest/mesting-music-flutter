import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mesting_music/core/cache/browse_response_cache.dart';
import 'package:mesting_music/core/database/app_database.dart';
import 'package:mesting_music/core/performance/background_json.dart';
import 'package:mesting_music/features/library/library_providers.dart';
import 'package:mesting_music/features/music_platform/discovery_startup_cache.dart';
import 'package:mesting_music/features/music_platform/domain/platform_session.dart';
import 'package:mesting_music/features/music_platform/music_platform_providers.dart';
import 'package:mesting_music/features/music_platform/platform_catalog_providers.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_api.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_browse_providers.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_providers.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_repository.dart';
import 'package:mesting_music/features/music_platform/qishui/qishui_search_catalog.dart';
import 'qishui_signed_api167_test.dart' show account, reply;

class _SodaAccount174 extends PlatformAccountController {
  @override
  Future<PlatformSession?> build() async => account().identity;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'large multilingual snapshot integrity remains compatible with stored UTF8 hashes',
    () async {
      final text = jsonEncode({
        'rows': List.generate(20000, (i) => {'name': '音乐 🎵 $i', 'id': i}),
      });
      expect(text.length, greaterThan(backgroundJsonThreshold));
      expect(
        await digestJsonText(text),
        sha256.convert(utf8.encode(text)).toString(),
      );
      expect(await decodeJsonText(text), isA<Map>());
    },
  );
  test(
    'cached page replacement retains later pages and rejects changed continuation boundaries',
    () {
      final rows = QishuiCatalogAccumulator<String>(keyOf: (s) => s);
      rows.accept(
        QishuiCatalogPage(
          items: ['old'],
          cursor: '0',
          hasMore: true,
          nextCursor: '50',
        ),
      );
      rows.accept(QishuiCatalogPage(items: ['later'], cursor: '50'));
      expect(
        rows.replace(
          QishuiCatalogPage(
            items: ['new'],
            cursor: '0',
            hasMore: true,
            nextCursor: '50',
          ),
        ),
        isTrue,
      );
      expect(rows.items, ['new', 'later']);
      expect(rows.pageCount, 2);
      expect(
        rows.replace(
          QishuiCatalogPage(
            items: ['bad'],
            cursor: '0',
            hasMore: true,
            nextCursor: '100',
          ),
        ),
        isFalse,
      );
      expect(rows.items, ['new', 'later']);
      expect(rows.hasMore, isFalse);
    },
  );
  test(
    'Soda cold hydration uses the same routed provider and starts no legacy platform work',
    () async {
      final dir = await Directory.systemTemp.createTemp('mesting174-startup-');
      BrowseResponseCache cache() => BrowseResponseCache(
        directory: () async => dir,
        initializeOnRead: true,
      );
      final first = QishuiApi(
        MockClient(
          (_) async => reply({
            'playlists': [
              {'id': '7', 'title': '已缓存歌单'},
            ],
          }),
        ),
        browseCache: cache(),
      )..configure(account());
      final watcher = BrowseCacheWatch(() {});
      await watcher.run(() => QishuiRepository(first).discover());
      watcher.dispose();
      first.dispose();
      var network = 0;
      final restored = QishuiApi(
        MockClient((_) async {
          network++;
          return reply({
            'playlists': [
              {'id': '7', 'title': '新歌单'},
            ],
          });
        }),
        browseCache: cache(),
      )..configure(account());
      final db = AppDatabase(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [
          platformAccountProvider.overrideWith(_SodaAccount174.new),
          qishuiApiProvider.overrideWithValue(restored),
          activeLibraryOwnerProvider.overrideWithValue('qishui:owner167'),
          appDatabaseProvider.overrideWithValue(db),
        ],
      );
      final lease = await DiscoveryStartupCache.prepare(container);
      expect(network, 0);
      expect(container.read(qishuiBrowseProvider('discover')).hasValue, isTrue);
      expect(container.exists(platformFeaturedProvider), isFalse);
      expect(container.exists(qishuiBrowseProvider('music')), isFalse);
      lease.dispose();
      container.dispose();
      restored.dispose();
      await db.close();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await dir.delete(recursive: true);
    },
  );
}
