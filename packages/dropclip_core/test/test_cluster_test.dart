import 'dart:async';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('TestCluster In-Memory Harness (T0.4 & NFR-RE02, NFR-RE03)', () {
    late TestCluster cluster;

    setUp(() async {
      cluster = await TestCluster.spawn(4);
    });

    tearDown(() async {
      await cluster.dispose();
    });

    test(
      'Spawns requested number of nodes with distinct IDs and initial HLCs',
      () {
        expect(cluster.nodes.length, equals(4));
        expect(cluster.getNode('node-0'), isNotNull);
        expect(cluster.getNode('node-1'), isNotNull);
        expect(cluster.getNode('node-2'), isNotNull);
        expect(cluster.getNode('node-3'), isNotNull);
      },
    );

    test('Delivers unicast packets and updates receiver HLC', () async {
      final node0 = cluster.getNode('node-0')!;
      final node1 = cluster.getNode('node-1')!;

      final packet = {'type': 'clipboard.update', 'item_id': 'clip-101'};

      await cluster.send(fromId: node0.id, toId: node1.id, packet: packet);

      expect(node1.receivedHistory.length, equals(1));
      expect(node1.receivedHistory.first['item_id'], equals('clip-101'));
      expect(node1.receivedHistory.first.containsKey('hlc'), isTrue);
      // Receiver clock has merged and is higher than sender's original clock
      expect(node1.clock.compareTo(node0.clock), greaterThanOrEqualTo(0));
    });

    test('Broadcasts packet to all peers in the cluster', () async {
      final node0 = cluster.getNode('node-0')!;

      await cluster.broadcast(
        fromId: node0.id,
        packet: {'type': 'cluster.ping', 'value': 42},
      );

      for (var i = 1; i < 4; i++) {
        final peer = cluster.getNode('node-$i')!;
        expect(peer.receivedHistory.length, equals(1));
        expect(peer.receivedHistory.first['value'], equals(42));
      }
      expect(
        node0.receivedHistory.isEmpty,
        isTrue,
      ); // Sender should not receive own broadcast
    });

    test(
      'Partitions network and isolates communication between groups',
      () async {
        // Group A: node-0, node-1; Group B: node-2, node-3
        cluster.partition(['node-0', 'node-1'], ['node-2', 'node-3']);

        // Intra-group communication should succeed
        await cluster.send(
          fromId: 'node-0',
          toId: 'node-1',
          packet: {'type': 'intra_a'},
        );
        expect(cluster.getNode('node-1')!.receivedHistory.length, equals(1));

        // Inter-group communication should be dropped
        await cluster.send(
          fromId: 'node-0',
          toId: 'node-2',
          packet: {'type': 'cross_partition'},
        );
        expect(cluster.getNode('node-2')!.receivedHistory.isEmpty, isTrue);

        // Healing restores connectivity
        cluster.heal();
        await cluster.send(
          fromId: 'node-0',
          toId: 'node-2',
          packet: {'type': 'after_heal'},
        );
        expect(cluster.getNode('node-2')!.receivedHistory.length, equals(1));
        expect(
          cluster.getNode('node-2')!.receivedHistory.first['type'],
          equals('after_heal'),
        );
      },
    );

    test(
      'Simulates network latency and settles in-flight deliveries',
      () async {
        cluster.latency = const Duration(milliseconds: 50);

        final node0 = cluster.getNode('node-0')!;
        final node1 = cluster.getNode('node-1')!;

        // Send without awaiting completion
        unawaited(
          cluster.send(
            fromId: node0.id,
            toId: node1.id,
            packet: {'type': 'delayed_msg'},
          ),
        );

        // Settle waits for the delayed delivery
        await cluster.settle(timeout: const Duration(seconds: 1));
        expect(node1.receivedHistory.length, equals(1));
        expect(node1.receivedHistory.first['type'], equals('delayed_msg'));
      },
    );

    test('Drops packets whose HLC drifts beyond MAX_CLOCK_DRIFT', () async {
      final node1 = cluster.getNode('node-1')!;
      final future = DateTime.now().millisecondsSinceEpoch +
          ProtocolConstants.maxClockDriftMs * 2;

      await cluster.send(
        fromId: 'node-0',
        toId: node1.id,
        packet: {'type': 'drifted', 'hlc': '$future:0:node-0'},
      );

      expect(node1.receivedHistory, isEmpty);
      expect(node1.clock.l, lessThan(future));
    });

    test('Sender clock advances monotonically across sends', () async {
      final node0 = cluster.getNode('node-0')!;
      final before = node0.clock;

      await cluster.send(fromId: 'node-0', toId: 'node-1', packet: {});
      final afterFirst = node0.clock;
      await cluster.send(fromId: 'node-0', toId: 'node-1', packet: {});

      expect(afterFirst.compareTo(before), greaterThan(0));
      expect(node0.clock.compareTo(afterFirst), greaterThan(0));
    });

    test('Ignores deliveries that arrive after the node is disposed', () async {
      final node1 = cluster.getNode('node-1')!;
      await node1.dispose();

      expect(() => node1.deliver({'type': 'late'}), returnsNormally);
      expect(node1.receivedHistory, isEmpty);
    });
  });
}
