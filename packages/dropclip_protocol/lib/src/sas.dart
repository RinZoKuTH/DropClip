import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Calculates Short Authentication String (SAS) and Commitments according to PROTO-DC-V2.0 §5
class SasCalculator {
  SasCalculator._();

  /// Computes 6-digit SAS string given two certificate fingerprints and single raw nonce bytes.
  /// Maintained for test vector conformance §18.1 & §18.2.
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

  /// Computes 6-digit SAS string with dual nonces according to PROTO-DC-V2.0 §5.5 (ADR-009).
  /// [nonceA] is the 16-byte CSPRNG Host nonce.
  /// [nonceB] is the 16-byte CSPRNG Client nonce revealed after commitment verification.
  static String calculateSasDual(
    String fpA,
    String fpB,
    Uint8List nonceA,
    Uint8List nonceB,
  ) {
    if (nonceA.length != 16 || nonceB.length != 16) {
      throw ArgumentError('Both nonces must be exactly 16 bytes');
    }
    final normalizedA = fpA.toLowerCase().trim();
    final normalizedB = fpB.toLowerCase().trim();

    final sorted = [normalizedA, normalizedB]..sort();
    final fpLo = sorted[0];
    final fpHi = sorted[1];

    final fpLoBytes = utf8.encode(fpLo);
    final fpHiBytes = utf8.encode(fpHi);

    // sas_input = UTF8(fp_lo) || UTF8(fp_hi) || nonce_A || nonce_B (64 + 64 + 16 + 16 = 160 bytes)
    final input = Uint8List(
      fpLoBytes.length + fpHiBytes.length + nonceA.length + nonceB.length,
    );
    var offset = 0;
    input.setRange(offset, offset + fpLoBytes.length, fpLoBytes);
    offset += fpLoBytes.length;
    input.setRange(offset, offset + fpHiBytes.length, fpHiBytes);
    offset += fpHiBytes.length;
    input.setRange(offset, offset + nonceA.length, nonceA);
    offset += nonceA.length;
    input.setRange(offset, offset + nonceB.length, nonceB);

    final digest = sha256.convert(input);
    final digestBytes = digest.bytes;

    final uint32Be = (digestBytes[0] << 24) |
        (digestBytes[1] << 16) |
        (digestBytes[2] << 8) |
        digestBytes[3];

    final unsigned32 = uint32Be & 0xFFFFFFFF;
    return (unsigned32 % 1000000).toString().padLeft(6, '0');
  }

  /// Computes cryptographic commitment for Client B according to PROTO-DC-V2.0 §5.2
  /// C_B = SHA-256("dropclip-commit-v1:" || nonce_B || fp_B)
  static String createCommitment(Uint8List nonceB, String fpB) {
    if (nonceB.length != 16) {
      throw ArgumentError('Nonce must be exactly 16 bytes');
    }
    final prefix = utf8.encode('dropclip-commit-v1:');
    final fpBytes = utf8.encode(fpB.toLowerCase().trim());
    final input = Uint8List(prefix.length + nonceB.length + fpBytes.length);

    var offset = 0;
    input.setRange(offset, offset + prefix.length, prefix);
    offset += prefix.length;
    input.setRange(offset, offset + nonceB.length, nonceB);
    offset += nonceB.length;
    input.setRange(offset, offset + fpBytes.length, fpBytes);

    return sha256.convert(input).toString();
  }

  /// Verifies client commitment against revealed nonce_B and client fingerprint.
  static bool verifyCommitment(
    String commitment,
    Uint8List nonceB,
    String fpB,
  ) {
    final expected = createCommitment(nonceB, fpB);
    return expected == commitment.toLowerCase().trim();
  }

  /// Derives 16-byte pin_nonce from 6-digit PIN according to PROTO-DC-V2.0 §5.2
  static Uint8List derivePinNonce(String pin) {
    final pinStr = 'dropclip-pin-v1:${pin.trim()}';
    final digest = sha256.convert(utf8.encode(pinStr));
    return Uint8List.fromList(digest.bytes.sublist(0, 16));
  }
}
