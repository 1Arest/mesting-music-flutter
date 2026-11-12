import '../../../../shared/widgets/beta_content_insets.dart';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/widgets/artwork_image.dart';
import '../../../../shared/widgets/beta_glass_controls.dart';
import '../../../../shared/widgets/beta_bottom_search.dart';
import '../../../../shared/widgets/beta_page_search_layout.dart';
import '../../music_platform_providers.dart';
import '../../platform_backend_providers.dart';
import '../../presentation/platform_design.dart';
import '../netease_music_repository.dart';
import 'netease_manual_routes.dart';

class NeteasePickedEntity {
  const NeteasePickedEntity(this.id, this.name, [this.raw = const {}]);
  final String id, name;
  final Map<String, dynamic> raw;
}

String neteaseEntityLabel(String kind) =>
    const {
      'song': '歌曲',
      'playlist': '歌单',
      'album': '专辑',
      'artist': '歌手',
      'user': '朋友',
      'mv': 'MV',
      'podcast': '播客',
      'program': '节目',
      'style': '曲风',
      'event': '动态',
      'yunbeiTask': '云贝任务',
      'vipTask': '会员任务',
      'musicianTask': '音乐人任务',
      'cloudSong': '云盘歌曲',
      'video': '视频',
      'radio': '电台',
      'podcastCategory': '播客分类',
      'topic': '话题',
    }[kind] ??
    '内容';

/// IDs remain an advanced option in task forms, but normal users can choose a
/// real song, collection or person. The picker returns an ID only; it neither
/// changes playback nor writes account data.
class NeteaseEntityPicker extends ConsumerStatefulWidget {
  const NeteaseEntityPicker({
    required this.kind,
    this.includeDetails = false,
    super.key,
  });
  final String kind;
  final bool includeDetails;
  @override
  ConsumerState<NeteaseEntityPicker> createState() =>
      _NeteaseEntityPickerState();
}

class _NeteaseEntityPickerState extends ConsumerState<NeteaseEntityPicker> {
  late final _bottomSearch = BetaPageSearchController(
    hintText: '搜索并选择内容',
    onSubmitted: (_) => _load(),
    onCleared: _clear,
  );
  TextEditingController get _search => _bottomSearch.text;
  void _clear() {
    _epoch++;
    if (mounted) {
      setState(() {
        _rows.clear();
        _error = null;
        _busy = false;
        _more = false;
        _page = 0;
      });
    }
  }

  final _rows = <Map<String, dynamic>>[];
  String? _owner, _token, _error;
  bool _busy = false;
  int _epoch = 0, _page = 0;
  bool _more = false;
  bool get _onlineSearch => {
    'song',
    'playlist',
    'album',
    'artist',
    'user',
    'mv',
    'podcast',
    'video',
  }.contains(widget.kind);
  bool get _current =>
      ref.read(usesNeteaseProvider) &&
      ref.read(platformAccountProvider).value?.ownerId == _owner &&
      ref.read(platformAccountProvider).value?.token == _token;
  @override
  void initState() {
    super.initState();
    final account = ref.read(platformAccountProvider).value;
    _owner = account?.ownerId;
    _token = account?.token;
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _epoch++;
    _bottomSearch.dispose();
    super.dispose();
  }

  Future<void> _load({bool next = false}) async {
    if (_busy || !_current) return;
    final epoch = ++_epoch;
    final page = next ? _page : 0;
    setState(() {
      _busy = true;
      _error = null;
      if (!next) _rows.clear();
    });
    try {
      final music = ref.read(neteaseMusicRepositoryProvider);
      final searching = _search.text.trim().isNotEmpty && _onlineSearch;
      final (type, field) = switch (widget.kind) {
        'playlist' => (1000, 'playlists'),
        'album' => (10, 'albums'),
        'artist' => (100, 'artists'),
        'user' => (1002, 'userprofiles'),
        'mv' => (1004, 'mvs'),
        'podcast' => (1009, 'djRadios'),
        'video' => (1014, 'videos'),
        _ => (1, 'songs'),
      };
      final (route, fields) = switch (widget.kind) {
        'playlist' => ('/user/playlist', ['playlist']),
        'album' => ('/album/sublist', ['data']),
        'artist' => ('/artist/sublist', ['data']),
        'user' => ('/user/follows', ['follow']),
        'mv' => ('/mv/first', ['data']),
        'podcast' => ('/dj/sublist', ['djRadios']),
        'radio' => ('/dj/sublist', ['djRadios']),
        'video' => ('/video/timeline/recommend', ['datas']),
        'program' => ('/program/recommend', ['programs']),
        'style' => ('/style/list', ['data']),
        'topic' => ('/hot/topic', ['hot']),
        'podcastCategory' => ('/dj/catelist', ['categories']),
        'event' => ('/user/event', ['events']),
        'yunbeiTask' => ('/yunbei/tasks/todo', ['data']),
        'vipTask' => ('/vip/tasks', ['data']),
        'musicianTask' => ('/musician/tasks/new', ['data']),
        'cloudSong' => ('/user/cloud', ['data']),
        _ => ('/recommend/songs', ['data', 'dailySongs']),
      };
      final query = <String, Object?>{
        'uid': music.api.session!.userId,
        'limit': 30,
        'offset': page * 30,
      };
      late Map<String, dynamic> payload;
      if (searching) {
        payload = await music.call('/search', {
          'keywords': _search.text.trim(),
          'type': type,
          'offset': page * 30,
        });
      } else {
        final c = neteaseCompleteContract(route, query);
        payload = c == null
            ? await music.call(route, query)
            : await music.api.request(
                c.path,
                c.data,
                weapi: c.weapi,
                expectedCredential: music.credential,
              );
      }
      if (!mounted || epoch != _epoch || !_current) return;
      Object? data = searching
          ? NeteaseMusicRepository.object(payload['result'])[field]
          : payload;
      if (!searching) {
        for (final key in fields) {
          data = NeteaseMusicRepository.object(data)[key];
        }
      }
      final rows = <Map<String, dynamic>>[];
      void collect(Object? value) {
        if (value is List) {
          for (final item in value) {
            collect(item);
          }
          return;
        }
        if (value is! Map) return;
        var row = Map<String, dynamic>.from(value);
        if (row['data'] is Map) {
          row = {...row, ...NeteaseMusicRepository.object(row['data'])};
        }
        if (row['json'] is String) {
          try {
            final event = NeteaseMusicRepository.object(
              jsonDecode('${row['json']}'),
            );
            row['name'] ??= event['msg'];
          } catch (_) {
            /* ordinary text */
          }
        }
        final raw = NeteaseMusicRepository.object(
          row['simpleSong'] ?? row['program'],
        );
        final id =
            row['id'] ??
            row['userId'] ??
            row['tagId'] ??
            row['actId'] ??
            row['actid'] ??
            row['vid'] ??
            row['userTaskId'] ??
            row['taskId'];
        final name =
            row['name'] ??
            row['nickname'] ??
            row['tagName'] ??
            row['taskName'] ??
            row['title'] ??
            raw['name'];
        if (id != null && name != null) {
          rows.add({...row, 'id': id, 'name': name});
        }
        for (final key in [
          'children',
          'tags',
          'tasks',
          'taskList',
          'list',
          'data',
          'unGet',
          'get',
        ]) {
          if (row[key] is List || row[key] is Map) collect(row[key]);
        }
      }

      collect(data);
      setState(() {
        final ids = _rows.map((r) => '${r['id'] ?? r['userId']}').toSet();
        _rows.addAll(rows.where((r) => ids.add('${r['id'] ?? r['userId']}')));
        _page = page + 1;
        _more = rows.length >= 30;
      });
    } catch (_) {
      if (mounted && epoch == _epoch && _current) {
        setState(() => _error = '搜索未完成，请重试');
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(platformAccountProvider);
    final label = neteaseEntityLabel(widget.kind);
    final visible = _onlineSearch
        ? _rows
        : _rows
              .where(
                (r) => '${r['name'] ?? r['nickname']}'.toLowerCase().contains(
                  _search.text.trim().toLowerCase(),
                ),
              )
              .toList();
    return BetaPageSearchLayout(
      controller: _bottomSearch,
      child: PlatformPageFrame(
        title: '选择$label',
        child: !_current
            ? const Center(child: Text('账号已变化，请返回'))
            : Column(
                children: [
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.all(14),
                      child: BetaActivityIndicator(),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_error!),
                    ),
                  Expanded(
                    child: ListView.builder(
                      padding: BetaContentInsets.musicPaddingOf(
                        context,
                        const EdgeInsets.only(bottom: 30),
                      ),
                      itemCount: visible.length + 1,
                      itemBuilder: (context, index) {
                        if (index == visible.length) {
                          return _more
                              ? Padding(
                                  padding: const EdgeInsets.all(22),
                                  child: BetaGlassButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _load(next: true),
                                    child: const Text('加载更多'),
                                  ),
                                )
                              : _rows.isEmpty && !_busy
                              ? const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text('输入名称，选择要操作的内容'),
                                )
                              : const SizedBox.shrink();
                        }
                        if (index >= visible.length) {
                          return const SizedBox.shrink();
                        }
                        final row = visible[index];
                        final album = NeteaseMusicRepository.object(
                          row['al'] ?? row['album'],
                        );
                        final creators = NeteaseMusicRepository.rows(
                          row['ar'] ?? row['artists'],
                        );
                        final creator = NeteaseMusicRepository.object(
                          row['creator'] ?? row['artist'],
                        );
                        final subtitle = creators.isNotEmpty
                            ? creators.map((a) => a['name']).join(' / ')
                            : '${creator['nickname'] ?? creator['name'] ?? row['signature'] ?? ''}';
                        final cover =
                            '${row['coverImgUrl'] ?? row['avatarUrl'] ?? row['picUrl'] ?? album['picUrl'] ?? ''}';
                        return ListTile(
                          leading: cover.isEmpty
                              ? const Icon(CupertinoIcons.music_note)
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: ArtworkImage(
                                    uri: cover,
                                    width: 48,
                                    height: 48,
                                  ),
                                ),
                          title: Text(
                            '${row['name'] ?? row['nickname'] ?? ''}',
                          ),
                          subtitle: subtitle.isEmpty ? null : Text(subtitle),
                          onTap: () => Navigator.pop(
                            context,
                            widget.includeDetails
                                ? NeteasePickedEntity(
                                    '${row['id'] ?? row['userId']}',
                                    '${row['name'] ?? row['nickname'] ?? '已选内容'}',
                                    row,
                                  )
                                : '${row['id'] ?? row['userId']}',
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
