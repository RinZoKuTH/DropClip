import 'dart:async';
import 'dart:math';
import 'package:dropclip_protocol/dropclip_protocol.dart';

/// Simulated In-Memory Node representing a DropClip instance (T0.4).
class TestNode {
  final String id;
  Hlc clock;
  final StreamController<Map<String, dynamic>> _inboundController =
      StreamController<Map<String, dynamic>>.broadcast();
  final List<Map<String, dynamic>> receivedHistory = [];

  TestNode({required this.id, Hlc? initialClock})
      : clock = initialClock ?? Hlc.now(id);

  Stream<Map<String, dynamic>> get messages => _inboundController.stream;

  void deliver(Map<String, dynamic> message) {
    if (message.containsKey('hlc')) {
      final remoteHlc = Hlc.parse(message['hlc'] as String);
      clock = clock.merge(remoteHlc);
    }
    receivedHistory.add(Map<String, dynamic>.from(message));
    _inboundController.add(message);
  }

  Future<void> dispose() async {
    await _inboundController.close();
  }
}

/// In-Memory Multi-Device Network Simulation Test Harness (T0.4).
///
/// Simulates local mesh clusters, latency injection, packet dropping,
/// network partitions, and healing without requiring physical devices or binding OS sockets.
class TestCluster {
  final Map<String, TestNode> _nodes = {};
  final Set<String> _partitions = {}; // Set of "idA<->idB" bidirectional cuts
  Duration latency = Duration.zero;
  double packetLossRate = 0.0;
  final Random _random = Random(42); // Deterministic seed for reproducible tests
  final List<Future<void>> _inFlightDeliveries = [];

  TestCluster._();

  List<TestNode> get nodes => _nodes.values.toList();

  TestNode? getNode(String id) => _nodes[id];

  /// Spawns an in-memory cluster of [count] virtual nodes.
  static Future<TestCluster> spawn(int count) async {
    if (count < 2) {
      throw ArgumentError.value(count, 'count', 'Cluster must have at least 2 nodes');
    }
    final cluster = TestCluster._();
    for (var i = 0; i < count; i++) {
      final id = 'node-$i';
      cluster._nodes[id] = TestNode(id: id);
    }
    return cluster;
  }

  String _partitionKey(String a, String b) {
    return a.compareTo(b) < 0 ? '$a<->$b' : '$b<->$a';
  }

  /// Partitions the network by cutting all communication links between [groupA] and [groupB].
  void partition(List<String> groupA, List<String> groupB) {
    for (final a in groupA) {
      for (final b in groupB) {
        _partitions.add(_partitionKey(a, b));
      }
    }
  }

  /// Heals all active network partitions.
  void heal() {
    _partitions.clear();
  }

  /// Sends a packet from [fromId] to [toId] honoring latency, loss, and partitions.
  Future<void> send({
    required String fromId,
    required String toId,
    required Map<String, dynamic> packet,
  }) async {
    final sender = _nodes[fromId];
    final receiver = _nodes[toId];

    if (sender == null || receiver == null) {
      throw ArgumentError('Sender or receiver node not found');
    }

    // Check network partition
    if (_partitions.contains(_partitionKey(fromId, toId))) {
      return; // Dropped silently by partition
    }

    // Check packet loss injection
    if (packetLossRate > 0.0 && _random.nextDouble() < packetLossRate) {
      return; // Dropped by simulated loss
    }

    // Attach sender HLC if not present
    final packetToSend = Map<String, dynamic>.from(packet);
    if (!packetToSend.containsKey('hlc')) {
      sender.clock = sender.clock.increment();
      packetToSend['hlc'] = sender.clock.toString();
    }

    if (latency > Duration.zero) {
      final delivery = Future.delayed(latency, () {
        receiver.deliver(packetToSend);
      });
      _inFlightDeliveries.add(delivery);
      await delivery;
    } else {
      receiver.deliver(packetToSend);
    }
  }

  /// Broadcasts a packet from [fromId] to all other nodes in the cluster.
  Future<void> broadcast({
    required String fromId,
    required Map<String, dynamic> packet,
  }) async {
    final futures = <Future<void>>[];
    for (final targetId in _nodes.keys) {
      if (targetId != fromId) {
        futures.add(send(fromId: fromId, toId: targetId, packet: packet));
      }
    }
    await Future.wait(futures);
  }

  /// Waits until all in-flight delayed packets have completed.
  Future<void> settle({Duration timeout = const Duration(seconds: 2)}) async {
    if (_inFlightDeliveries.isEmpty) return;
    await Future.wait(_inFlightDeliveries).timeout(timeout, onTimeout: () => []);
    _inFlightDeliveries.clear();
  }

  /// Disposes all nodes in the cluster.
  Future<void> dispose() async {
    for (final node in _nodes.values) {
      await node.dispose();
    }
    _nodes.clear();
    _partitions.clear();
    _inFlightDeliveries.clear();
  }
}

