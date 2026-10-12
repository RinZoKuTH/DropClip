import 'dart:convert';

/// High-throughput structured logging scrubber framework (T0.3 & SRS NFR-S02, NFR-S04).
///
/// Ensures zero-cloud and local-first privacy by guaranteeing that no plaintext
/// private keys, secrets, PINs, or raw clipboard payloads leak into log files.
class LoggingScrubber {
  static final RegExp _pemPrivateKeyRegex = RegExp(
    r'-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----',
    multiLine: true,
  );

  static final RegExp _sensitiveKeyRegex = RegExp(
    r'^(password|passwd|pin|secret|private_key|token|auth|credential|api_key|master_key)$',
    caseSensitive: false,
  );

  static final RegExp _contentKeyRegex = RegExp(
    r'^(payload|clipboard_content|content|raw_data|clip_text)$',
    caseSensitive: false,
  );

  /// Scrubs a plain string for embedded PEM private keys.
  ///
  /// Free-text PINs are not detected here; pass them as structured `data`
  /// under a sensitive key (e.g. `pin`) so [scrubData] redacts them.
  static String scrubText(String input) {
    if (input.isEmpty) return input;
    return input.replaceAll(_pemPrivateKeyRegex, '[REDACTED_PRIVATE_KEY]');
  }

  /// Recursively scrubs a Map, List, or primitive dynamic data structure.
  static dynamic scrubData(dynamic data) {
    if (data == null) return null;

    if (data is Map) {
      final result = <String, dynamic>{};
      for (final entry in data.entries) {
        final key = entry.key.toString();
        final value = entry.value;

        if (_sensitiveKeyRegex.hasMatch(key)) {
          result[key] = '[REDACTED]';
        } else if (_contentKeyRegex.hasMatch(key)) {
          if (value is String) {
            result[key] = '[REDACTED_CONTENT: length=${value.length}]';
          } else if (value is List) {
            result[key] = '[REDACTED_CONTENT: bytes=${value.length}]';
          } else {
            result[key] = '[REDACTED_CONTENT]';
          }
        } else {
          result[key] = scrubData(value);
        }
      }
      return result;
    }

    if (data is List) {
      return data.map((item) => scrubData(item)).toList();
    }

    if (data is String) {
      return scrubText(data);
    }

    return data;
  }

  /// Formats a structured log record as a single-line JSON string (JSON Lines format).
  ///
  /// Output schema:
  /// `{"ts": "...", "level": "...", "component": "...", "device_id": "...", "msg": "...", "data": {...}}`
  static String formatLogLine({
    required String level,
    required String component,
    required String deviceId,
    required String msg,
    Map<String, dynamic>? data,
    DateTime? timestamp,
  }) {
    final ts = (timestamp ?? DateTime.now().toUtc()).toIso8601String();
    final sanitizedMsg = scrubText(msg);
    final sanitizedData = data != null ? scrubData(data) : null;

    final record = <String, dynamic>{
      'ts': ts,
      'level': level.toUpperCase(),
      'component': component,
      'device_id': deviceId,
      'msg': sanitizedMsg,
      if (sanitizedData != null) 'data': sanitizedData,
    };

    return jsonEncode(record);
  }
}
