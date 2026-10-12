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
  static final RegExp _bidiOverrideRegex = RegExp(r'[\u202A-\u202E\u2066-\u2069]');
  static final RegExp _reservedDeviceNames = RegExp(
    r'^(CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|COM[0-9\u00B9\u00B2\u00B3]|LPT[0-9\u00B9\u00B2\u00B3])$',
    caseSensitive: false,
  );

  /// Validates relative wire path format using forward slashes.
  /// Note: Path strings are validated for compliance and security constraints;
  /// Unicode NFC normalization should be applied by the platform filesystem adapter.
  /// Throws [InvalidPathException] if any vulnerability or format violation is detected.
  static String sanitize(String input) {
    if (input.isEmpty) {
      throw InvalidPathException('Path cannot be empty');
    }
    if (utf8.encode(input).length > 4096) {
      throw InvalidPathException('Total path length exceeds 4096 bytes');
    }
    if (_bidiOverrideRegex.hasMatch(input)) {
      throw InvalidPathException('Unicode bidirectional override characters are not permitted');
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

  /// Validates a collection of offer paths and detects case-insensitive collisions.
  ///
  /// Throws [InvalidPathException] if any individual path is invalid or if
  /// two paths collide under case-insensitive comparison (critical for Windows/macOS).
  static List<String> validateOfferPaths(List<String> paths) {
    final sanitizedPaths = <String>[];
    final lowercasedSet = <String>{};
    for (final p in paths) {
      final sanitized = sanitize(p);
      final lower = sanitized.toLowerCase();
      if (!lowercasedSet.add(lower)) {
        throw InvalidPathException('Case-insensitive path collision detected: "$sanitized"');
      }
      sanitizedPaths.add(sanitized);
    }
    return sanitizedPaths;
  }
}


