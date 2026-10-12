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

    test('QR mode SAS calculation matches test vector 18.1 ("579318")', () {
      final sas = SasCalculator.calculateSas(fpA, fpB, nonceBytes);
      expect(sas, equals('579318'));
    });

    test('SAS calculation is symmetric when swapping fpA and fpB', () {
      final sasForward = SasCalculator.calculateSas(fpA, fpB, nonceBytes);
      final sasReverse = SasCalculator.calculateSas(fpB, fpA, nonceBytes);
      expect(sasReverse, equals(sasForward));
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
