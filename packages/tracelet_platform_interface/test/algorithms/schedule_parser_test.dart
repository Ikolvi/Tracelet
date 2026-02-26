import 'package:flutter_test/flutter_test.dart';
import 'package:tracelet_platform_interface/tracelet_platform_interface.dart';

void main() {
  group('ScheduleParser', () {
    test('isWithinSchedule returns true for matching window', () {
      // Monday at 10:00.
      final now = DateTime(2024, 1, 8, 10, 0); // Monday = weekday 1.
      expect(ScheduleParser.isWithinSchedule(['1-5 09:00-17:00'], now), isTrue);
    });

    test('isWithinSchedule returns false outside time window', () {
      // Monday at 18:00.
      final now = DateTime(2024, 1, 8, 18, 0);
      expect(
        ScheduleParser.isWithinSchedule(['1-5 09:00-17:00'], now),
        isFalse,
      );
    });

    test('isWithinSchedule returns false outside day window', () {
      // Sunday at 10:00.
      final now = DateTime(2024, 1, 7, 10, 0); // Sunday = weekday 7.
      expect(
        ScheduleParser.isWithinSchedule(['1-5 09:00-17:00'], now),
        isFalse,
      );
    });

    test('isWithinSchedule weekend schedule works', () {
      // Saturday at 12:00.
      final now = DateTime(2024, 1, 6, 12, 0); // Saturday = weekday 6.
      expect(ScheduleParser.isWithinSchedule(['6-7 08:00-20:00'], now), isTrue);
    });

    test('isWithinSchedule matches any of multiple schedules', () {
      final now = DateTime(2024, 1, 6, 10, 0); // Saturday.
      expect(
        ScheduleParser.isWithinSchedule([
          '1-5 09:00-17:00', // Weekdays — no match.
          '6-7 08:00-20:00', // Weekend — match.
        ], now),
        isTrue,
      );
    });

    test('isWithinSchedule returns false for empty list', () {
      expect(ScheduleParser.isWithinSchedule([]), isFalse);
    });

    test('matchesSchedule end time is exclusive', () {
      // Monday at exactly 17:00 — outside "09:00-17:00" (exclusive end).
      final now = DateTime(2024, 1, 8, 17, 0);
      expect(ScheduleParser.matchesSchedule('1-5 09:00-17:00', now), isFalse);
    });

    test('matchesSchedule start time is inclusive', () {
      // Monday at exactly 09:00 — inside "09:00-17:00" (inclusive start).
      final now = DateTime(2024, 1, 8, 9, 0);
      expect(ScheduleParser.matchesSchedule('1-5 09:00-17:00', now), isTrue);
    });

    test('matchesSchedule returns false for malformed string', () {
      final now = DateTime(2024, 1, 8, 10, 0);
      expect(ScheduleParser.matchesSchedule('invalid', now), isFalse);
      expect(ScheduleParser.matchesSchedule('1-5', now), isFalse);
      expect(ScheduleParser.matchesSchedule('1-5 09:00', now), isFalse);
      expect(ScheduleParser.matchesSchedule('', now), isFalse);
    });

    test('parse returns ScheduleWindow for valid input', () {
      final window = ScheduleParser.parse('1-5 09:00-17:00');
      expect(window, isNotNull);
      expect(window!.dayStart, 1);
      expect(window.dayEnd, 5);
      expect(window.startMinutes, 9 * 60);
      expect(window.endMinutes, 17 * 60);
      expect(window.startTime, '09:00');
      expect(window.endTime, '17:00');
    });

    test('parse returns null for invalid input', () {
      expect(ScheduleParser.parse('invalid'), isNull);
      expect(ScheduleParser.parse(''), isNull);
    });

    test('calculateNextAlarms returns future times', () {
      final now = DateTime(2024, 1, 8, 10, 0);
      final alarms = ScheduleParser.calculateNextAlarms('1-5 09:00-17:00', now);

      // Start is 09:00 but we're past that → next day.
      expect(alarms.start, isNotNull);
      expect(alarms.start!.isAfter(now), isTrue);
      expect(alarms.start!.hour, 9);

      // Stop is 17:00 today.
      expect(alarms.stop, isNotNull);
      expect(alarms.stop!.isAfter(now), isTrue);
      expect(alarms.stop!.hour, 17);
    });

    test('calculateNextAlarms handles midnight crossing', () {
      final now = DateTime(2024, 1, 8, 23, 0);
      final alarms = ScheduleParser.calculateNextAlarms('1-5 09:00-17:00', now);

      // Both times are before now → both pushed to next day.
      expect(alarms.start!.day, now.day + 1);
      expect(alarms.stop!.day, now.day + 1);
    });

    test('ScheduleWindow toString formats correctly', () {
      final window = ScheduleWindow(
        dayStart: 1,
        dayEnd: 5,
        startMinutes: 540,
        endMinutes: 1020,
      );
      expect(window.toString(), contains('days=1-5'));
      expect(window.toString(), contains('09:00'));
      expect(window.toString(), contains('17:00'));
    });

    test('single-digit hours and minutes are zero-padded', () {
      final window = ScheduleParser.parse('1-7 08:05-09:30');
      expect(window, isNotNull);
      expect(window!.startTime, '08:05');
      expect(window.endTime, '09:30');
    });
  });
}
