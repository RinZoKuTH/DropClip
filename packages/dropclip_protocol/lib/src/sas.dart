import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Calculates Short Authentication String (SAS) and Commitments according to PROTO-DC-V2.0 §5
class SasCalculator {
  SasCalculator._();

  static final RegExp _hex64Regex = RegExp(r'^[0-9a-fA-F]{64}$');
  static final RegExp _pin6Regex = RegExp(r'^\d{6}$');

  static void _validateFingerprint(String fp, String paramName) {
    if (!_hex64Regex.hasMatch(fp.trim())) {
      throw ArgumentError(
        'Fingerprint $paramName must be a 64-character hexadecimal string',
      );
    }
  }

  static void _validatePin(String pin) {
    if (!_pin6Regex.hasMatch(pin.trim())) {
      throw ArgumentError('PIN must be exactly 6 digits');
    }
  }

  /// Hashes concatenated byte chunks with SHA-256 and computes big-endian uint32 mod 1,000,000.
  static String _sas(List<List<int>> parts) {
    final totalLength = parts.fold<int>(0, (sum, part) => sum + part.length);
    final input = Uint8List(totalLength);
    var offset = 0;
    for (final part in parts) {
      input.setRange(offset, offset + part.length, part);
      offset += part.length;
    }

    final digest = sha256.convert(input);
    final digestBytes = digest.bytes;

    // First 4 bytes as big-endian uint32
    final uint32Be = (digestBytes[0] << 24) |
        (digestBytes[1] << 16) |
        (digestBytes[2] << 8) |
        digestBytes[3];

    // mod 1,000,000 padded to 6 digits
    final unsigned32 = uint32Be & 0xFFFFFFFF;
    return (unsigned32 % 1000000).toString().padLeft(6, '0');
  }

  /// Computes 6-digit SAS string given two certificate fingerprints and single raw nonce bytes.
  /// Maintained for test vector conformance §18.1.
  /// [fpA] and [fpB] are SHA-256 hex strings (64 lowercase characters).
  /// [nonceBytes] is the 16-byte pairing nonce.
  @Deprecated(
    'Use calculateSasDual for QR mode or calculateSasPinMode for PIN mode',
  )
  static String calculateSas(String fpA, String fpB, Uint8List nonceBytes) {
    if (nonceBytes.length != 16) {
      throw ArgumentError('Nonce must be exactly 16 bytes');
    }
    _validateFingerprint(fpA, 'fpA');
    _validateFingerprint(fpB, 'fpB');

    final normalizedA = fpA.toLowerCase().trim();
    final normalizedB = fpB.toLowerCase().trim();

    // Ascending sort of fingerprints as lowercase hex strings
    final sorted = [normalizedA, normalizedB]..sort();
    return _sas([utf8.encode(sorted[0]), utf8.encode(sorted[1]), nonceBytes]);
  }

  /// Computes 6-digit SAS string with dual nonces in QR Mode according to PROTO-DC-V2.0 §5.5.1.
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
    _validateFingerprint(fpA, 'fpA');
    _validateFingerprint(fpB, 'fpB');

    final normalizedA = fpA.toLowerCase().trim();
    final normalizedB = fpB.toLowerCase().trim();

    final sorted = [normalizedA, normalizedB]..sort();
    return _sas([
      utf8.encode(sorted[0]),
      utf8.encode(sorted[1]),
      nonceA,
      nonceB,
    ]);
  }

  /// Computes 6-digit SAS string in PIN mode according to PROTO-DC-V2.0 §5.5.2 & §18.2.
  /// Neither PIN nor any hash derived from PIN is ever sent over the network.
  /// Instead, [pin] is used as an out-of-band shared secret salt.
  static String calculateSasPinMode(
    String fpA,
    String fpB,
    Uint8List nonceA,
    Uint8List nonceB,
    String pin,
  ) {
    if (nonceA.length != 16 || nonceB.length != 16) {
      throw ArgumentError('Both nonces must be exactly 16 bytes');
    }
    _validateFingerprint(fpA, 'fpA');
    _validateFingerprint(fpB, 'fpB');
    _validatePin(pin);

    final normalizedA = fpA.toLowerCase().trim();
    final normalizedB = fpB.toLowerCase().trim();

    final sorted = [normalizedA, normalizedB]..sort();
    final pinBytes = utf8.encode('dropclip-pin-salt-v1:${pin.trim()}');

    return _sas([
      utf8.encode(sorted[0]),
      utf8.encode(sorted[1]),
      nonceA,
      nonceB,
      pinBytes,
    ]);
  }

  /// Computes cryptographic commitment for Client B according to PROTO-DC-V2.0 §5.2
  /// C_B = SHA-256("dropclip-commit-v1:" || nonce_B || fp_B)
  static String createCommitment(Uint8List nonceB, String fpB) {
    if (nonceB.length != 16) {
      throw ArgumentError('Nonce must be exactly 16 bytes');
    }
    _validateFingerprint(fpB, 'fpB');

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
    if (nonceB.length != 16) {
      return false;
    }
    if (!_hex64Regex.hasMatch(fpB.trim())) {
      return false;
    }
    final expected = createCommitment(nonceB, fpB);
    return expected == commitment.toLowerCase().trim();
  }
}
