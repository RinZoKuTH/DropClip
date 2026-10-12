import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('Hybrid Logical Clock (HLC) Tests (PROTO-DC-V2.0 §10 & ADR-008)', () {
    const nodeA = 'device-aaaa-1111';
    const nodeB = 'device-bbbb-2222';

    test('Initializes correctly and serializes to/from JSON', () {
      final hlc = Hlc(l: 1700000000000, c: 0, d: nodeA);
      final json = hlc.toJson();

      expect(json, equals({'l': 1700000000000, 'c': 0, 'd': nodeA}));

      final restored = Hlc.fromJson(json);
      expect(restored, equals(hlc));
      expect(restored.toString(), equals('1700000000000:0:device-aaaa-1111'));
    });

    test('tick advances l when physical time moves forward', () {
      final hlc0 = Hlc(l: 1000, c: 5, d: nodeA);
      final hlc1 = hlc0.tick(1050);

      expect(hlc1.l, equals(1050));
      expect(hlc1.c, equals(0), reason: 'Logical counter resets on physical tick');
      expect(hlc1.d, equals(nodeA));
    });

    test('tick increments c when physical time is same or behind', () {
      final hlc0 = Hlc(l: 1000, c: 0, d: nodeA);
      final hlc1 = hlc0.tick(1000);
      final hlc2 = hlc1.tick(990); // Wall clock slightly behind/skewed

      expect(hlc1.l, equals(1000));
      expect(hlc1.c, equals(1));

      expect(hlc2.l, equals(1000));
      expect(hlc2.c, equals(2));
    });

    test('merge adopts higher physical time and advances counter properly', () {
      final local = Hlc(l: 1000, c: 2, d: nodeA);
      final remote = Hlc(l: 1050, c: 0, d: nodeB);

      // Local wall time is 1020 (less than remote 1050)
      final merged = local.merge(remote, 1020);

      expect(merged.l, equals(1050));
      expect(merged.c, equals(1));
      expect(merged.d, equals(nodeA), reason: 'Keeps local node ID');
    });

    test('merge handles simultaneous events at identical physical timestamps', () {
      final local = Hlc(l: 2000, c: 3, d: nodeA);
      final remote = Hlc(l: 2000, c: 5, d: nodeB);

      final merged = local.merge(remote, 2000);

      expect(merged.l, equals(2000));
      expect(merged.c, equals(6), reason: 'max(3, 5) + 1');
      expect(merged.d, equals(nodeA));
    });

    test('Total order comparison respects l, then c, then d tie-break', () {
      final h1 = Hlc(l: 100, c: 0, d: nodeA);
      final h2 = Hlc(l: 101, c: 0, d: nodeA);
      final h3 = Hlc(l: 101, c: 1, d: nodeA);
      final h4 = Hlc(l: 101, c: 1, d: nodeB); // nodeB > nodeA string

      expect(h1.compareTo(h2), lessThan(0));
      expect(h2.compareTo(h1), greaterThan(0));

      expect(h2.compareTo(h3), lessThan(0));
      expect(h3.compareTo(h2), greaterThan(0));

      expect(h3.compareTo(h4), lessThan(0));
      expect(h4.compareTo(h3), greaterThan(0));
    });

    test('Resolves offline clipboard problem: newer physical copy wins over stale clock', () {
      // Scenario: Node A was connected, reached clock 1500:0.
      // Node B went offline at clock 1000:0 for 2 hours.
      // At physical time 1700 (2 hours later), user copies on Node B.
      // Under pure Lamport, B's clock would be 1001, losing to A's 1500 (silent drop bug!).
      // Under HLC:
      final nodeAClock = Hlc(l: 1500, c: 0, d: nodeA);
      final nodeBOffline = Hlc(l: 1000, c: 0, d: nodeB);

      // User copies on Node B at physical time 1700
      final nodeBNewCopy = nodeBOffline.tick(1700);

      // Node B reconnects and sends to Node A. LWW evaluation:
      expect(nodeBNewCopy.l, equals(1700));
      expect(nodeBNewCopy.compareTo(nodeAClock), greaterThan(0),
          reason: 'B has higher physical time (1700 > 1500), so the fresh offline copy wins LWW!');
    });

    test('Normalizes deviceId to lowercase and trimmed string', () {
      final hlc = Hlc(l: 1000, c: 0, d: '  DEVICE-UPPER-CASE  ');
      expect(hlc.d, equals('device-upper-case'));
    });

    test('Hlc.parse and tryParse parse wire string representations correctly', () {
      final parsed = Hlc.parse('1757280000000:42:device-1234');
      expect(parsed.l, equals(1757280000000));
      expect(parsed.c, equals(42));
      expect(parsed.d, equals('device-1234'));

      expect(Hlc.tryParse('1757280000000:42:device-1234'), equals(parsed));
      expect(Hlc.tryParse('invalid'), isNull);
      expect(Hlc.tryParse(null), isNull);
      expect(() => Hlc.parse('invalid'), throwsA(isA<FormatException>()));
    });

    test('merge succeeds when remote physical drift is within maxDriftMs (<= 60,000 ms)', () {
      final local = Hlc(l: 100000, c: 0, d: nodeA);
      final remote = Hlc(l: 150000, c: 0, d: nodeB); // 50,000 ms drift

      final merged = local.merge(remote, 100000);
      expect(merged.l, equals(150000));
      expect(merged.c, equals(1));
    });

    test('merge throws ClockDriftException when remote clock drifts beyond maxDriftMs (> 60s)', () {
      final local = Hlc(l: 100000, c: 0, d: nodeA);
      final remoteMalicious = Hlc(l: 200000, c: 0, d: nodeB); // 100,000 ms drift > 60,000 ms limit

      expect(
        () => local.merge(remoteMalicious, 100000),
        throwsA(
          isA<ClockDriftException>()
              .having((e) => e.driftMs, 'driftMs', equals(100000))
              .having((e) => e.maxDriftMs, 'maxDriftMs', equals(60000))
              .having((e) => e.localPhysicalTimeMs, 'localPhysicalTimeMs', equals(100000))
              .having((e) => e.remotePhysicalTimeMs, 'remotePhysicalTimeMs', equals(200000)),
        ),
      );
    });
  });
}

