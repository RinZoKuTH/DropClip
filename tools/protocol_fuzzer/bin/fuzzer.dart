import 'dart:io';
import 'package:dropclip_protocol/dropclip_protocol.dart';

void main(List<String> args) {
  stdout.writeln('Running DropClip Protocol Fuzzer against attack vectors...');
  int blockedCount = 0;

  final attackVectors = [
    '../../etc/passwd',
    'photos/../../secret.txt',
    '/etc/passwd',
    'C:/Windows/System32/evil.dll',
    '//server/share/x',
    r'..\..\Windows\win.ini',
    'file\x00.txt',
    'CON',
    'report.',
    'a:b.txt',
    'bad\x1Bname.txt',
    'a//b',
  ];

  for (final vector in attackVectors) {
    try {
      PathSanitizer.sanitize(vector);
      stderr.writeln('FAILED TO BLOCK: $vector');
    } on InvalidPathException {
      blockedCount++;
    }
  }

  stdout.writeln('Fuzzer finished: Successfully blocked $blockedCount / ${attackVectors.length} malicious vectors.');
}
