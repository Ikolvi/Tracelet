import 'package:meta/meta.dart';

/// Event fired during HTTP sync operations.
///
/// Reports success/failure, HTTP status code, and the server response text.
@immutable
class HttpEvent {
  /// Creates a new [HttpEvent].
  const HttpEvent({
    required this.success,
    required this.status,
    this.responseText = '',
  });

  /// Whether the HTTP request succeeded (2xx).
  final bool success;

  /// The HTTP status code returned by the server.
  final int status;

  /// The raw response body text from the server.
  final String responseText;

  /// Creates an [HttpEvent] from a platform map.
  factory HttpEvent.fromMap(Map<String, Object?> map) {
    return HttpEvent(
      success: _ensureBool(map['success'], fallback: false),
      status: _ensureInt(map['status'], fallback: 0),
      responseText: map['responseText'] as String? ?? '',
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'success': success,
      'status': status,
      'responseText': responseText,
    };
  }

  @override
  String toString() =>
      'HttpEvent(success: $success, status: $status)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HttpEvent &&
          runtimeType == other.runtimeType &&
          success == other.success &&
          status == other.status;

  @override
  int get hashCode => Object.hash(success, status);
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

bool _ensureBool(Object? value, {required bool fallback}) {
  if (value is bool) return value;
  if (value is int) return value != 0;
  return fallback;
}

int _ensureInt(Object? value, {required int fallback}) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  return fallback;
}
