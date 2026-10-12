import 'package:meta/meta.dart';

/// Hybrid Logical Clock (HLC) implementation according to PROTO-DC-V2.0 §10
/// and ADR-008.
///
/// HLC couples physical time `l` (milliseconds since epoch) with a logical
/// counter `c` and deterministic node tie-breaker `d`.
@immutable
class Hlc implements Comparable<Hlc> {
  /// Physical component: maximum wall clock timestamp observed so far (ms).
  final int l;

  /// Logical counter for events occurring within the same physical millisecond.
  final int c;

  /// Node / Device identifier (UUID string) for deterministic tie-breaking.
  final String d;

  const Hlc({
    required this.l,
    required this.c,
    required this.d,
  });

  /// Creates a new HLC initialized to current time or provided [physicalTimeMs].
  factory Hlc.now(String deviceId, [int? physicalTimeMs]) {
    final now = physicalTimeMs ?? DateTime.now().millisecondsSinceEpoch;
    return Hlc(l: now, c: 0, d: deviceId);
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
  Hlc merge(Hlc remote, int physicalTimeMs) {
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

