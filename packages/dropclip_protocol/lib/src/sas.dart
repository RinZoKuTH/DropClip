import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Calculates Short Authentication String (SAS) according to PROTO-DC-V2.0 §5.5
class SasCalculator {
  SasCalculator._();

  /// Computes 6-digit SAS string given two certificate fingerprints and raw nonce bytes.
  /// [fpA] and [fpB] are SHA-256 hex strings (64 lowercase characters).
  /// [nonceBytes] is the 16-byte pairing nonce.
  static String calculateSas(String fpA, String fpB, Uint8List nonceBytes) {
    if (nonceBytes.length != 16) {
      throw ArgumentError('Nonce must be exactly 16 bytes');
    }
    final normalizedA = fpA.toLowerCase().trim();
    final normalizedB = fpB.toLowerCase().trim();

    // Ascending sort of fingerprints as lowercase hex strings
    final sorted = [normalizedA, normalizedB]..sort();
    final fpLo = sorted[0];
    final fpHi = sorted[1];

    // sas_input = UTF8(fp_lo) || UTF8(fp_hi) || nonce_bytes (64 + 64 + 16 = 144 bytes)
    final fpLoBytes = utf8.encode(fpLo);
    final fpHiBytes = utf8.encode(fpHi);

    final input = Uint8List(fpLoBytes.length + fpHiBytes.length + nonceBytes.length);
    input.setRange(0, fpLoBytes.length, fpLoBytes);
    input.setRange(fpLoBytes.length, fpLoBytes.length + fpHiBytes.length, fpHiBytes);
    input.setRange(fpLoBytes.length + fpHiBytes.length, input.length, nonceBytes);

    final digest = sha256.convert(input);
    final digestBytes = digest.bytes;

    // First 4 bytes as big-endian uint32
    final uint32Be = (digestBytes[0] << 24) |
        (digestBytes[1] << 16) |
        (digestBytes[2] << 8) |
        digestBytes[3];

    // mod 1,000,000 padded to 6 digits
    final unsigned32 = uint32Be & 0xFFFFFFFF;
    final sasDigits = (unsigned32 % 1000000).toString().padLeft(6, '0');
    return sasDigits;
  }

  /// Derives 16-byte pin_nonce from 6-digit PIN according to PROTO-DC-V2.0 §5.2
  static Uint8List derivePinNonce(String pin) {
    final pinStr = 'dropclip-pin-v1:${pin.trim()}';
    final digest = sha256.convert(utf8.encode(pinStr));
    return Uint8List.fromList(digest.bytes.sublist(0, 16));
  }
}
