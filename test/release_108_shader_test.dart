import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';

// Compile the ACTUAL new GLSL helpers alongside the frozen 1.0.7 formula and
// compare rendered pixels. No test-only shaders/assets enter the release APK.
String function(String source, String name) {
  final start = source.indexOf('vec4 $name(');
  if (start < 0) throw StateError('Missing shader function $name');
  var at = source.indexOf('{', start);
  var depth = 1;
  while (depth > 0) {
    at++;
    if (source[at] == '{') depth++;
    if (source[at] == '}') depth--;
  }
  return source.substring(start, at + 1);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'dispersion fast path matches reference pixels across footprints, edges and alpha',
    () async {
      final compiler = File(
        '${File(Platform.resolvedExecutable).parent.path}/impellerc.exe',
      );
      expect(compiler.existsSync(), isTrue);
      final out = Directory(
        '.codex-artifacts/2026-10-28-release108/shader-test',
      )..createSync(recursive: true);
      final source = File(
        'third_party/liquid_glass_widgets/package/shaders/liquid_glass_render.frag',
      ).readAsStringSync();
      const prefix = '''#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec2 uSpread;
uniform vec4 uBackgroundFallback;
uniform sampler2D uBackgroundTexture;
out vec4 fragColor;
''';
      final programs = <String, ui.FragmentProgram>{};
      for (final optimized in [false, true]) {
        final name = optimized ? 'optimized' : 'reference';
        final helpers = optimized
            ? [
                'backdropOverFallback',
                'textureBilinear',
                'textureDispersed',
              ].map((n) => function(source, n)).join('\n')
            : File('test/support/glass_bilinear_107.glsl').readAsStringSync();
        final sample = optimized
            ? 'textureDispersed(uv+d, uv, uv-d, uSize, invSize)'
            : 'vec4(textureBilinear(uv+d,uSize,invSize).r, textureBilinear(uv,uSize,invSize).g, textureBilinear(uv-d,uSize,invSize).b, textureBilinear(uv,uSize,invSize).a)';
        final input = File('${out.path}/$name.frag')
          ..writeAsStringSync(
            '$prefix\n$helpers\nvoid main() { vec2 invSize=1.0/uSize; vec2 uv=(FlutterFragCoord().xy+vec2(.23,.38))*invSize; vec2 d=uSpread*invSize; fragColor=$sample; }',
          );
        final output = File('${out.path}/$name.iplr');
        final result = await Process.run(compiler.path, [
          '--sksl',
          '--runtime-stage-gles',
          '--runtime-stage-gles3',
          '--runtime-stage-vulkan',
          '--iplr',
          '--input=${input.absolute.path}',
          '--sl=${output.absolute.path}',
          '--spirv=${output.absolute.path}.spirv',
          '--input-type=frag',
          '--include=${compiler.parent.path}/shader_lib',
        ]);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        // FragmentProgram resolves native assets, bypassing the Dart asset
        // messenger. Stage ONLY in the test engine's asset directory, never
        // in pubspec or the Android release bundle.
        final staged = File('build/unit_test_assets/$name.iplr');
        staged.writeAsBytesSync(output.readAsBytesSync());
        addTearDown(() {
          if (staged.existsSync()) staged.deleteSync();
        });
        programs[name] = await ui.FragmentProgram.fromAsset('$name.iplr');
      }
      const size = 32;
      final bytes = Uint8List(size * size * 4);
      for (var i = 0; i < size * size; i++) {
        final a = (i * 53) % 256;
        bytes.setRange(i * 4, i * 4 + 4, [
          (i * 17) % (a + 1),
          (i * 97) % (a + 1),
          (i * 11) % (a + 1),
          a,
        ]);
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: size,
        height: size,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final codec = await descriptor.instantiateCodec();
      final image = (await codec.getNextFrame()).image;
      addTearDown(() {
        image.dispose();
        codec.dispose();
        descriptor.dispose();
        buffer.dispose();
      });
      var compared = 0;
      for (final spread in [0.0, .005, .02, .49, .51, 1.1, 5.3]) {
        for (final alpha in [0.0, .5, 1.0]) {
          final rendered = <Uint8List>[];
          for (final program in programs.values) {
            final shader = program.fragmentShader();
            for (final entry in [
              32.0,
              32.0,
              spread,
              spread * .7,
              .1,
              .4,
              .8,
              alpha,
            ].indexed) {
              shader.setFloat(entry.$1, entry.$2);
            }
            shader.setImageSampler(0, image);
            final recorder = ui.PictureRecorder();
            ui.Canvas(recorder).drawRect(
              const ui.Rect.fromLTWH(0, 0, 32, 32),
              ui.Paint()..shader = shader,
            );
            final picture = recorder.endRecording();
            final frame = await picture.toImage(size, size);
            rendered.add(
              (await frame.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!.buffer.asUint8List(),
            );
            frame.dispose();
            picture.dispose();
            shader.dispose();
          }
          var maxDifference = 0;
          for (var i = 0; i < rendered.first.length; i++) {
            final difference = (rendered.first[i] - rendered.last[i]).abs();
            if (difference > maxDifference) maxDifference = difference;
          }
          expect(
            maxDifference,
            lessThanOrEqualTo(1),
            reason: 'spread=$spread alpha=$alpha',
          );
          compared += size * size;
        }
      }
      // ignore: avoid_print
      print(
        'GLASS_SAMPLER_REFERENCE pixels=$compared maxAllowedChannelDifference=1',
      );
    },
  );
}
