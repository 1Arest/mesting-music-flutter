import 'package:flutter_test/flutter_test.dart';
import 'package:ring_download_sdk/ring_download_sdk.dart';
import 'package:ring_download_sdk/src/p8p/source_diversity.dart';

const sdp =
    'v=0\r\na=ice-ufrag:unitufrag\r\na=ice-pwd:abcdefghijklmnopqrstuvwx\r\n'
    'm=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\n';
const advice = {
  'version': 1,
  'strategy': P8PSourceDiversity.strategy,
  'max_sockets': 4,
};

void main() {
  test('source-port experiment defaults off independently of peer race', () {
    expect(
      const RingDownloadConfig(appId: 'lifering').p8pSourcePortDiversity,
      false,
    );
    expect(
      const RingDownloadConfig(
        appId: 'lifering',
        p8pSourcePortDiversity: true,
      ).p8pPeerRaceLimit,
      2,
    );
  });
  test('ICE credential digest matches the server fixed vector', () {
    expect(
      P8PSourceDiversity.iceGeneration(sdp),
      'a9a9cdd4c0109ebade2e47251f5052c35ea94510ad77665eff014cd22a15136f',
    );
    expect(
      P8PSourceDiversity.iceGeneration(sdp.replaceAll('\r\n', '\n')),
      'a9a9cdd4c0109ebade2e47251f5052c35ea94510ad77665eff014cd22a15136f',
    );
    expect(
      P8PSourceDiversity.offer({
        ...advice,
        'targets': ['untrusted'],
        'attempt_id': 'x',
      }, sdp),
      {
        ...advice,
        'ice_generation':
            'a9a9cdd4c0109ebade2e47251f5052c35ea94510ad77665eff014cd22a15136f',
      },
    );
  });
  test('media credential overrides use the same scoped pair', () {
    expect(
      P8PSourceDiversity.iceGeneration('${sdp}a=ice-ufrag:replacement\r\n'),
      isNot(P8PSourceDiversity.iceGeneration(sdp)),
    );
  });
  test('unknown capability and malformed counts retain original transport', () {
    for (final value in [
      null,
      {},
      {...advice, 'version': 99},
      {...advice, 'strategy': 'other'},
      for (final count in [true, 1, 5, 4.0, '4'])
        {...advice, 'max_sockets': count},
    ]) {
      expect(P8PSourceDiversity.offer(value, sdp), null);
    }
  });
  test(
    'mixed media, invalid credentials and oversized input are unsupported',
    () {
      for (final value in [
        'm=\r\n',
        '${sdp}m=audio 9 RTP/AVP 0\r\n',
        sdp.replaceAll('unitufrag', 'bad!'),
        sdp.replaceAll('unitufrag', 'a'),
        sdp.replaceAll('abcdefghijklmnopqrstuvwx', 'short'),
        '${sdp}a=ice-ufrag:first\r\na=ice-ufrag:second\r\n',
        'x' * 65537,
      ]) {
        expect(P8PSourceDiversity.offer(advice, value), null);
      }
    },
  );
}
