import 'package:dropclip_core/dropclip_core.dart';
import 'package:test/test.dart';

void main() {
  group('DropClip Core Package', () {
    test('Package exports core types properly', () {
      expect(SecureKeyStore, isNotNull);
      expect(LoggingScrubber, isNotNull);
      expect(TestCluster, isNotNull);
    });
  });
}
