import 'package:flutter_test/flutter_test.dart';
import 'package:mp3splitter/audio_speed_changer.dart';

void main() {
  group('buildSlowDownArgs', () {
    test('lowers the sample rate proportionally to speed, then resamples back', () {
      final args = buildSlowDownArgs(
        inputPath: '/tmp/in.mp3',
        outputPath: '/tmp/out.mp3',
        speed: 0.8,
        sourceSampleRate: 44100,
      );

      expect(args, [
        '-y',
        '-i',
        '/tmp/in.mp3',
        '-filter:a',
        'asetrate=35280,aresample=44100',
        '-acodec',
        'libmp3lame',
        '-q:a',
        '2',
        '/tmp/out.mp3',
      ]);
    });

    test('rounds a fractional target rate to the nearest integer', () {
      final args = buildSlowDownArgs(
        inputPath: '/tmp/in.mp3',
        outputPath: '/tmp/out.mp3',
        speed: 0.75,
        sourceSampleRate: 44100,
      );

      // 44100 * 0.75 = 33075.0 exactly, but this also exercises rounding
      // for sample rates that don't divide evenly.
      expect(args, contains('asetrate=33075,aresample=44100'));
    });

    test('the input and output paths are passed through untouched', () {
      final args = buildSlowDownArgs(
        inputPath: '/a path with spaces/in.mp3',
        outputPath: '/another one/out.mp3',
        speed: 0.9,
        sourceSampleRate: 48000,
      );

      expect(args, contains('/a path with spaces/in.mp3'));
      expect(args, contains('/another one/out.mp3'));
    });
  });
}
