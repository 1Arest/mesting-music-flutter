import 'package:ring_download_sdk/compat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('v40 download URL boundary', () {
    test('accepts only HTTPS download paths on configured service hosts', () {
      expect(
        AppUpgradeV40DownloadClient.isV40DownloadUrl(
          'https://download.csnas.asia/lifering/download',
          expectedSlug: 'lifering',
        ),
        isTrue,
      );
      expect(
        AppUpgradeV40DownloadClient.isV40DownloadUrl(
          'https://download1.csnas.asia/lifering/download?direct=backup',
          expectedSlug: 'lifering',
        ),
        isTrue,
      );
      for (final url in <String>[
        'http://download.csnas.asia/lifering/download',
        'https://example.com/lifering/download',
        'https://download.csnas.asia/other/download',
        'https://download.csnas.asia/lifering/download/extra',
        'https://user@download.csnas.asia/lifering/download',
        'https://download.csnas.asia:444/lifering/download',
      ]) {
        expect(
          AppUpgradeV40DownloadClient.isV40DownloadUrl(
            url,
            expectedSlug: 'lifering',
          ),
          isFalse,
          reason: url,
        );
      }
    });

    test('accepts a well-formed single byte range only', () {
      final range = AppUpgradeV40DownloadClient.parseContentRange(
        'bytes 10-19/100',
      );
      expect(range?.start, 10);
      expect(range?.end, 19);
      expect(range?.total, 100);
      for (final value in <String?>[
        null,
        'bytes 10-9/100',
        'bytes 10-100/100',
        'items 10-19/100',
        'bytes */100',
      ]) {
        expect(AppUpgradeV40DownloadClient.parseContentRange(value), isNull);
      }
    });
  });
}
