// Pure logic for the on-device crash log: formatting one crash and trimming
// the growing log to a bounded size. No Flutter or dart:io dependency —
// kept separate from the platform glue in crash_log_file.dart so this part
// is directly unit-testable, the same split as mp3_frame_parser.dart/
// cut_timeline.dart (logic) vs. mp3_export.dart (platform IO).

/// How many crashes the on-device log keeps before the oldest are dropped,
/// so a long-lived install can't grow the file without bound.
const int maxCrashLogEntries = 20;

const String _entrySeparator = '\n========================================\n';

/// Formats one crash as a self-contained, human-readable block: an
/// ISO-8601 timestamp, the error's string form, and its stack trace if
/// given. [timestamp] is a parameter rather than read internally so this
/// stays pure and deterministic for tests.
String formatCrashEntry({
  required DateTime timestamp,
  required Object error,
  StackTrace? stackTrace,
}) {
  final buffer = StringBuffer()
    ..writeln(timestamp.toIso8601String())
    ..writeln(error.toString());
  if (stackTrace != null) {
    buffer.writeln(stackTrace.toString());
  }
  return buffer.toString().trimRight();
}

/// Appends [newEntry] to [existingLog] (empty for the first-ever crash) and
/// trims the result to at most [maxEntries] most-recent entries, oldest
/// dropped first.
String appendCrashEntry(
  String existingLog,
  String newEntry, {
  int maxEntries = maxCrashLogEntries,
}) {
  final entries = existingLog.isEmpty
      ? <String>[]
      : existingLog.split(_entrySeparator);
  entries.add(newEntry);
  final trimmed = entries.length > maxEntries
      ? entries.sublist(entries.length - maxEntries)
      : entries;
  return trimmed.join(_entrySeparator);
}
