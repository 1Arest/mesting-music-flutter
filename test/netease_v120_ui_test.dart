import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/shared/media/persistent_network_image_cache.dart';
import 'package:mesting_music/shared/widgets/artwork_image.dart';

class _BrokenFileCache extends PersistentNetworkImageCache {
  _BrokenFileCache(this.file);
  final File file;
  int invalidations = 0;
  @override
  File? peek({required String cacheKey, required String url}) => file;
  @override
  Future<File?> resolve({
    required String cacheKey,
    required String url,
  }) async => file;
  @override
  Future<void> invalidate({
    required String cacheKey,
    required String url,
  }) async {
    invalidations++;
  }
}

class _ImageClient extends Fake implements HttpClient {
  _ImageClient(this.bytes);
  final Uint8List bytes;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _ImageRequest(bytes);
}

class _ImageRequest extends Fake implements HttpClientRequest {
  _ImageRequest(this.bytes);
  final Uint8List bytes;
  @override
  Future<HttpClientResponse> close() async => _ImageResponse(bytes);
}

class _ImageResponse extends Fake implements HttpClientResponse {
  _ImageResponse(this.bytes);
  final Uint8List bytes;
  @override
  int get statusCode => 200;
  @override
  int get contentLength => bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

void main() {
  testWidgets(
    'a cached file with a valid header but broken decoder recovers to the network image',
    (tester) async {
      late Uint8List png;
      late Directory folder;
      await tester.runAsync(() async {
        folder = await Directory.systemTemp.createTemp(
          'mesting120-broken-file-',
        );
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 2, 2),
          Paint()..color = Colors.green,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(2, 2);
        png = (await image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
        image.dispose();
        picture.dispose();
      });
      addTearDown(() async {
        await folder.delete(recursive: true);
        debugNetworkImageHttpClientProvider = null;
      });
      final file = File('${folder.path}/cached.avatar');
      await tester.runAsync(() => file.writeAsBytes([255, 216, 255, 0]));
      final cache = _BrokenFileCache(file);
      debugNetworkImageHttpClientProvider = () => _ImageClient(png);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: ArtworkImage(
              uri: 'https://cdn.example/decoded.png',
              width: 64,
              height: 64,
              retryOnNetworkError: true,
              persistentNetworkCacheKey: 'playlist',
              networkImageCache: cache,
            ),
          ),
        );
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 80));
          await tester.pump();
        }
      });
      expect(cache.invalidations, greaterThan(0));
      expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
      expect(find.byIcon(Icons.album_rounded), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      debugNetworkImageHttpClientProvider = null;
    },
  );
}
