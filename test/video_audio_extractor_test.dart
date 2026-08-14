import 'package:flutter_test/flutter_test.dart';
import 'package:mp3splitter/video_audio_extractor.dart';

void main() {
  group('videoFileNameFrom', () {
    test('strips a unix-style directory path', () {
      expect(
        videoFileNameFrom('/storage/emulated/0/Movies/clip.mp4'),
        'clip.mp4',
      );
    });

    test('a bare filename with no path is returned unchanged', () {
      expect(videoFileNameFrom('clip.mov'), 'clip.mov');
    });
  });

  group('buildExtractAudioArgs', () {
    test('drops the video stream and encodes to mp3', () {
      final args = buildExtractAudioArgs(
        inputPath: '/tmp/in.mp4',
        outputPath: '/tmp/out.mp3',
      );

      expect(args, [
        '-y',
        '-i',
        '/tmp/in.mp4',
        '-vn',
        '-acodec',
        'libmp3lame',
        '-q:a',
        '2',
        '/tmp/out.mp3',
      ]);
    });

    test('the input and output paths are passed through untouched', () {
      final args = buildExtractAudioArgs(
        inputPath: '/a path with spaces/in.mov',
        outputPath: '/another one/out.mp3',
      );

      expect(args, contains('/a path with spaces/in.mov'));
      expect(args, contains('/another one/out.mp3'));
    });
  });
}
