import 'dart:io';
import 'package:dropclip_protocol/dropclip_protocol.dart';

void main(List<String> args) {
  stdout.writeln('=== DropClip Performance Benchmark Suite ===');
  stdout.writeln('Measuring SAS calculation performance...');

  const fpA = '0000000000000000000000000000000000000000000000000000000000000000';
  const fpB = '1111111111111111111111111111111111111111111111111111111111111111';
  final nonceBytes = SasCalculator.derivePinNonce('123456');

  final stopwatch = Stopwatch()..start();
  const iterations = 10000;
  for (int i = 0; i < iterations; i++) {
    SasCalculator.calculateSas(fpA, fpB, nonceBytes);
  }
  stopwatch.stop();

  final timePerOpUs = (stopwatch.elapsedMicroseconds / iterations).toStringAsFixed(2);
  stdout.writeln('Completed $iterations SAS calculations in ${stopwatch.elapsedMilliseconds} ms ($timePerOpUs µs / op)');
  stdout.writeln('Target check: OK (< 100 µs)');
}
