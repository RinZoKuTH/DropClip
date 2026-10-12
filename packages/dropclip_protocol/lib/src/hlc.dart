import 'package:meta/meta.dart';
import 'constants.dart';

/// Thrown when a remote HLC physical timestamp exceeds allowable clock drift.
class ClockDriftException implements Exception {
  final int localPhysicalTimeMs;
  final int remotePhysicalTimeMs;
  final int maxDriftMs;

  const ClockDriftException({
    required this.localPhysicalTimeMs,
    required this.remotePhysicalTimeMs,
    required this.maxDriftMs,
  });

  int get driftMs => remotePhysicalTimeMs - localPhysicalTimeMs;

  @override
  String toString() =>
      'ClockDriftException: Remote timestamp ($remotePhysicalTimeMs ms) drifts by '
      '$driftMs ms ahead of local clock ($localPhysicalTimeMs ms), exceeding maximum '
      'allowable drift of $maxDriftMs ms.';
}

/// Hybrid Logical Clock (HLC) implementation according to PROTO-DC-V2.0 §10
/// and ADR-008.
///
/// HLC couples physical time `l` (milliseconds since epoch) with a logical
/// counter `c` and deterministic node tie-breaker `d`.
///
/// **Clock Drift Bounds & Trade-offs:**
/// Forward clock drift is bounded by [ProtocolConstants.maxClockDriftMs] (60s)
/// during [merge]. If a remote peer presents a physical time `l` more than 60s
/// ahead of the local wall clock, a [ClockDriftException] is thrown to prevent
/// future-timestamp hijacking of Last-Writer-Wins (LWW).
/// In exchange, a node that remains offline with a severely lagging physical clock
/// will lose LWW resolution against fresher cluster updates upon reconnect.
@immutable
class Hlc implements Comparable<Hlc> {
  /// Physical component: maximum wall clock timestamp observed so far (ms).
  final int l;

  /// Logical counter for events occurring within the same physical millisecond.
  final int c;

  /// Node / Device identifier (UUID string, normalized to lowercase) for deterministic tie-breaking.
  final String d;

  Hlc({
    required this.l,
    required this.c,
    required String d,
  }) : d = d.toLowerCase().trim();

  /// Raw constructor without string normalization.
  const Hlc.raw({
    required this.l,
    required this.c,
    required this.d,
  });

  /// Creates a new HLC initialized to current time or provided [physicalTimeMs].
  factory Hlc.now(String deviceId, [int? physicalTimeMs]) {
    final now = physicalTimeMs ?? DateTime.now().millisecondsSinceEpoch;
    return Hlc(l: now, c: 0, d: deviceId);
  }

  /// Parses an HLC from wire string representation `"<l>:<c>:<d>"`
  /// (used in `X-DropClip-HLC` HTTP header and logging).
  factory Hlc.parse(String s) {
    final parts = s.split(':');
    if (parts.length < 3) {
      throw FormatException('Invalid HLC string representation: "$s" (expected l:c:d)');
    }
    final l = int.tryParse(parts[0]);
    final c = int.tryParse(parts[1]);
    final d = parts.sublist(2).join(':').trim();
    if (l == null || c == null || d.isEmpty) {
      throw FormatException('Invalid HLC format: "$s"');
    }
    return Hlc(l: l, c: c, d: d);
  }

  /// Safely parses an HLC from wire string representation or returns null.
  static Hlc? tryParse(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    try {
      return Hlc.parse(s);
    } catch (_) {
      return null;
    }
  }

  /// Parses an HLC from JSON representation `{"l": int, "c": int, "d": string}`.
  factory Hlc.fromJson(Map<String, dynamic> json) {
    return Hlc(
      l: json['l'] as int,
      c: json['c'] as int,
      d: json['d'] as String,
    );
  }

  /// Serializes this HLC to JSON map.
  Map<String, dynamic> toJson() => {
        'l': l,
        'c': c,
        'd': d,
      };

  /// Advances the clock upon a local event.
  ///
  /// [physicalTimeMs] is the current local wall clock time in milliseconds.
  Hlc tick(int physicalTimeMs) {
    if (physicalTimeMs > l) {
      return Hlc(l: physicalTimeMs, c: 0, d: d);
    } else {
      return Hlc(l: l, c: c + 1, d: d);
    }
  }

  /// Merges a remote HLC timestamp upon receiving an inbound event.
  ///
  /// [remote] is the inbound event's HLC.
  /// [physicalTimeMs] is the current local wall clock time in milliseconds.
  /// [maxDriftMs] is the maximum allowable forward clock drift threshold
  /// (defaults to [ProtocolConstants.maxClockDriftMs] = 60,000 ms).
  ///
  /// Throws [ClockDriftException] if `remote.l - physicalTimeMs > maxDriftMs`.
  Hlc merge(
    Hlc remote,
    int physicalTimeMs, {
    int maxDriftMs = ProtocolConstants.maxClockDriftMs,
  }) {
    if (remote.l - physicalTimeMs > maxDriftMs) {
      throw ClockDriftException(
        localPhysicalTimeMs: physicalTimeMs,
        remotePhysicalTimeMs: remote.l,
        maxDriftMs: maxDriftMs,
      );
    }

    final lMax = [l, remote.l, physicalTimeMs].reduce((a, b) => a > b ? a : b);

    int cNext;
    if (lMax == l && lMax == remote.l) {
      cNext = (c > remote.c ? c : remote.c) + 1;
    } else if (lMax == l) {
      cNext = c + 1;
    } else if (lMax == remote.l) {
      cNext = remote.c + 1;
    } else {
      cNext = 0;
    }

    return Hlc(l: lMax, c: cNext, d: d);
  }

  /// Compares two HLCs according to total order rules:
  /// 1. Highest `l` wins.
  /// 2. If `l` is equal, highest `c` wins.
  /// 3. If `c` is equal, highest `d` string (lexicographical) wins.
  @override
  int compareTo(Hlc other) {
    if (l != other.l) {
      return l.compareTo(other.l);
    }
    if (c != other.c) {
      return c.compareTo(other.c);
    }
    return d.compareTo(other.d);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Hlc &&
          runtimeType == other.runtimeType &&
          l == other.l &&
          c == other.c &&
          d == other.d;

  @override
  int get hashCode => Object.hash(l, c, d);

  @override
  String toString() => '$l:$c:$d';
}


