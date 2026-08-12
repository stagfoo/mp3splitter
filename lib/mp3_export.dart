import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'mp3_frame_parser.dart';
import 'mp3_splitter.dart';

/// One segment written to disk.
class ExportedFile {
  const ExportedFile({
    required this.file,
    required this.result,
  });

  final File file;
  final Mp3SplitResult result;

  int get sizeBytes => result.bytes.length;
}

/// The message bundled for [_splitInIsolate] — [compute] takes exactly one
/// argument, so the pieces [splitMp3] actually needs travel together.
typedef _SplitRequest = ({ParsedMp3 parsed, List<double> cutMillis});

List<Mp3SplitResult> _splitInIsolate(_SplitRequest request) =>
    splitMp3(request.parsed, request.cutMillis);

/// Splits [parsed] at [cutMillis] and writes each piece to its own file
/// under this app's documents directory, named after [sourceFileName].
///
/// The actual byte-copying (potentially large for a long track) runs off the
/// UI thread via [compute]; only the file-writing happens on the main
/// isolate, since that's I/O rather than CPU work.
Future<List<ExportedFile>> exportSegments({
  required ParsedMp3 parsed,
  required List<double> cutMillis,
  required String sourceFileName,
}) async {
  final results = await compute(
    _splitInIsolate,
    (parsed: parsed, cutMillis: cutMillis),
  );

  final baseName = stripExtension(sourceFileName);
  final dir = await _exportDirectoryFor(baseName);

  final files = <ExportedFile>[];
  for (final result in results) {
    final file = File('${dir.path}/${segmentFileName(baseName, result)}');
    await file.writeAsBytes(result.bytes, flush: true);
    files.add(ExportedFile(file: file, result: result));
  }
  return files;
}

/// The on-disk filename for one exported segment, e.g. "podcast_part2.mp3".
String segmentFileName(String baseName, Mp3SplitResult result) =>
    '${baseName}_part${result.index + 1}.mp3';

Future<Directory> _exportDirectoryFor(String baseName) async {
  final docs = await getApplicationDocumentsDirectory();
  // Namespaced per source track, so splitting the same file twice doesn't
  // silently overwrite the first attempt's output.
  final dir = Directory('${docs.path}/exports/$baseName');
  await dir.create(recursive: true);
  return dir;
}

/// "track.mp3" -> "track". A name with no extension is returned unchanged.
String stripExtension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot <= 0 ? fileName : fileName.substring(0, dot);
}
