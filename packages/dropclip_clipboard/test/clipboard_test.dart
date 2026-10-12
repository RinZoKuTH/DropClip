import 'package:dropclip_clipboard/dropclip_clipboard.dart';
import 'package:test/test.dart';

void main() {
  group('DropClip Clipboard Package', () {
    test('ClipboardItem initializes with proper mime and data', () {
      final item = ClipboardItem(mime: 'text/plain', data: [72, 101, 108, 108, 111]);
      expect(item.mime, equals('text/plain'));
      expect(item.data.length, equals(5));
    });
  });
}
