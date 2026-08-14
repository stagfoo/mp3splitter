import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:path_provider/path_provider.dart';

import 'mp3_export.dart' show stripExtension;

/// Thrown when ffmpeg fails to pull audio out of a video — no audio track,
/// an unsupported container/codec, a corrupt file, or any other ffmpeg
/// error. [message] is ffmpeg's own log output, which is usually specific
/// enough to show the user directly (e.g. "does not contain any stream").
class VideoExtractionException implements Exception {
  VideoExtractionException(this.message);
  final String message;

  @override
  String toString() => 'VideoExtractionException: $message';
}

/// "/storage/emulated/0/Movies/clip.mp4" -> "clip.mp4".
String videoFileNameFrom(String path) =>
    path.split(Platform.pathSeparator).last;

/// Where a given video's extracted audio gets written: this app's
/// documents directory, named after the video with its extension swapped
/// for ".mp3", grouped the same way exportSegments groups split output
/// under exports/ (see mp3_export.dart).
Future<String> mp3OutputPathFor(String videoPath) async {
  final baseName = stripExtension(videoFileNameFrom(videoPath));
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}/extracted');
  await dir.create(recursive: true);
  return '${dir.path}/$baseName.mp3';
}

/// The ffmpeg arguments to pull just the audio out of [inputPath] and
/// encode it to mp3 at [outputPath]. `-vn` drops the video stream entirely
/// so ffmpeg never has to decode it; `-q:a 2` is LAME's VBR quality 2
/// (roughly 170-210kbps, "extremely high" per LAME's own scale — no reason
/// to go higher for what's ultimately a listen-and-cut workflow). `-y`
/// overwrites a stale file left over from a previous extraction of the
/// same video without prompting.
List<String> buildExtractAudioArgs({
  required String inputPath,
  required String outputPath,
}) => [
  '-y',
  '-i',
  inputPath,
  '-vn',
  '-acodec',
  'libmp3lame',
  '-q:a',
  '2',
  outputPath,
];

/// Extracts the audio track from [videoPath], encodes it to mp3, and
/// returns the path it was written to.
Future<String> extractAudioToMp3(String videoPath) async {
  final outputPath = await mp3OutputPathFor(videoPath);
  final args = buildExtractAudioArgs(
    inputPath: videoPath,
    outputPath: outputPath,
  );

  final session = await FFmpegKit.executeWithArguments(args);
  final returnCode = await session.getReturnCode();

  if (!ReturnCode.isSuccess(returnCode)) {
    final logs = (await session.getAllLogsAsString())?.trim();
    throw VideoExtractionException(
      logs != null && logs.isNotEmpty
          ? logs
          : 'ffmpeg exited with code ${returnCode?.getValue()}',
    );
  }

  return outputPath;
}
