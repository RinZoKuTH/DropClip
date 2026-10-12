import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('Path Sanitizer Attack Vectors (PROTO-DC-V2.0 §18.6 & NFR-S03)', () {
    test('V1: Blocks parent traversal (../../etc/passwd)', () {
      expect(() => PathSanitizer.sanitize('../../etc/passwd'),
          throwsA(isA<InvalidPathException>()));
    });

    test('V2: Blocks hidden traversal in middle (photos/../../secret.txt)', () {
      expect(() => PathSanitizer.sanitize('photos/../../secret.txt'),
          throwsA(isA<InvalidPathException>()));
    });

    test('V3: Blocks absolute POSIX paths (/etc/passwd)', () {
      expect(() => PathSanitizer.sanitize('/etc/passwd'),
          throwsA(isA<InvalidPathException>()));
    });

    test('V4: Blocks Windows drive letters (C:/Windows/System32/evil.dll)', () {
      expect(() => PathSanitizer.sanitize('C:/Windows/System32/evil.dll'),
          throwsA(isA<InvalidPathException>()));
    });

    test('V5: Blocks UNC paths (//server/share/x)', () {
      expect(() => PathSanitizer.sanitize('//server/share/x'),
          throwsA(isA<InvalidPathException>()));
    });

    test('V6: Blocks backslash separators (..\\..\\Windows\\win.ini)', () {
      expect(() => PathSanitizer.sanitize(r'..\..\Windows\win.ini'),
          throwsA(isA<InvalidPathException>()));
    });

    test('V7: Blocks null byte injection (file\x00.txt)', () {
      expect(() => PathSanitizer.sanitize('file\x00.txt'),
          throwsA(isA<InvalidPathException>()));
    });

    test('V8: Blocks Windows reserved device names (CON, NUL, COM1, CONIN$, COM¹, etc.)', () {
      expect(() => PathSanitizer.sanitize('CON'),
          throwsA(isA<InvalidPathException>()));
      expect(() => PathSanitizer.sanitize('photos/con.txt'),
          throwsA(isA<InvalidPathException>()));
      expect(() => PathSanitizer.sanitize('COM1.log'),
          throwsA(isA<InvalidPathException>()));
      expect(() => PathSanitizer.sanitize('data/LPT9'),
          throwsA(isA<InvalidPathException>()));
      expect(() => PathSanitizer.sanitize('CONIN$'),
          throwsA(isA<InvalidPathException>()));
      expect(() => PathSanitizer.sanitize('docs/CONOUT$.txt'),
          throwsA(isA<InvalidPathException>()));
      expect(() => PathSanitizer.sanitize('COM¹'),
          throwsA(isA<InvalidPathException>()));
      expect(() => PathSanitizer.sanitize('data/LPT².pdf'),
          throwsA(isA<InvalidPathException>()));
    });

    test('V9: Blocks trailing dots and spaces (report., report )', () {
      expect(() => PathSanitizer.sanitize('report.'),
          throwsA(isA<InvalidPathException>()));
      expect(() => PathSanitizer.sanitize('report '),
          throwsA(isA<InvalidPathException>()));
    });

    test('V10: Blocks reserved characters (a:b.txt, a<b>.txt, what?.txt)', () {
      expect(() => PathSanitizer.sanitize('a:b.txt'),
          throwsA(isA<InvalidPathException>()));
      expect(() => PathSanitizer.sanitize('a<b>.txt'),
          throwsA(isA<InvalidPathException>()));
      expect(() => PathSanitizer.sanitize('what?.txt'),
          throwsA(isA<InvalidPathException>()));
    });

    test('V11: Blocks control characters', () {
      expect(() => PathSanitizer.sanitize('bad\x1Bname.txt'),
          throwsA(isA<InvalidPathException>()));
    });

    test('V12: Blocks double slashes, dot directories, and overlong components', () {
      expect(() => PathSanitizer.sanitize('a//b'),
          throwsA(isA<InvalidPathException>()));
      expect(() => PathSanitizer.sanitize('./a'),
          throwsA(isA<InvalidPathException>()));
      final overlongComponent = 'a' * 256;
      expect(() => PathSanitizer.sanitize('dir/$overlongComponent'),
          throwsA(isA<InvalidPathException>()));
    });

    test('V13: Blocks Unicode bidirectional override characters (RLO, LRO, etc.)', () {
      // Right-to-Left Override (\u202E) used to disguise executables e.g. "invoice\u202Etxt.exe"
      expect(() => PathSanitizer.sanitize('invoice\u202Etxt.exe'),
          throwsA(isA<InvalidPathException>()));
      expect(() => PathSanitizer.sanitize('file\u202Aname.txt'),
          throwsA(isA<InvalidPathException>()));
      expect(() => PathSanitizer.sanitize('folder/\u2066secret\u2069.doc'),
          throwsA(isA<InvalidPathException>()));
    });

    test('Valid paths are accepted and formatted', () {
      expect(PathSanitizer.sanitize('Photos/vacation.jpg'),
          equals('Photos/vacation.jpg'));
      expect(PathSanitizer.sanitize('เอกสาร/รายงาน ฉบับที่ 1.pdf'),
          equals('เอกสาร/รายงาน ฉบับที่ 1.pdf'));
      expect(PathSanitizer.sanitize('😀/emoji file.png'),
          equals('😀/emoji file.png'));
      expect(PathSanitizer.sanitize('a/b/c/d.txt'), equals('a/b/c/d.txt'));
      expect(PathSanitizer.sanitize('.hidden'), equals('.hidden'));
      expect(PathSanitizer.sanitize('name.with.dots.tar.gz'),
          equals('name.with.dots.tar.gz'));
    });

    test('validateOfferPaths detects case-insensitive collisions', () {
      final collidingPaths = [
        'Documents/Report.pdf',
        'documents/report.pdf',
      ];
      expect(
        () => PathSanitizer.validateOfferPaths(collidingPaths),
        throwsA(isA<InvalidPathException>().having((e) => e.reason, 'reason', contains('collision'))),
      );

      final validPaths = [
        'Documents/Report.pdf',
        'Documents/Summary.pdf',
        'Photos/img1.png',
      ];
      final validated = PathSanitizer.validateOfferPaths(validPaths);
      expect(validated.length, equals(3));
    });
  });
}

