import '../../../shared/utils/media_uri.dart';
import 'music_platform_api.dart';

enum MusicEffectsCatalog { community, earphone, artist }

class MusicSoundEffect {
  const MusicSoundEffect({
    required this.id,
    required this.name,
    required this.preset,
    this.author = '',
    this.cover = '',
    this.category = '',
    this.description = '',
  });
  final String id, name, preset, author, cover, category, description;

  /// md3Music v6.1.0 applies free catalogue items through a documented native
  /// EQ preset mapping; an IRS/VPF convolution engine is not claimed here.
  static MusicSoundEffect? parse(Object? raw) {
    if (raw is! Map) return null;
    final nested = raw['sound'] is Map ? raw['sound'] as Map : const {};
    String text(String key) {
      final value = raw[key];
      if (value is String || value is num) return '$value'.trim();
      final inner = nested[key];
      return inner is String || inner is num ? '$inner'.trim() : '';
    }

    final id = text('id').isNotEmpty
        ? text('id')
        : text('model_id').isNotEmpty
        ? text('model_id')
        : text('brand_id');
    final name = text('name').isNotEmpty ? text('name') : text('model');
    final sound = text('sound');
    final privilege = int.tryParse(text('privilege'));
    if (id.isEmpty ||
        id == '0' ||
        name.isEmpty ||
        sound.isEmpty ||
        (privilege != null && privilege != 0) ||
        text('is_unlocked') == '0') {
      return null;
    }
    final labels = raw['label'] is List ? (raw['label'] as List).join(' ') : '';
    final category = text('tag_name');
    final description = text('intro');
    final preset = presetFor('$name $labels $description $category');
    return MusicSoundEffect(
      id: id,
      name: name,
      preset: preset,
      author: text('author').isNotEmpty ? text('author') : text('brand_name'),
      category: category,
      description: description,
      // Community/artist return icon_url; headphone models use model_icon.
      // Some catalogues carry only their playlist artwork. Select the first
      // valid real URL, rather than allowing an empty/identifier field to mask
      // a later image, and share the same transport normalization as the widget.
      cover: firstArtworkUri([
        text('icon_url'),
        text('model_icon'),
        text('logo'),
        text('playlist_v20_icon'),
        text('playlist_on_icon'),
        text('playlist_off_icon'),
      ]),
    );
  }

  static String presetFor(String text) {
    final lower = text.toLowerCase();
    if (['重低音', '低音炮', 'bass'].any(lower.contains)) return '重低音';
    if (['人声', '女声', '男声', 'vocal'].any(lower.contains)) return '人声';
    if (['电音', '电子', 'dj'].any(lower.contains)) return '电子';
    if (['摇滚', 'rock'].any(lower.contains)) return '摇滚';
    if (['高音', '解析', 'hifi', '清晰', '人耳'].any(lower.contains)) return '高音增强';
    if (['环绕', '3d', '现场', '影院', '声场', '趣味'].any(lower.contains)) return '电子';
    return '流行';
  }
}

class MusicEffectBrand {
  const MusicEffectBrand(this.id, this.name);
  final String id, name;
}

class MusicEffectsPage {
  const MusicEffectsPage(this.items, this.hasMore);
  final List<MusicSoundEffect> items;
  final bool hasMore;
}

class PlatformEffectsRepository {
  const PlatformEffectsRepository(this.api);
  final MusicPlatformApi api;
  static List<Object?> rows(Map<String, dynamic> payload) {
    final data = payload['data'];
    if (data is List) return data;
    if (data is Map) {
      for (final key in ['list', 'items', 'info']) {
        if (data[key] is List) return data[key] as List;
      }
    }
    return const [];
  }

  Future<List<MusicEffectBrand>> brands() async {
    final response = await api.get(
      '/effects/brand',
      query: const {'page': '1', 'pagesize': '100'},
    );
    return rows(response)
        .whereType<Map>()
        .where((row) => '${row['id'] ?? row['brand_id'] ?? ''}'.isNotEmpty)
        .map(
          (row) => MusicEffectBrand(
            '${row['id'] ?? row['brand_id']}',
            '${row['name'] ?? row['brand_name'] ?? ''}',
          ),
        )
        .where((b) => b.name.isNotEmpty)
        .toList();
  }

  Future<MusicEffectsPage> list(
    MusicEffectsCatalog catalog, {
    int page = 1,
    String? brandId,
    bool newest = false,
  }) async {
    final session = api.session;
    final path = switch (catalog) {
      MusicEffectsCatalog.community => '/get/model',
      MusicEffectsCatalog.artist => '/effects/artist',
      MusicEffectsCatalog.earphone =>
        brandId == null ? '/effects/match' : '/effects/brand/detail',
    };
    final response = await api.get(
      path,
      expectedSession: session,
      query: {
        'page': '$page',
        'pagesize': '30',
        if (catalog == MusicEffectsCatalog.community)
          'sort': newest ? '4' : '3',
        'brand_id': ?brandId,
      },
    );
    var raw = rows(response);
    if (catalog == MusicEffectsCatalog.earphone && brandId == null) {
      final data = MusicPlatformApi.objectMap(response['data']);
      raw = [
        for (final key in ['common', 'earphone', 'brand'])
          if (data[key] != null) data[key],
        ...raw,
      ];
    }
    final known = <String>{};
    final items = raw
        .map(MusicSoundEffect.parse)
        .whereType<MusicSoundEffect>()
        .where((item) => known.add(item.id))
        .toList();
    return MusicEffectsPage(
      items,
      raw.length >= 30 &&
          !(catalog == MusicEffectsCatalog.earphone && brandId == null),
    );
  }
}
