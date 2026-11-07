import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps upstream authorship and the complete license available offline in the
/// APK. Corresponding server sources and build scripts live in third_party.
class PlatformCredits {
  PlatformCredits._();
  static bool _registered = false;

  static void register() {
    if (_registered) return;
    _registered = true;
    LicenseRegistry.addLicense(() async* {
      final license = await rootBundle.loadString(
        'third_party/md3music/LICENSE',
      );
      final notice = await rootBundle.loadString(
        'third_party/md3music/NOTICE.md',
      );
      yield LicenseEntryWithLineBreaks(
        ['md3Music · zzyoxml and contributors'],
        '$notice\n\n${await rootBundle.loadString('third_party/md3music/MESTING-1.0.3-PORTS.md')}\n\n$license',
      );
      final glassLicense = await rootBundle.loadString(
        'third_party/liquid_glass_widgets/LICENSE',
      );
      final glassNotice = await rootBundle.loadString(
        'third_party/liquid_glass_widgets/NOTICE.md',
      );
      yield LicenseEntryWithLineBreaks([
        'Liquid Glass Widgets Apple Music example · Sebastian Degenaar',
      ], '$glassNotice\n\n$glassLicense');
      final audioGlyphLicense = await rootBundle.loadString(
        'third_party/audio_glyphs/LICENSE',
      );
      final audioGlyphNotice = await rootBundle.loadString(
        'third_party/audio_glyphs/NOTICE.md',
      );
      yield LicenseEntryWithLineBreaks([
        'Tabler Icons · Paweł Kuna',
      ], '$audioGlyphNotice\n\n$audioGlyphLicense');
      final regionLicense = await rootBundle.loadString(
        'third_party/region_data/LICENSE',
      );
      final regionNotice = await rootBundle.loadString(
        'third_party/region_data/NOTICE.md',
      );
      yield LicenseEntryWithLineBreaks([
        'Administrative divisions · modood and contributors',
      ], '$regionNotice\n\n$regionLicense');
      // The native Dart port ships the upstream MIT text offline as well as
      // in source archives, independently of whether an account is signed in.
      final neteaseLicense = await rootBundle.loadString(
        'third_party/netease_protocol/LICENSE',
      );
      final neteaseNotice = await rootBundle.loadString(
        'third_party/netease_protocol/NOTICE.md',
      );
      yield LicenseEntryWithLineBreaks([
        'NetEaseCloudMusicApi · Binaryify and contributors',
      ], '$neteaseNotice\n\n$neteaseLicense');
      final unblockNotice = await rootBundle.loadString(
        'third_party/unblock_netease/NOTICE.md',
      );
      final unblockLicense = await rootBundle.loadString(
        'third_party/unblock_netease/COPYING.LESSER',
      );
      final gplTerms = await rootBundle.loadString(
        'third_party/unblock_netease/COPYING',
      );
      yield LicenseEntryWithLineBreaks([
        'UnblockNeteaseMusic · native source adapters',
      ], '$unblockNotice\n\n$unblockLicense\n\n$gplTerms');
    });
  }
}
