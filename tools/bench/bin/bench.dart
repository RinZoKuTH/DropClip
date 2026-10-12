import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dropclip_protocol/dropclip_protocol.dart';

void main(List<String> args) {
  stdout.writeln('=== DropClip Performance Benchmark Suite ===');
  stdout.writeln('Measuring SAS calculation performance...');

  const fpA =
      '0000000000000000000000000000000000000000000000000000000000000000';
  const fpB =
      '1111111111111111111111111111111111111111111111111111111111111111';
  final nonceA = Uint8List.fromList(ascii.encode('0123456789abcdef'));
  final nonceB = Uint8List.fromList(ascii.encode('fedcba9876543210'));

  final stopwatch = Stopwatch()..start();
  const iterations = 10000;
  for (int i = 0; i < iterations; i++) {
    SasCalculator.calculateSasDual(fpA, fpB, nonceA, nonceB);
  }
  stopwatch.stop();

  const targetUs = 100.0;
  final perOpUs = stopwatch.elapsedMicroseconds / iterations;
  stdout.writeln(
    'Completed $iterations Dual SAS calculations in ${stopwatch.elapsedMilliseconds} ms (${perOpUs.toStringAsFixed(2)} µs / op)',
  );
  if (perOpUs < targetUs) {
    stdout.writeln('Target check: OK (< $targetUs µs)');
  } else {
    stderr.writeln('Target check: FAILED (>= $targetUs µs)');
    exitCode = 1;
  }
}
