import '../presentation/platform_lazy_list.dart';
import '../../../shared/widgets/beta_content_insets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/beta_glass_controls.dart';
import '../data/platform_comments_repository.dart';
import '../platform_backend_providers.dart';
import '../presentation/platform_design.dart';
import 'netease_comments_repository.dart';
import 'netease_music_repository.dart';
import 'messages/netease_messages_repository.dart';
import 'messages/netease_messages_page.dart';

class NeteaseCommentHugsPage extends ConsumerStatefulWidget {
  const NeteaseCommentHugsPage({
    required this.repository,
    required this.resource,
    required this.comment,
    this.sourceCurrent,
    super.key,
  });
  final NeteaseCommentsRepository repository;
  final PlatformCommentResource resource;
  final PlatformComment comment;
  final bool Function()? sourceCurrent;
  @override
  ConsumerState<NeteaseCommentHugsPage> createState() =>
      _NeteaseCommentHugsPageState();
}

class _NeteaseCommentHugsPageState
    extends ConsumerState<NeteaseCommentHugsPage> {
  final _people = <NeteasePerson>[];
  String? _error;
  String _cursor = '-1', _idCursor = '-1';
  bool _busy = false, _sent = false, _more = false;
  int _page = 1;
  bool get _current =>
      widget.sourceCurrent?.call() ??
      (ref.read(usesNeteaseProvider) &&
          ref.read(neteaseMusicRepositoryProvider).credential ==
              widget.repository.music.credential);
  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load({bool next = false}) async {
    if (_busy || !_current) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.repository.hugs(
        widget.resource,
        widget.comment,
        page: next ? _page : 1,
        cursor: next ? _cursor : '-1',
        idCursor: next ? _idCursor : '-1',
      );
      if (!mounted || !_current) return;
      final data = NeteaseMusicRepository.object(r['data']);
      final rows = NeteaseMusicRepository.rows(
        data['hugUsers'] ?? data['users'] ?? data['list'] ?? data['hugList'],
      );
      setState(() {
        if (!next) _people.clear();
        final ids = _people.map((p) => p.id).toSet();
        _people.addAll(
          rows
              .map((r) => NeteasePerson.parse(r['user'] ?? r))
              .where((p) => ids.add(p.id)),
        );
        _page = next ? _page + 1 : 2;
        _cursor = '${data['cursor'] ?? '-1'}';
        _idCursor = '${data['idCursor'] ?? '-1'}';
        _more = data['hasMore'] == true;
      });
    } catch (e) {
      if (mounted && _current) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _hug() async {
    if (_busy || _sent || !_current) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.hug(widget.resource, widget.comment);
      if (mounted && _current) setState(() => _sent = true);
    } catch (e) {
      if (mounted && _current) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && _sent) await _load();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(usesNeteaseProvider);
    ref.watch(neteaseMusicRepositoryProvider);
    return PlatformPageFrame(
      title: '抱一抱',
      child: !_current
          ? const Center(child: Text('账号已变化，请返回'))
          : buildPlatformLazyList(
              padding: BetaContentInsets.musicPaddingOf(
                context,
                const EdgeInsets.all(22),
              ),
              header: [
                Text(
                  widget.comment.nickname,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                SelectableText(widget.comment.content),
                const SizedBox(height: 20),
                BetaGlassButton(
                  blue: true,
                  loading: _busy,
                  onPressed: _sent ? null : _hug,
                  child: Text(_sent ? '已送出拥抱' : '送一个拥抱'),
                ),
                const SizedBox(height: 24),
                const Text('给过拥抱的人'),
              ],
              itemCount: _people.length,
              itemBuilder: (context, index) {
                final person = _people[index];
                return ListTile(
                  leading: NeteasePersonAvatar(person),
                  title: Text(person.name),
                );
              },
              footer: [
                if (!_busy && _people.isEmpty && _error == null)
                  const Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('暂时没有拥抱记录'),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(_error!),
                  ),
                if (_more)
                  BetaGlassButton(
                    onPressed: _busy ? null : () => _load(next: true),
                    child: const Text('加载更多'),
                  ),
              ],
            ),
    );
  }
}
