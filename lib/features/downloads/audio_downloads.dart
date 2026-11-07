import '../../core/network/system_music_io_client.dart';
import '../music_platform/netease/netease_track_sources.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../shared/models/track.dart';
import '../../core/persistence/app_preferences.dart';
import 'audio_download_storage.dart';
import 'audio_download_resume.dart';
import '../music_platform/data/music_platform_api.dart';
import '../music_platform/data/embedded_kugou_music_source.dart';
import '../music_platform/domain/platform_session.dart';
import '../music_platform/music_platform_providers.dart';
import '../music_platform/platform_backend_providers.dart';
import '../music_platform/platform_quality_providers.dart';
import '../music_platform/domain/platform_audio_quality.dart';
import '../music_platform/netease/netease_fallback.dart';
import '../search/search_providers.dart';
import 'netease_download_resolver.dart';

enum AudioDownloadPhase {
  queued,
  resolving,
  downloading,
  saving,
  completed,
  failed,
  cancelled,
  paused,
  awaitingSource,
}

class AudioDownloadTask {
  const AudioDownloadTask({
    required this.id,
    required this.owner,
    required this.track,
    this.phase = AudioDownloadPhase.queued,
    this.received = 0,
    this.total = 0,
    this.uri = '',
    this.error = '',
    this.requestedQuality,
    this.validator = '',
    this.downloadSource,
  });
  final String id, owner, uri, error;
  final String validator;
  final Track track;
  // Immutable per task; playback preferences may change while it is queued.
  final PlatformAudioQuality? requestedQuality;

  /// Explicit download-only choice; null means official first. Never inherit
  /// the per-song playback selection or persist a temporary signed URL here.
  final NeteaseTrackSource? downloadSource;
  final AudioDownloadPhase phase;
  final int received, total;
  AudioDownloadTask copy({
    Track? track,
    AudioDownloadPhase? phase,
    int? received,
    int? total,
    String? uri,
    String? error,
    String? validator,
    NeteaseTrackSource? downloadSource,
  }) => AudioDownloadTask(
    id: id,
    owner: owner,
    track: track ?? this.track,
    requestedQuality: requestedQuality,
    downloadSource: downloadSource ?? this.downloadSource,
    phase: phase ?? this.phase,
    received: received ?? this.received,
    total: total ?? this.total,
    uri: uri ?? this.uri,
    error: error ?? this.error,
    validator: validator ?? this.validator,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'owner': owner,
    'track': track.toJson(),
    'phase': phase.name,
    'received': received,
    'total': total,
    'uri': uri,
    'error': error,
    'requestedQuality': requestedQuality?.code,
    'validator': validator,
    'downloadSource': downloadSource?.name,
  };
}

/// Detect containers from bytes: some music CDNs label FLAC as audio/mpeg.
/// A JSON/HTML error must never become a successful-looking .mp3 download.
({String extension, String mime})? identifyAudio(List<int> data) {
  if (data.length < 12) return null;
  String at(int start, int end) =>
      String.fromCharCodes(data.sublist(start, end));
  if (at(0, 4) == 'fLaC') return (extension: 'flac', mime: 'audio/flac');
  if (at(0, 3) == 'ID3' || (data[0] == 0xff && data[1] & 0xe0 == 0xe0)) {
    return (extension: 'mp3', mime: 'audio/mpeg');
  }
  if (at(0, 4) == 'OggS') return (extension: 'ogg', mime: 'audio/ogg');
  if (at(0, 4) == 'RIFF' && at(8, 12) == 'WAVE') {
    return (extension: 'wav', mime: 'audio/wav');
  }
  if (at(4, 8) == 'ftyp') return (extension: 'm4a', mime: 'audio/mp4');
  return null;
}

typedef ResolveDownload = Future<String> Function(Track track);
typedef ResolveDownloadMedia = Future<Track> Function(Track track);
typedef ResolveRequestedDownloadMedia =
    Future<Track> Function(Track track, PlatformAudioQuality? quality);
typedef ResolveDownloadTaskMedia =
    Future<Track> Function(AudioDownloadTask task, Future<void> abortTrigger);
typedef PublishDownload =
    Future<String> Function(
      File file,
      Track track,
      String extension,
      String mime,
    );

/// A single bounded streaming worker owns queue/progress/cancellation. The
/// resolver and platform exporter are injected; neither controls audio playback.
class AudioDownloadManager extends ChangeNotifier {
  AudioDownloadManager({
    required this.client,
    this.resolve,
    this.resolveMedia,
    this.resolveRequestedMedia,
    this.resolveTaskMedia,
    required this.publish,
    required this.currentOwner,
    required this.directory,
    required this.persist,
    List<AudioDownloadTask> restored = const [],
  }) : assert(
         [
               resolve,
               resolveMedia,
               resolveRequestedMedia,
               resolveTaskMedia,
             ].where((r) => r != null).length ==
             1,
       ),
       _tasks = [...restored],
       _resume = {
         for (final task in restored)
           if (task.phase == AudioDownloadPhase.paused) task.id,
       };
  final http.Client client;
  // Preserve URL-only embedders while letting typed native sources carry their
  // public CDN headers. Exactly one resolver owns a given download manager.
  final ResolveDownload? resolve;
  final ResolveDownloadMedia? resolveMedia;
  final ResolveRequestedDownloadMedia? resolveRequestedMedia;
  final ResolveDownloadTaskMedia? resolveTaskMedia;
  final PublishDownload publish;
  final String? Function() currentOwner;
  final Future<Directory> Function() directory;
  final Future<void> Function(List<AudioDownloadTask>) persist;
  final List<AudioDownloadTask> _tasks;
  List<AudioDownloadTask> get tasks => List.unmodifiable(_tasks);
  bool restoring = false;
  final _deferredEnqueue = <(String, List<Track>, PlatformAudioQuality?)>[];
  Object? restoreError;
  bool _batching = false, _batchSave = false, _batchChanged = false;

  /// A large persisted directory hydrates before new queued writes are allowed
  /// to replace it. New requests retain their owner and are cancelled on login
  /// changes, just like active transfers.
  Future<void> restoreSnapshot(Future<List<AudioDownloadTask>> snapshot) async {
    restoring = true;
    _notify();
    try {
      final restored = await snapshot;
      if (_disposed) return;
      final known = _tasks.map((task) => task.id).toSet();
      _tasks.insertAll(0, restored.where((task) => known.add(task.id)));
      _resume.addAll(
        restored
            .where((task) => task.phase == AudioDownloadPhase.paused)
            .map((task) => task.id),
      );
    } catch (failure) {
      restoreError = failure;
    } finally {
      if (!_disposed) {
        restoring = false;
        _notify();
        final deferred = _deferredEnqueue.toList();
        _deferredEnqueue.clear();
        for (final request in deferred) {
          if (restoreError == null && request.$1 == currentOwner()) {
            enqueueAll(request.$2, quality: request.$3);
          }
        }
      }
    }
  }

  /// Structural listeners do not receive byte-progress ticks. Rows subscribe
  /// by task ID; account-scoped badges reuse one completed-ID index.
  final collectionChanges = ValueNotifier<int>(0);
  final _taskChanges = <String, ValueNotifier<int>>{};
  final _completedIds = <String, Set<String>>{};
  Map<String, AudioDownloadTask>? _byId;
  Map<String, int>? _positions;
  int _indexOf(String id) =>
      (_positions ??= {
        for (final row in _tasks.indexed) row.$2.id: row.$1,
      })[id] ??
      -1;
  Listenable taskChanges(String id) =>
      _taskChanges.putIfAbsent(id, () => ValueNotifier(0));
  AudioDownloadTask? taskById(String id) =>
      (_byId ??= {for (final task in _tasks) task.id: task})[id];
  Set<String> completedTrackIds(String owner) => _completedIds.putIfAbsent(
    owner,
    () => {
      for (final task in _tasks)
        if (task.owner == owner &&
            task.phase == AudioDownloadPhase.completed &&
            task.uri.isNotEmpty)
          task.track.id,
    },
  );
  bool _working = false, _disposed = false;
  String? _active;
  final _attempts = <String, int>{};
  final Set<String> _resume;
  Completer<void>? _abort;
  Future<void> _writes = Future.value();
  void _notify({bool collection = true, String? taskId}) {
    if (_disposed) return;
    if (_batching) {
      _batchChanged = true;
      return;
    }
    if (collection) {
      _byId = null;
      _positions = null;
      _completedIds.clear();
      collectionChanges.value++;
    }
    if (taskId != null) {
      final signal = _taskChanges[taskId];
      if (signal != null) signal.value++;
    }
    notifyListeners();
  }

  void _save() {
    if (_batching) {
      _batchSave = true;
      return;
    }
    final snapshot = List<AudioDownloadTask>.of(_tasks);
    _writes = _writes.catchError((Object _) {}).then((_) => persist(snapshot));
    // Storage errors must not leak into the playback/UI zone as unhandled work.
    unawaited(_writes.catchError((Object _) {}));
  }

  void _replace(AudioDownloadTask task, {bool save = true}) {
    final index = _indexOf(task.id);
    if (index < 0) return;
    final previous = _tasks[index];
    _tasks[index] = task;
    _byId?[task.id] = task;
    if (save) _save();
    _notify(
      collection: previous.phase != task.phase || previous.uri != task.uri,
      taskId: task.id,
    );
  }

  void enqueue(Track track, {PlatformAudioQuality? quality}) =>
      enqueueAll([track], quality: quality);

  void enqueueAll(Iterable<Track> tracks, {PlatformAudioQuality? quality}) {
    final owner = currentOwner();
    if (owner == null) throw const MusicPlatformException('请先登录对应音乐平台');
    if (restoreError != null) {
      throw const MusicPlatformException('下载记录暂时无法读取，请重试后再添加');
    }
    if (restoring) {
      _deferredEnqueue.add((owner, tracks.toList(), quality));
      return;
    }
    final active = {
      for (final t in _tasks)
        if (t.owner == owner &&
            {
              AudioDownloadPhase.queued,
              AudioDownloadPhase.resolving,
              AudioDownloadPhase.downloading,
              AudioDownloadPhase.saving,
              AudioDownloadPhase.paused,
              AudioDownloadPhase.awaitingSource,
            }.contains(t.phase))
          (t.track.id, t.requestedQuality),
    };
    var added = false;
    for (final track in tracks) {
      if (!active.add((track.id, quality))) continue;
      added = true;
      _tasks.add(
        AudioDownloadTask(
          id: '${DateTime.now().microsecondsSinceEpoch}-${_tasks.length}',
          owner: owner,
          track: track,
          requestedQuality: quality,
        ),
      );
    }
    if (!added) return;
    _save();
    _notify();
    unawaited(_pump());
  }

  void cancel(String id) {
    final task = taskById(id) ?? (throw StateError('下载任务不存在'));
    if (task.phase == AudioDownloadPhase.saving ||
        task.phase == AudioDownloadPhase.completed) {
      return;
    }
    _attempts[id] = (_attempts[id] ?? 0) + 1;
    if (_active == id && _abort?.isCompleted == false) _abort!.complete();
    _replace(task.copy(phase: AudioDownloadPhase.cancelled));
    _resume.remove(id);
  }

  /// Pause owns cancellation of the active transfer, while its partial remains
  /// private and unpublished. Its exact flushed length is read when resuming.
  void pause(String id) {
    final task = _tasks.where((t) => t.id == id).firstOrNull;
    if (task == null ||
        task.owner != currentOwner() ||
        !{
          AudioDownloadPhase.downloading,
          AudioDownloadPhase.resolving,
        }.contains(task.phase)) {
      return;
    }
    _resume.add(id);
    _attempts[id] = (_attempts[id] ?? 0) + 1;
    if (_active == id && _abort?.isCompleted == false) _abort!.complete();
    _replace(task.copy(phase: AudioDownloadPhase.paused));
  }

  void resume(String id) {
    final task = _tasks.where((t) => t.id == id).firstOrNull;
    if (task == null ||
        task.owner != currentOwner() ||
        task.phase != AudioDownloadPhase.paused) {
      return;
    }
    _resume.add(id);
    _replace(task.copy(phase: AudioDownloadPhase.queued, error: ''));
    unawaited(_pump());
  }

  /// Removing the task invalidates every late resolver/stream result. Saving
  /// has already entered the system exporter and must finish its atomic publish.
  bool remove(String id) {
    final task = _tasks.where((t) => t.id == id).firstOrNull;
    if (task == null ||
        task.owner != currentOwner() ||
        {
          AudioDownloadPhase.saving,
          AudioDownloadPhase.completed,
        }.contains(task.phase)) {
      return false;
    }
    _attempts[id] = (_attempts[id] ?? 0) + 1;
    if (_active == id && _abort?.isCompleted == false) _abort!.complete();
    _resume.remove(id);
    _tasks.removeWhere((t) => t.id == id);
    _save();
    _notify();
    // The active worker cleans up after closing its sink; idle partials can be
    // removed immediately. The path is generated from our own task identifier.
    if (_active != id) unawaited(_deletePartial(id));
    return true;
  }

  Future<void> _deletePartial(String id) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) return;
    try {
      final root = await directory();
      final file = File('${root.path}/$id.part');
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      /* Temporary storage can be removed externally. */
    }
  }

  void cancelPending() {
    _deferredEnqueue.clear();
    _batching = true;
    try {
      for (final task in List<AudioDownloadTask>.of(_tasks)) {
        if (task.phase == AudioDownloadPhase.queued ||
            task.phase == AudioDownloadPhase.resolving ||
            task.phase == AudioDownloadPhase.downloading ||
            task.phase == AudioDownloadPhase.awaitingSource) {
          cancel(task.id);
        } else if (task.phase == AudioDownloadPhase.saving) {
          // An account token can change without changing ownerId. Invalidate a
          // saving attempt too; its late exporter result cannot claim success.
          _attempts[task.id] = (_attempts[task.id] ?? 0) + 1;
          _replace(
            task.copy(
              phase: AudioDownloadPhase.failed,
              error: '账号已变化，保存结果未写入下载记录',
            ),
          );
        }
      }
    } finally {
      _batching = false;
      if (_batchSave) {
        _batchSave = false;
        _save();
      }
      if (_batchChanged) {
        _batchChanged = false;
        _notify();
      }
    }
  }

  void retry(String id) {
    final task = _tasks.firstWhere((t) => t.id == id);
    if (task.owner != currentOwner() ||
        !{
          AudioDownloadPhase.failed,
          AudioDownloadPhase.cancelled,
        }.contains(task.phase)) {
      return;
    }
    _resume.remove(id);
    _replace(
      task.copy(
        phase: AudioDownloadPhase.queued,
        received: 0,
        total: 0,
        error: '',
      ),
    );
    unawaited(_pump());
  }

  /// Re-enter the queue only after a visible, explicit user choice. Discard
  /// any old partial: bytes from two source identities cannot be concatenated.
  void selectDownloadSource(String id, NeteaseTrackSource source) {
    final task = taskById(id);
    if (task == null ||
        task.owner != currentOwner() ||
        _disposed ||
        task.phase != AudioDownloadPhase.awaitingSource ||
        source == NeteaseTrackSource.automatic) {
      return;
    }
    _resume.remove(id);
    _replace(
      task.copy(
        phase: AudioDownloadPhase.queued,
        received: 0,
        total: 0,
        error: '',
        validator: '',
        downloadSource: source,
      ),
    );
    unawaited(_pump());
  }

  bool _current(AudioDownloadTask task, int attempt) =>
      _attempts[task.id] == attempt &&
      !_disposed &&
      task.owner == currentOwner() &&
      taskById(task.id) != null &&
      taskById(task.id)!.phase != AudioDownloadPhase.cancelled;
  Future<void> _pump() async {
    if (_working || _disposed || restoring) return;
    _working = true;
    try {
      while (!_disposed) {
        final next = _tasks
            .where(
              (t) =>
                  t.phase == AudioDownloadPhase.queued &&
                  t.owner == currentOwner(),
            )
            .firstOrNull;
        if (next == null) break;
        await _download(next);
      }
    } finally {
      _working = false;
    }
  }

  Future<void> _download(AudioDownloadTask task) async {
    // A cancelled task can be retried while its resolver is still unwinding.
    // An attempt token prevents that old result from reviving the new job.
    final attempt = (_attempts[task.id] ?? 0) + 1;
    _attempts[task.id] = attempt;
    _active = task.id;
    _abort = Completer<void>();
    File? partial;
    try {
      _replace(task.copy(phase: AudioDownloadPhase.resolving));
      final resolving = () async {
        return resolveTaskMedia != null
            ? await resolveTaskMedia!(task, _abort!.future)
            : resolveRequestedMedia != null
            ? await resolveRequestedMedia!(task.track, task.requestedQuality)
            : resolveMedia != null
            ? await resolveMedia!(task.track)
            : task.track.copyWith(
                audioAsset: await resolve!(task.track),
                audioHeaders: const {},
              );
      }();
      // Release the single queue worker even when an upstream resolver never
      // completes after pause/delete. A late result cannot revive this attempt.
      final media = await Future.any<Track>([
        resolving,
        _abort!.future.then<Track>(
          (_) => throw const MusicPlatformException('下载已暂停或取消'),
        ),
      ]);
      final url = Uri.parse(media.audioAsset);
      if (!_current(task, attempt)) return;
      if (media.isPreview) throw _sourceError(task, '平台只返回试听片段，未下载');
      if (task.requestedQuality != null &&
          media.playbackQuality != task.requestedQuality!.code) {
        throw _sourceError(task, '平台未返回所选下载音质，请重选音质后下载');
      }
      if (!{'https', 'http'}.contains(url.scheme) ||
          url.host.isEmpty ||
          url.userInfo.isNotEmpty) {
        throw _sourceError(task, '无效音频地址');
      }
      // Resolving may outlive cancellation or an account switch. Recheck before
      // opening a network stream; cancelled jobs must never be resurrected.
      if (!_current(task, attempt)) return;
      task = task.copy(
        track: task.track.copyWith(
          audioOrigin: media.audioOrigin,
          playbackQuality: media.playbackQuality,
          audioBitrate: media.audioBitrate,
        ),
      );
      _replace(task.copy(phase: AudioDownloadPhase.downloading));
      final root = await directory();
      await root.create(recursive: true);
      if (!_current(task, attempt)) return;
      partial = File('${root.path}/${task.id}.part');
      final offset = _resume.contains(task.id) && await partial.exists()
          ? await partial.length()
          : 0;
      if (offset == 0 && task.received > 0 && _resume.contains(task.id)) {
        throw const MusicPlatformException('暂停文件已被清理，请重新下载');
      }
      if (offset > 0 && task.validator.isEmpty) {
        throw const MusicPlatformException('服务器未提供续传校验信息，请重新下载');
      }
      final headers = Map<String, String>.of(
        publicAudioHeaders(media.audioHeaders),
      );
      if (offset > 0) {
        headers['Range'] = 'bytes=$offset-';
        if (task.validator.isNotEmpty) headers['If-Range'] = task.validator;
      }
      final response = await client
          .send(
            http.AbortableRequest('GET', url, abortTrigger: _abort!.future)
              ..headers.addAll(headers),
          )
          .timeout(const Duration(seconds: 20));
      if (offset == 0 && response.statusCode != 200) {
        await response.stream.take(1).drain<void>();
        throw _sourceError(task, '下载地址已失效，请重试');
      }
      if (!_current(task, attempt)) {
        await response.stream.take(1).drain<void>();
        return;
      }
      late final int total;
      try {
        total = offset > 0
            ? resumedDownloadTotal(
                offset: offset,
                status: response.statusCode,
                headers: response.headers,
                validator: task.validator,
              )
            : response.contentLength ?? 0;
      } catch (_) {
        await response.stream.take(1).drain<void>();
        rethrow;
      }
      final responseValidator = downloadValidator(response.headers);
      // A valid If-Range/206 response may omit the validator header. Retain
      // the accepted original validator for a later pause/resume cycle.
      final validator = responseValidator.isEmpty && offset > 0
          ? task.validator
          : responseValidator;
      if (response.statusCode == 416) {
        await response.stream.take(1).drain<void>();
      }
      _replace(
        task.copy(
          phase: AudioDownloadPhase.downloading,
          received: offset,
          total: total,
          validator: validator,
        ),
      );
      if (total > 512 * 1024 * 1024) {
        await response.stream.take(1).drain<void>();
        throw const MusicPlatformException('文件超过 512 MB');
      }
      var received = offset;
      final prefix = offset > 0
          ? await partial.open().then((file) async {
              try {
                return (await file.read(64)).toList(growable: true);
              } finally {
                await file.close();
              }
            })
          : <int>[];
      final output = partial.openWrite(
        mode: offset > 0 ? FileMode.append : FileMode.write,
      );
      final watch = Stopwatch()..start();
      try {
        await for (final chunk
            in (response.statusCode == 416
                    ? const Stream<List<int>>.empty()
                    : response.stream)
                .timeout(const Duration(seconds: 30))) {
          if (!_current(task, attempt)) {
            throw const MusicPlatformException('下载已取消');
          }
          received += chunk.length;
          if (received > 512 * 1024 * 1024) {
            throw const MusicPlatformException('文件超过 512 MB');
          }
          if (prefix.length < 64) {
            prefix.addAll(chunk.take(64 - prefix.length));
          }
          output.add(chunk);
          if (watch.elapsedMilliseconds >= 250) {
            _replace(
              task.copy(
                phase: AudioDownloadPhase.downloading,
                received: received,
                total: total,
                validator: validator,
              ),
              save: false,
            );
            watch.reset();
          }
        }
        await output.flush();
      } finally {
        await output.close();
      }
      if (!_current(task, attempt)) return;
      if (received == 0 || (total > 0 && received != total)) {
        throw _sourceError(task, '文件下载不完整，请重试');
      }
      final format = identifyAudio(prefix);
      if (format == null) throw _sourceError(task, '返回内容不是受支持的音频文件');
      _resume.remove(task.id);
      _replace(
        task.copy(
          phase: AudioDownloadPhase.saving,
          received: received,
          total: received,
        ),
      );
      final uri = await publish(
        partial,
        task.track,
        format.extension,
        format.mime,
      );
      // The platform exporter is asynchronous too. Disposed/account-invalid
      // workers must not publish a late successful-looking history entry.
      if (!_current(task, attempt)) return;
      _replace(
        task.copy(
          phase: AudioDownloadPhase.completed,
          track: task.track.copyWith(
            audioOrigin: media.audioOrigin,
            playbackQuality: media.playbackQuality,
            audioBitrate: media.audioBitrate,
          ),
          received: received,
          total: received,
          uri: uri,
        ),
      );
    } catch (error) {
      if (_current(task, attempt)) {
        final chooseSource =
            error is DownloadSourceSelectionRequired ||
            (task.track.source == TrackSource.netease &&
                taskById(task.id)?.phase == AudioDownloadPhase.downloading &&
                (error is http.ClientException ||
                    error is TimeoutException ||
                    error is HttpException));
        _replace(
          _tasks
              .firstWhere((t) => t.id == task.id)
              .copy(
                phase: chooseSource
                    ? AudioDownloadPhase.awaitingSource
                    : AudioDownloadPhase.failed,
                error: chooseSource && error is! DownloadSourceSelectionRequired
                    ? const DownloadSourceSelectionRequired().toString()
                    : error.toString(),
              ),
        );
      }
    } finally {
      try {
        if (partial != null && await partial.exists()) {
          final retained = _tasks.where((t) => t.id == task.id).firstOrNull;
          if (_resume.contains(task.id) && retained != null) {
            // Read the flushed file rather than the throttled UI byte counter.
            final bytes = await partial.length();
            _replace(retained.copy(received: bytes));
          } else {
            await partial.delete();
          }
        }
      } on FileSystemException {
        // Cleanup races with external storage removal or app shutdown. It must
        // not escape the detached worker or overwrite a confirmed publish.
      }
      _active = null;
      _abort = null;
    }
  }

  Exception _sourceError(AudioDownloadTask task, String message) =>
      task.track.source == TrackSource.netease
      ? DownloadSourceSelectionRequired(message)
      : MusicPlatformException(message);

  @override
  void dispose() {
    _disposed = true;
    if (_abort?.isCompleted == false) _abort!.complete();
    client.close();
    collectionChanges.dispose();
    for (final signal in _taskChanges.values) {
      signal.dispose();
    }
    super.dispose();
  }
}

/// URI-backed playback bypasses platform parsing, even after an app restart.
Track downloadedPlaybackTrack(AudioDownloadTask task) {
  if (task.phase != AudioDownloadPhase.completed || task.uri.isEmpty) {
    throw const MusicPlatformException('歌曲尚未下载完成');
  }
  final uri = Uri.tryParse(task.uri);
  if (uri == null || !{'content', 'file'}.contains(uri.scheme)) {
    throw const MusicPlatformException('下载文件地址不可用，请重新下载');
  }
  return task.track.copyWith(
    audioAsset: task.uri,
    audioHeaders: const {},
    isPreview: false,
  );
}

/// Persisted tasks are one device snapshot, not a frame-time UI operation.
List<AudioDownloadTask> _decodeDownloadSnapshot(String raw) {
  final restored = <AudioDownloadTask>[];
  try {
    final rows = jsonDecode(raw) as List;
    for (final row in rows.whereType<Map>()) {
      final phase = AudioDownloadPhase.values.byName('${row['phase']}');
      restored.add(
        AudioDownloadTask(
          id: '${row['id']}',
          owner: '${row['owner']}',
          track: Track.fromJson(Map<String, Object?>.from(row['track'] as Map)),
          requestedQuality: PlatformAudioQuality.fromCode(
            row['requestedQuality'],
          ),
          phase:
              phase == AudioDownloadPhase.completed ||
                  phase == AudioDownloadPhase.cancelled ||
                  phase == AudioDownloadPhase.paused ||
                  phase == AudioDownloadPhase.awaitingSource
              ? phase
              : AudioDownloadPhase.failed,
          received: row['received'] as int? ?? 0,
          total: row['total'] as int? ?? 0,
          uri: '${row['uri'] ?? ''}',
          validator: '${row['validator'] ?? ''}',
          downloadSource: NeteaseTrackSource.values
              .where((s) => s.name == row['downloadSource'])
              .firstOrNull,
          error: phase == AudioDownloadPhase.completed
              ? ''
              : phase == AudioDownloadPhase.awaitingSource
              ? '请为此任务选择下载音源'
              : '上次下载已中断，可点击重试',
        ),
      );
    }
  } catch (_) {
    /* A corrupt history must not block new downloads. */
  }
  return restored;
}

Future<List<AudioDownloadTask>> decodeAudioDownloadSnapshot(String raw) =>
    raw.length < 128 * 1024
    ? Future.value(_decodeDownloadSnapshot(raw))
    : compute(
        _decodeDownloadSnapshot,
        raw,
        debugLabel: 'download-directory-restore',
      );

String _encodeDownloadSnapshot(List<AudioDownloadTask> tasks) =>
    jsonEncode(tasks.map((task) => task.toJson()).toList());
Future<String> encodeAudioDownloadSnapshot(List<AudioDownloadTask> tasks) =>
    tasks.length < 100
    ? Future.value(_encodeDownloadSnapshot(tasks))
    : compute(
        _encodeDownloadSnapshot,
        tasks,
        debugLabel: 'download-directory-write',
      );

final audioDownloadManagerProvider = Provider<AudioDownloadManager>((ref) {
  final preferences = ref.watch(sharedPreferencesProvider);
  final raw = preferences.getString('audio_download_tasks_v1') ?? '[]';
  final largeSnapshot = raw.length >= 128 * 1024;
  final restored = largeSnapshot
      ? <AudioDownloadTask>[]
      : _decodeDownloadSnapshot(raw);
  final downloadClient = SystemMusicIoClient();
  final manager = AudioDownloadManager(
    client: downloadClient,
    restored: restored,
    currentOwner: () => ref.read(platformAccountProvider).value?.ownerId,
    directory: () async =>
        Directory('${(await getTemporaryDirectory()).path}/audio-downloads'),
    persist: (tasks) async {
      if (!await preferences.setString(
        'audio_download_tasks_v1',
        await encodeAudioDownloadSnapshot(tasks),
      )) {
        throw const MusicPlatformException('下载记录未保存');
      }
    },
    resolveTaskMedia: (task, abortTrigger) async {
      final track = task.track;
      final requested = task.requestedQuality;
      final quality = requested ?? ref.read(platformQualityProvider).preferred;
      if (track.source == TrackSource.netease &&
          ref.read(usesNeteaseProvider)) {
        final music = ref.read(neteaseMusicRepositoryProvider);
        final credential = music.credential;
        var cancelled = false;
        unawaited(abortTrigger.then((_) => cancelled = true));
        bool current() =>
            !cancelled &&
            ref.mounted &&
            ref.read(usesNeteaseProvider) &&
            ref.read(neteaseMusicRepositoryProvider).credential == credential;
        return resolveNeteaseDownload(
          track: track,
          quality: quality,
          current: current,
          selectedSource: task.downloadSource,
          requireQuality: requested != null,
          allowAlternative: ref.read(neteaseFallbackEnabledProvider),
          official: (song, tier) => lookupOfficialNeteaseDownload(
            music,
            song,
            tier,
            client: downloadClient,
            abortTrigger: abortTrigger,
          ),
          alternative: (song, tier, source) => ref
              .read(neteaseFallbackResolverProvider)
              .resolve(
                song.copyWith(playbackQuality: tier.code),
                current: current,
                onlySource: source.adapter,
                requiredQuality: requested?.code,
                abortTrigger: abortTrigger,
              ),
        );
      }
      if (track.source == TrackSource.kugou &&
          ref.read(platformAccountProvider).value?.platform ==
              MusicPlatform.kugou) {
        final source = ref.read(kugouMusicSourceProvider);
        if (source is EmbeddedKugouMusicSource) {
          final resolved = await source.resolveTrack(
            track,
            quality: quality,
            requireRequestedQuality: requested != null,
          );
          if (resolved.isPlayable && !resolved.isPreview) {
            return resolved;
          }
        }
      }
      throw const MusicPlatformException('请使用当前平台的在线歌曲下载');
    },
    publish: const AudioDownloadStorage().publish,
  );
  if (largeSnapshot) {
    unawaited(manager.restoreSnapshot(decodeAudioDownloadSnapshot(raw)));
  }
  ref.listen(platformAccountProvider, (before, after) {
    if (before?.value?.ownerId != after.value?.ownerId ||
        before?.value?.token != after.value?.token) {
      manager.cancelPending();
    }
  });
  ref.onDispose(manager.dispose);
  return manager;
});
