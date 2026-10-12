import 'dart:convert';
import 'dart:typed_data';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('SAS Calculation Conformance Tests (PROTO-DC-V2.0 §18.1 & §18.2)', () {
    const fpA = '0000000000000000000000000000000000000000000000000000000000000000';
    const fpB = '1111111111111111111111111111111111111111111111111111111111111111';
    final nonceBytes = Uint8List.fromList(ascii.encode('0123456789abcdef'));
    final nonceA = Uint8List.fromList(ascii.encode('0123456789abcdef'));
    final nonceB = Uint8List.fromList(ascii.encode('fedcba9876543210'));

    test('Dual nonce QR mode SAS matches test vector 18.1 ("337017")', () {
      final sas = SasCalculator.calculateSasDual(fpA, fpB, nonceA, nonceB);
      expect(sas, equals('337017'));

      // Symmetry check
      final sasSwapped = SasCalculator.calculateSasDual(fpB, fpA, nonceA, nonceB);
      expect(sasSwapped, equals(sas));
    });

    test('Legacy single-nonce QR mode SAS calculation matches ("579318")', () {
      // ignore: deprecated_member_use_from_same_package
      final sas = SasCalculator.calculateSas(fpA, fpB, nonceBytes);
      expect(sas, equals('579318'));
    });

    test('OOB Salted PIN mode SAS matches test vector 18.2 ("639589")', () {
      final sas = SasCalculator.calculateSasPinMode(fpA, fpB, nonceA, nonceB, '123456');
      expect(sas, equals('639589'));

      // Symmetry check
      final sasSwapped = SasCalculator.calculateSasPinMode(fpB, fpA, nonceA, nonceB, '123456');
      expect(sasSwapped, equals(sas));
    });

    test('PIN mode fails if PIN is incorrect', () {
      final sasCorrect = SasCalculator.calculateSasPinMode(fpA, fpB, nonceA, nonceB, '123456');
      final sasWrong = SasCalculator.calculateSasPinMode(fpA, fpB, nonceA, nonceB, '654321');
      expect(sasWrong, isNot(equals(sasCorrect)));
    });
  });

  group('Input Validation Tests', () {
    const validFp = '0000000000000000000000000000000000000000000000000000000000000000';
    final validNonce = Uint8List.fromList(ascii.encode('0123456789abcdef'));
    final shortNonce = Uint8List.fromList(ascii.encode('short'));

    test('Throws ArgumentError for non-hex or non-64-char fingerprints', () {
      expect(
        () => SasCalculator.calculateSasDual('not-a-valid-fp', validFp, validNonce, validNonce),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => SasCalculator.calculateSasDual(validFp, '012345', validNonce, validNonce),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Throws ArgumentError for invalid PIN length or non-numeric PIN', () {
      expect(
        () => SasCalculator.calculateSasPinMode(validFp, validFp, validNonce, validNonce, '123'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => SasCalculator.calculateSasPinMode(validFp, validFp, validNonce, validNonce, 'abcdef'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Throws ArgumentError for non-16-byte nonces', () {
      expect(
        () => SasCalculator.calculateSasDual(validFp, validFp, shortNonce, validNonce),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => SasCalculator.calculateSasDual(validFp, validFp, validNonce, shortNonce),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Commit-then-Reveal SAS Scheme (PROTO-DC-V2.0 §5.2, §5.5 & ADR-009)', () {
    const fpA = '0000000000000000000000000000000000000000000000000000000000000000';
    const fpB = '1111111111111111111111111111111111111111111111111111111111111111';
    final nonceA = Uint8List.fromList(ascii.encode('0123456789abcdef'));
    final nonceB = Uint8List.fromList(ascii.encode('fedcba9876543210'));

    test('Calculates 6-digit dual SAS with symmetry in QR mode', () {
      final sasHost = SasCalculator.calculateSasDual(fpA, fpB, nonceA, nonceB);
      final sasClient = SasCalculator.calculateSasDual(fpB, fpA, nonceA, nonceB);

      expect(sasHost.length, equals(6));
      expect(RegExp(r'^\d{6}$').hasMatch(sasHost), isTrue);
      expect(sasClient, equals(sasHost), reason: 'Must be symmetric across peers');
    });

    test('Commitment generation and verification succeed with valid nonce and fp', () {
      final commitment = SasCalculator.createCommitment(nonceB, fpB);
      expect(commitment.length, equals(64));

      final isValid = SasCalculator.verifyCommitment(commitment, nonceB, fpB);
      expect(isValid, isTrue);
    });

    test('Commitment verification fails when tampered or wrong fp is supplied', () {
      final commitment = SasCalculator.createCommitment(nonceB, fpB);

      // Wrong nonce
      final fakeNonce = Uint8List.fromList(ascii.encode('0000000000000000'));
      expect(SasCalculator.verifyCommitment(commitment, fakeNonce, fpB), isFalse);

      // Wrong fp (MITM key substitution)
      const fakeFp = '2222222222222222222222222222222222222222222222222222222222222222';
      expect(SasCalculator.verifyCommitment(commitment, nonceB, fakeFp), isFalse);
    });
  });
}

