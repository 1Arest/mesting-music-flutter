import '../../library/data/library_repository.dart';

/// Shared cloud-playlist operations used by the existing library page. Remote
/// ownership and resource IDs stay inside each platform's repository.
abstract class CloudLibraryRepository extends LibraryRepository {
  CloudLibraryRepository(super.database, {required super.ownerId});
  bool canManage(String id);
  Future<String> commentId(String id);
}
