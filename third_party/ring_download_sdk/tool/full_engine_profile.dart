import 'dart:typed_data';

import 'package:ring_download_sdk/compat.dart';
import 'package:ring_download_sdk/src/p8p/transfer_protocol.dart';

const profileName = 'p8p';

AppUpgradeV40P2PClient createBenchmarkClient(Map<Symbol, dynamic> options) =>
    Function.apply(AppUpgradeV40P2PClient.new, const [], {
          ...options,
          #enableP8P: true,
        })
        as AppUpgradeV40P2PClient;

Uint8List encodeBenchmarkFrame(
  int generation,
  int request,
  int offset,
  Uint8List bytes,
) => P8PTransferProtocol.encode(generation, request, offset, bytes);
