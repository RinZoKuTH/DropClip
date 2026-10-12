import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:test/test.dart';

void main() {
  group('DropClip UI Package', () {
    test('DropClipThemeTokens defines valid app name', () {
      expect(DropClipThemeTokens.appName, equals('DropClip'));
    });
  });
}

