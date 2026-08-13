import 'package:flutter_test/flutter_test.dart';
import 'package:mp3splitter/crash_log.dart';

void main() {
  group('formatCrashEntry', () {
    test('includes the ISO-8601 timestamp and error text', () {
      final entry = formatCrashEntry(
        timestamp: DateTime.utc(2026, 8, 4, 12, 30),
        error: Exception('boom'),
      );

      expect(entry, contains('2026-08-04T12:30'));
      expect(entry, contains('boom'));
    });

    test('includes the stack trace when provided', () {
      final entry = formatCrashEntry(
        timestamp: DateTime.utc(2026, 8, 4),
        error: 'err',
        stackTrace: StackTrace.fromString('#0 someFunction'),
      );

      expect(entry, contains('someFunction'));
    });

    test('omits a stack trace section when none is given', () {
      final entry = formatCrashEntry(
        timestamp: DateTime.utc(2026, 8, 4),
        error: 'err',
      );

      expect(entry.split('\n'), hasLength(2));
    });

    test('a non-Exception error object still formats via toString', () {
      final entry = formatCrashEntry(
        timestamp: DateTime.utc(2026, 8, 4),
        error: 'a plain string thrown as an error',
      );

      expect(entry, contains('a plain string thrown as an error'));
    });
  });

  group('appendCrashEntry', () {
    test('the first entry on an empty log is just that entry', () {
      expect(appendCrashEntry('', 'entry-1'), 'entry-1');
    });

    test('entries under the cap all survive', () {
      var log = '';
      for (var i = 0; i < 5; i++) {
        log = appendCrashEntry(log, 'entry-$i', maxEntries: 20);
      }

      expect(log, contains('entry-0'));
      expect(log, contains('entry-4'));
    });

    test('entries beyond the cap drop the oldest first', () {
      var log = '';
      for (var i = 0; i < 25; i++) {
        log = appendCrashEntry(log, 'entry-$i', maxEntries: 20);
      }

      expect(log, isNot(contains('entry-0\n')));
      expect(log, isNot(contains('entry-4\n')));
      expect(log, contains('entry-5'));
      expect(log, contains('entry-24'));
    });

    test('the default cap matches maxCrashLogEntries', () {
      var log = '';
      for (var i = 0; i < maxCrashLogEntries + 5; i++) {
        log = appendCrashEntry(log, 'entry-$i');
      }

      expect(log, isNot(contains('entry-0\n')));
      expect(log, contains('entry-${maxCrashLogEntries + 4}'));
    });

    test('a multi-line stack trace inside one entry is not split apart by '
        'trimming', () {
      final multiline = formatCrashEntry(
        timestamp: DateTime.utc(2026, 8, 4),
        error: 'err',
        stackTrace: StackTrace.fromString('#0 a\n#1 b\n#2 c'),
      );

      final log = appendCrashEntry(appendCrashEntry('', 'first'), multiline);

      expect(log, contains('#0 a'));
      expect(log, contains('#1 b'));
      expect(log, contains('#2 c'));
    });
  });
}
