import 'package:dropclip_core/dropclip_core.dart';
import 'package:test/test.dart';

void main() {
  group('DropClip Core Package', () {
    test('Package initializes properly', () {
      expect(SecureKeyStore, isNotNull);
    });
  });
}
