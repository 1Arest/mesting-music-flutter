import 'package:flutter_test/flutter_test.dart';
import 'package:mesting_music/features/lyrics/domain/lrc_parser.dart';

void main() {
  group('LrcParser', () {
    const parser = LrcParser();

    test('解析时间轴、多时间标签与 offset', () {
      final document = parser.parse('''
[ar:测试歌手]
[offset:120]
[00:01.50][00:03.250]第一句
[00:05]第二句
''');

      expect(document.isSynced, isTrue);
      expect(document.lines, hasLength(3));
      expect(document.lines[0].time, const Duration(milliseconds: 1620));
      expect(document.lines[1].time, const Duration(milliseconds: 3370));
      expect(document.lines[2].text, '第二句');
      expect(document.activeIndexAt(const Duration(milliseconds: 4000)), 1);
    });

    test('没有时间标签时降级为普通文本歌词', () {
      final document = parser.parse('第一句\n\n第二句');

      expect(document.isSynced, isFalse);
      expect(document.lines.map((line) => line.text), ['第一句', '第二句']);
      expect(document.activeIndexAt(const Duration(seconds: 10)), -1);
    });

    test('负 offset 不会产生负时间', () {
      final document = parser.parse('[offset:-2000]\n[00:01.00]开场');

      expect(document.lines.single.time, Duration.zero);
    });

    test('同一物理行连续存放多句歌词时逐句拆分', () {
      final document = parser.parse(
        '[00:01.00]第一句[00:03.50]第二句[00:05.00][00:07.00]副歌',
      );

      expect(document.lines, hasLength(4));
      expect(document.lines.map((line) => line.text), [
        '第一句',
        '第二句',
        '副歌',
        '副歌',
      ]);
      expect(document.lines[1].time, const Duration(milliseconds: 3500));
      expect(document.lines[3].time, const Duration(seconds: 7));
    });
  });
}
