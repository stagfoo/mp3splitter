import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';

/// Thrown when ffmpeg fails to apply a speed change — a corrupt segment, an
/// unsupported input, or any other ffmpeg error. [message] is ffmpeg's own
/// log output, which is usually specific enough to show the user directly.
class SpeedChangeException implements Exception {
  SpeedChangeException(this.message);
  final String message;

  @override
  String toString() => 'SpeedChangeException: $message';
}

/// 44.1kHz is by far the most common mp3 sample rate — used only if ffprobe
/// can't determine the real one, which should be rare for a well-formed
/// mp3 file.
const fallbackSampleRate = 44100;

/// Reads [path]'s audio sample rate via ffprobe, falling back to
/// [fallbackSampleRate] if no audio stream is found or it doesn't report one.
Future<int> probeSampleRate(String path) async {
  final session = await FFprobeKit.getMediaInformation(path);
  final streams = session.getMediaInformation()?.getStreams() ?? [];
  for (final stream in streams) {
    if (stream.getType() == 'audio') {
      final rate = int.tryParse(stream.getSampleRate() ?? '');
      if (rate != null && rate > 0) return rate;
    }
  }
  return fallbackSampleRate;
}

/// The ffmpeg arguments for a "vinyl slowdown": [speed] (< 1.0) both slows
/// the track down and drops its pitch, by reinterpreting the audio at a
/// lower sample rate (`asetrate`) and then resampling back to
/// [sourceSampleRate] so the output file's declared sample rate matches the
/// input (`aresample`) — the file plays back slower and lower without a
/// separate pitch-shift step. This is a real decode/DSP/re-encode pass,
/// unlike the byte-copy splitting elsewhere in this app; it should never be
/// run with speed == 1.0 (nothing to change, and it'd cost a needless
/// re-encode).
List<String> buildSlowDownArgs({
  required String inputPath,
  required String outputPath,
  required double speed,
  required int sourceSampleRate,
}) {
  final targetRate = (sourceSampleRate * speed).round();
  return [
    '-y',
    '-i',
    inputPath,
    '-filter:a',
    'asetrate=$targetRate,aresample=$sourceSampleRate',
    '-acodec',
    'libmp3lame',
    '-q:a',
    '2',
    outputPath,
  ];
}

/// Slows the file at [path] down in place by [speed] (e.g. 0.8 for 80%
/// speed), dropping its pitch along with its tempo. Writes to a sibling
/// temp file first and swaps it in, so a failed ffmpeg run never leaves
/// [path] truncated or corrupt.
Future<void> slowDownInPlace(
  String path, {
  required double speed,
  required int sourceSampleRate,
}) async {
  assert(speed > 0 && speed < 1.0);

  final tempPath = '$path.slowed.mp3';
  final args = buildSlowDownArgs(
    inputPath: path,
    outputPath: tempPath,
    speed: speed,
    sourceSampleRate: sourceSampleRate,
  );

  final session = await FFmpegKit.executeWithArguments(args);
  final returnCode = await session.getReturnCode();
  final temp = File(tempPath);

  if (!ReturnCode.isSuccess(returnCode)) {
    if (await temp.exists()) await temp.delete();
    final logs = (await session.getAllLogsAsString())?.trim();
    throw SpeedChangeException(
      logs != null && logs.isNotEmpty
          ? logs
          : 'ffmpeg exited with code ${returnCode?.getValue()}',
    );
  }

  final original = File(path);
  if (await original.exists()) await original.delete();
  await temp.rename(path);
}
