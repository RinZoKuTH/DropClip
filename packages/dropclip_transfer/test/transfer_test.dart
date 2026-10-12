import 'package:dropclip_transfer/dropclip_transfer.dart';
import 'package:test/test.dart';

void main() {
  group('DropClip Transfer Package', () {
    test('TransferProgress calculates percentage accurately', () {
      const progress = TransferProgress(
        transferId: 'tx-1',
        itemId: 'item-1',
        bytesTransferred: 50,
        totalBytes: 100,
      );
      expect(progress.fraction, equals(0.5));
      expect(progress.percentage, equals(50.0));
    });
  });
}
