/// Pure-Dart schedule parsing and matching.
///
/// Replaces the schedule-matching logic previously duplicated in native
/// Kotlin (`ScheduleManager.matchesSchedule`) and Swift
/// (`ScheduleManager.isWithinSchedule` / `parseScheduleEntry`).
///
/// Schedule strings use the format `"dayStart-dayEnd HH:mm-HH:mm"` where
/// days are ISO 8601 day-of-week numbers (1 = Monday, 7 = Sunday).
///
/// **This is a pure Dart implementation** — no native code required. It runs
/// identically on Android, iOS, web, macOS, Linux, and Windows.
///
/// ```dart
/// final active = ScheduleParser.isWithinSchedule(['1-5 09:00-17:00']);
/// print('Should track: $active');
/// ```
class ScheduleParser {
  ScheduleParser._(); // Prevent instantiation.

  /// Check whether [now] (or the current time) falls within any of the
  /// given [schedules].
  ///
  /// Each schedule string must be in `"dayStart-dayEnd HH:mm-HH:mm"` format.
  /// Returns `true` if **any** entry matches.
  static bool isWithinSchedule(List<String> schedules, [DateTime? now]) {
    if (schedules.isEmpty) return false;
    now ??= DateTime.now();

    for (final schedule in schedules) {
      if (matchesSchedule(schedule, now)) return true;
    }
    return false;
  }

  /// Check whether a single [schedule] string matches the given [now] time.
  ///
  /// Format: `"dayStart-dayEnd HH:mm-HH:mm"`
  ///
  /// - Days are ISO 8601: 1 = Monday, 7 = Sunday.
  /// - The time range is inclusive of start, exclusive of end.
  ///
  /// Returns `false` for malformed strings.
  static bool matchesSchedule(String schedule, DateTime now) {
    final parts = schedule.trim().split(' ');
    if (parts.length != 2) return false;

    final dayRange = parts[0].split('-');
    final timeRange = parts[1].split('-');
    if (dayRange.length != 2 || timeRange.length != 2) return false;

    try {
      final dayStart = int.parse(dayRange[0]);
      final dayEnd = int.parse(dayRange[1]);

      // Dart DateTime.weekday is already ISO 8601 (1=Monday, 7=Sunday).
      final isoDay = now.weekday;
      if (isoDay < dayStart || isoDay > dayEnd) return false;

      final startMinutes = _parseTime(timeRange[0]);
      final endMinutes = _parseTime(timeRange[1]);
      if (startMinutes == null || endMinutes == null) return false;

      final currentMinutes = now.hour * 60 + now.minute;
      return currentMinutes >= startMinutes && currentMinutes < endMinutes;
    } catch (_) {
      return false;
    }
  }

  /// Parse a schedule string into a [ScheduleWindow], or `null` if
  /// the format is invalid.
  ///
  /// Useful for UI display or calculating next alarm times.
  static ScheduleWindow? parse(String schedule) {
    final parts = schedule.trim().split(' ');
    if (parts.length != 2) return null;

    final dayRange = parts[0].split('-');
    final timeRange = parts[1].split('-');
    if (dayRange.length != 2 || timeRange.length != 2) return null;

    try {
      final dayStart = int.parse(dayRange[0]);
      final dayEnd = int.parse(dayRange[1]);
      final startMinutes = _parseTime(timeRange[0]);
      final endMinutes = _parseTime(timeRange[1]);
      if (startMinutes == null || endMinutes == null) return null;

      return ScheduleWindow(
        dayStart: dayStart,
        dayEnd: dayEnd,
        startMinutes: startMinutes,
        endMinutes: endMinutes,
      );
    } catch (_) {
      return null;
    }
  }

  /// Calculate the next start and stop timestamps from a schedule string.
  ///
  /// Returns a record with nullable [DateTime] values. Either may be `null`
  /// if the schedule string is malformed.
  static ({DateTime? start, DateTime? stop}) calculateNextAlarms(
    String schedule, [
    DateTime? now,
  ]) {
    now ??= DateTime.now();
    final window = parse(schedule);
    if (window == null) return (start: null, stop: null);

    final startHour = window.startMinutes ~/ 60;
    final startMinute = window.startMinutes % 60;
    final endHour = window.endMinutes ~/ 60;
    final endMinute = window.endMinutes % 60;

    var start = DateTime(now.year, now.month, now.day, startHour, startMinute);
    if (start.isBefore(now)) {
      start = start.add(const Duration(days: 1));
    }

    var stop = DateTime(now.year, now.month, now.day, endHour, endMinute);
    if (stop.isBefore(now)) {
      stop = stop.add(const Duration(days: 1));
    }

    return (start: start, stop: stop);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private
  // ─────────────────────────────────────────────────────────────────────────

  /// Parse `"HH:mm"` to minutes since midnight.
  static int? _parseTime(String str) {
    final parts = str.split(':');
    if (parts.length != 2) return null;
    final hours = int.tryParse(parts[0]);
    final minutes = int.tryParse(parts[1]);
    if (hours == null || minutes == null) return null;
    return hours * 60 + minutes;
  }
}

/// A parsed schedule window.
///
/// Represents the day-range and time-range extracted from a schedule string.
class ScheduleWindow {
  const ScheduleWindow({
    required this.dayStart,
    required this.dayEnd,
    required this.startMinutes,
    required this.endMinutes,
  });

  /// Start day of week (ISO 8601: 1 = Monday).
  final int dayStart;

  /// End day of week (ISO 8601: 7 = Sunday).
  final int dayEnd;

  /// Start time as minutes since midnight.
  final int startMinutes;

  /// End time as minutes since midnight.
  final int endMinutes;

  /// Start time formatted as `"HH:mm"`.
  String get startTime =>
      '${(startMinutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(startMinutes % 60).toString().padLeft(2, '0')}';

  /// End time formatted as `"HH:mm"`.
  String get endTime =>
      '${(endMinutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(endMinutes % 60).toString().padLeft(2, '0')}';

  @override
  String toString() =>
      'ScheduleWindow(days=$dayStart-$dayEnd, time=$startTime-$endTime)';
}
