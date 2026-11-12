import '../music_platform/data/platform_comments_repository.dart';
import '../music_platform/netease/netease_comments_repository.dart';

/// A resource alone is insufficient to locate a message's exact comment.
/// NetEase can read its explicit floor owner. Kugou can resolve an exact ID in
/// one bounded page; absent/retired comments return to the message category.
/// No approximate text match or unbounded scan may select another comment.
Future<PlatformComment> resolveNoticeComment(
  PlatformCommentsRepository repository,
  PlatformCommentResource resource,
  String commentId,
) async {
  if (commentId.isEmpty) {
    throw const FormatException('Missing comment target');
  }
  if (repository is NeteaseCommentsRepository) {
    return repository.noticeThread(resource, commentId);
  }
  if (!const {
    PlatformCommentKind.song,
    PlatformCommentKind.playlist,
    PlatformCommentKind.mv,
  }.contains(resource.kind)) {
    throw const FormatException('Unsupported comment resource');
  }
  final page = await repository.load(resource);
  final comment = page.comments.where((row) => row.id == commentId).firstOrNull;
  if (comment == null || comment.specialId.isEmpty) {
    throw const FormatException('Comment no longer locatable');
  }
  return comment;
}
