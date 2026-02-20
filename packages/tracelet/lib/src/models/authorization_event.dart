import 'package:meta/meta.dart';

/// Event fired when the HTTP Authorization token exchange occurs.
///
/// Used for OAuth-style token refresh. The server response is included
/// to help the app decide whether to update stored tokens.
@immutable
class AuthorizationEvent {
  /// Creates a new [AuthorizationEvent].
  const AuthorizationEvent({
    required this.success,
    required this.status,
    this.response = '',
  });

  /// Whether the authorization token exchange succeeded.
  final bool success;

  /// HTTP status code from the authorization endpoint.
  final int status;

  /// Response body from the authorization endpoint.
  final String response;

  /// Creates an [AuthorizationEvent] from a platform map.
  factory AuthorizationEvent.fromMap(Map<String, Object?> map) {
    return AuthorizationEvent(
      success: _ensureBool(map['success'], fallback: false),
      status: _ensureInt(map['status'], fallback: 0),
      response: map['response'] as String? ?? '',
    );
  }

  /// Serializes to a map.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'success': success,
      'status': status,
      'response': response,
    };
  }

  @override
  String toString() =>
      'AuthorizationEvent(success: $success, status: $status)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthorizationEvent &&
          runtimeType == other.runtimeType &&
          success == other.success &&
          status == other.status;

  @override
  int get hashCode => Object.hash(success, status);
}

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
