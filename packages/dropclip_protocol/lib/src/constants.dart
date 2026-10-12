/// Protocol constants defined in PROTO-DC-V2.0
class ProtocolConstants {
  ProtocolConstants._();

  static const int protocolVersion = 1;
  static const int portRangeStart = 53317;
  static const int portRangeEnd = 53417;

  static const Duration mdnsTtl = Duration(seconds: 120);
  static const Duration discoveryQueryInterval = Duration(seconds: 10);
  static const Duration deviceStaleTimeout = Duration(seconds: 30);
  static const Duration deviceRemoveTimeout = Duration(seconds: 120);

  static const Duration pairNonceTtl = Duration(seconds: 60);
  static const Duration pairConfirmTimeout = Duration(seconds: 120);
  static const int pairRateLimit = 5; // requests / minute / IP
  static const int pairMaxFailures = 3;
  static const Duration pairLockout = Duration(minutes: 5);

  static const int wsMaxMessageSize = 65536; // 64 KiB
  static const int clipboardInlineThreshold = 32768; // 32 KiB
  static const int clipboardMaxSize = 33554432; // 32 MiB
  static const int imageMaxPixels = 64000000; // 8000x8000 px

  static const Duration blobTtl = Duration(seconds: 120);
  static const Duration suppressionWindow = Duration(milliseconds: 800);
  static const int seenMsgCacheSize = 200;
  static const int catchupQueueSize = 20;
  static const int outboundQueueSize = 50;

  static const Duration helloTimeout = Duration(seconds: 5);
  static const Duration initiatorGrace = Duration(seconds: 10);
  static const Duration pingInterval = Duration(seconds: 15);
  static const Duration pongTimeout = Duration(seconds: 45);

  static const int maxPeers = 8;
  static const int fileChunkSize = 1048576; // 1 MiB
  static const int maxConcurrentTransfers = 3;
  static const int maxItemsPerTransfer = 10000;
  static const Duration offerTimeout = Duration(seconds: 60);
  static const Duration progressMinInterval = Duration(milliseconds: 500);
  static const Duration partialRetention = Duration(hours: 24);
  static const Duration revocationDeadline = Duration(milliseconds: 1000);
}
