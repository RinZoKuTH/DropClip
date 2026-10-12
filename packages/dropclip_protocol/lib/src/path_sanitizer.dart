import 'dart:convert';

/// Exception thrown when a file path violates DropClip security constraints
class InvalidPathException implements Exception {
  final String reason;
  InvalidPathException(this.reason);

  @override
  String toString() => 'InvalidPathException: $reason';
}

/// Sanitizes wire file paths according to PROTO-DC-V2.0 §17.3 and NFR-S03
class PathSanitizer {
  PathSanitizer._();

  static final RegExp _driveLetterRegex = RegExp(r'^[A-Za-z]:');
  static final RegExp _controlCharRegex = RegExp(r'[\x00-\x1F\x7F]');
  static final RegExp _reservedCharRegex = RegExp(r'[<>:"|?*]');
  static final RegExp _reservedDeviceNames =
      RegExp(r'^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])$', caseSensitive: false);

  /// Validates and normalizes relative wire path using forward slashes.
  /// Throws [InvalidPathException] if any vulnerability is detected.
  static String sanitize(String input) {
    if (input.isEmpty) {
      throw InvalidPathException('Path cannot be empty');
    }
    if (utf8.encode(input).length > 4096) {
      throw InvalidPathException('Total path length exceeds 4096 bytes');
    }
    if (input.contains(r'\')) {
      throw InvalidPathException('Backslashes are not permitted in wire paths');
    }
    if (input.startsWith('/')) {
      throw InvalidPathException('Absolute paths are not permitted');
    }
    if (_driveLetterRegex.hasMatch(input)) {
      throw InvalidPathException('Windows drive letters are not permitted');
    }

    final parts = input.split('/');
    if (parts.length > 32) {
      throw InvalidPathException('Directory depth exceeds limit of 32');
    }

    for (final component in parts) {
      if (component.isEmpty) {
        throw InvalidPathException('Empty directory component detected (double slashes)');
      }
      if (component == '.' || component == '..') {
        throw InvalidPathException('Directory traversal components are not permitted');
      }
      if (_controlCharRegex.hasMatch(component)) {
        throw InvalidPathException('Control characters are not permitted');
      }
      if (_reservedCharRegex.hasMatch(component)) {
        throw InvalidPathException('Reserved characters (<>:"|?*) are not permitted');
      }
      if (component.endsWith('.') || component.endsWith(' ')) {
        throw InvalidPathException('Trailing dots or spaces are not permitted');
      }
      if (utf8.encode(component).length > 255) {
        throw InvalidPathException('Path component exceeds 255 bytes limit');
      }

      final stem = component.split('.').first;
      if (_reservedDeviceNames.hasMatch(stem)) {
        throw InvalidPathException('Reserved device name ($stem) is not permitted');
      }
    }

    return parts.join('/');
  }
}
