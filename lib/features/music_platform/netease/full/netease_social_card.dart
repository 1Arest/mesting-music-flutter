import 'package:flutter/material.dart';
import '../../../../shared/widgets/artwork_image.dart';
import '../../../../shared/models/track.dart';
import '../netease_music_repository.dart';
import 'netease_content.dart';

String neteaseDisplayTime(Object? value) {
  final stamp = int.tryParse('$value');
  if (stamp == null || stamp <= 0 || stamp > 8640000000000000) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(
    stamp < 100000000000 ? stamp * 1000 : stamp,
  );
  String pad(int n) => '$n'.padLeft(2, '0');
  return '${date.year}-${pad(date.month)}-${pad(date.day)} ${pad(date.hour)}:${pad(date.minute)}';
}

/// A shared, finite presentation for comments, events and message-like rows.
/// Protocol cursors never appear as labels; all counters below are returned
/// values, and optional media is shown only when actually present.
class NeteaseSocialCard extends StatelessWidget {
  const NeteaseSocialCard({
    required this.row,
    this.onOpen,
    this.onPlay,
    this.onAuthor,
    this.expanded = false,
    super.key,
  });
  final NeteaseContentRow row;
  final VoidCallback? onOpen, onAuthor;
  final ValueChanged<Track>? onPlay;
  final bool expanded;
  @override
  Widget build(BuildContext context) {
    final raw = row.raw;
    final user = NeteaseMusicRepository.object(raw['user'] ?? raw['fromUser']);
    final info = NeteaseMusicRepository.object(raw['info']);
    final author = '${user['nickname'] ?? user['name'] ?? ''}';
    final avatar = '${user['avatarUrl'] ?? ''}';
    final time = neteaseDisplayTime(
      raw['time'] ?? raw['eventTime'] ?? raw['showTime'],
    );
    final body = '${raw['content'] ?? raw['msg'] ?? raw['text'] ?? row.title}';
    final replies = NeteaseMusicRepository.rows(raw['beReplied']);
    final song = NeteaseMusicRepository.object(raw['song']);
    final track = song['id'] == null
        ? null
        : NeteaseMusicRepository.track(song);
    final pictures = NeteaseMusicRepository.rows(raw['pics'])
        .map((p) => '${p['squareUrl'] ?? p['originUrl'] ?? p['url'] ?? ''}')
        .where((p) => Uri.tryParse(p)?.hasScheme == true)
        .take(9)
        .toList();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: ValueKey('netease-social-${row.identity}'),
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (avatar.isNotEmpty)
                ClipOval(
                  child: ArtworkImage(uri: avatar, width: 40, height: 40),
                )
              else
                Icon(
                  row.kind == 'event'
                      ? Icons.person_outline
                      : Icons.chat_bubble_outline,
                  size: 28,
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        alignment: Alignment.centerLeft,
                      ),
                      onPressed: onAuthor,
                      child: Text(
                        author.isEmpty
                            ? (row.kind == 'event' ? '用户动态' : '历史评论')
                            : author,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    if (time.isNotEmpty)
                      Text(time, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            maxLines: expanded ? null : 8,
            overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(height: 1.55),
          ),
          if (replies.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${NeteaseMusicRepository.object(replies.first['user'])['nickname'] ?? '回复'}：${replies.first['content'] ?? ''}',
              ),
            ),
          if (pictures.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final picture in pictures)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: ArtworkImage(uri: picture, width: 88, height: 88),
                    ),
                ],
              ),
            ),
          if (track != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.music_note_outlined),
              title: Text(track.title),
              subtitle: Text(track.artist),
              trailing: const Icon(Icons.play_circle_outline),
              onTap: onPlay == null ? null : () => onPlay!(track),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              if ((raw['likedCount'] ?? info['likedCount']) is num)
                Text('赞 ${raw['likedCount'] ?? info['likedCount']}'),
              if ((raw['commentCount'] ?? info['commentCount']) is num)
                Text('评论 ${raw['commentCount'] ?? info['commentCount']}'),
              if (onOpen != null)
                TextButton(
                  onPressed: onOpen,
                  child: Text(row.kind == 'event' ? '查看动态' : '查看评论'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(color: scheme.outlineVariant),
        ],
      ),
    );
  }
}
