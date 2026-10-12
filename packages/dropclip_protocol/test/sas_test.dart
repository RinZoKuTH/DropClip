import 'dart:convert';
import 'dart:typed_data';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('SAS Calculation Conformance Tests (PROTO-DC-V2.0 §18.1 & §18.2)', () {
    const fpA = '0000000000000000000000000000000000000000000000000000000000000000';
    const fpB = '1111111111111111111111111111111111111111111111111111111111111111';
    final nonceBytes = Uint8List.fromList(ascii.encode('0123456789abcdef'));

    test('QR mode SAS calculation matches test vector 18.1 ("579318")', () {
      final sas = SasCalculator.calculateSas(fpA, fpB, nonceBytes);
      expect(sas, equals('579318'));
    });

    test('SAS calculation is symmetric when swapping fpA and fpB', () {
      final sasForward = SasCalculator.calculateSas(fpA, fpB, nonceBytes);
      final sasReverse = SasCalculator.calculateSas(fpB, fpA, nonceBytes);
      expect(sasReverse, equals(sasForward));
    });

    test('PIN mode SAS calculation matches test vector 18.2 ("738586")', () {
      final pinNonce = SasCalculator.derivePinNonce('123456');
      expect(pinNonce.length, equals(16));
      final sas = SasCalculator.calculateSas(fpA, fpB, pinNonce);
      expect(sas, equals('738586'));
    });
  });
}
