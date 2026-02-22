/// Shared deserialization helpers for Tracelet model classes.
///
/// These helpers handle type coercion from platform channels where:
/// - iOS sends `Map<Object?, Object?>` instead of `Map<String, Object?>`
/// - iOS sends `NSNumber` (int 0/1) instead of `bool`
/// - Android may send `String` representations of numbers
///
/// This file is internal to the `tracelet` package — it is NOT exported
/// from the barrel `tracelet.dart`.

/// Safely extract a [bool] from a platform value.
///
/// Handles int-to-bool coercion (iOS returns 0/1 for bools).
bool ensureBool(Object? value, {required bool fallback}) {
  if (value is bool) return value;
  if (value is int) return value != 0;
  return fallback;
}

/// Safely extract an [int] from a platform value.
///
/// Handles double-to-int truncation and String parsing.
int ensureInt(Object? value, {required int fallback}) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

/// Safely extract a [double] from a platform value.
///
/// Handles int-to-double promotion and String parsing.
double ensureDouble(Object? value, {required double fallback}) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

/// Safely convert any value to a [String].
///
/// Returns empty string for `null`. Handles int (epoch millis), double,
/// and other types by calling `.toString()`.
String ensureString(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  return value.toString();
}

/// Safely cast a platform value to `Map<String, Object?>?`.
///
/// iOS platform channels return `Map<Object?, Object?>` which cannot be
/// directly cast to `Map<String, Object?>`. This helper handles both types.
Map<String, Object?>? safeMap(Object? value) {
  if (value == null) return null;
  if (value is Map<String, Object?>) return value;
  if (value is Map) return Map<String, Object?>.from(value);
  return null;
}

/// Cast a platform value to `Map<String, String>`.
///
/// Converts all keys and values to strings. Returns an empty const map
/// if the value is not a [Map].
Map<String, String> castStringMap(Object? value) {
  if (value is Map) {
    return value.map<String, String>(
      (Object? k, Object? v) => MapEntry(k.toString(), v.toString()),
    );
  }
  return const <String, String>{};
}

/// Cast a platform value to `Map<String, Object?>`.
///
/// Converts keys to strings. Returns an empty const map if the value
/// is not a [Map].
Map<String, Object?> castObjectMap(Object? value) {
  if (value is Map) {
    return value.map<String, Object?>(
      (Object? k, Object? v) => MapEntry(k.toString(), v),
    );
  }
  return const <String, Object?>{};
}
