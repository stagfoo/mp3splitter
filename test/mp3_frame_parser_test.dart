import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mp3splitter/mp3_frame_parser.dart';

import 'mp3_test_support.dart';

void main() {
  group('frame header parsing', () {
    test('reads a single CBR MPEG1 frame', () {
      final data = buildFrame(bitrateKbps: 128, sampleRate: 44100);

      final parsed = parseMp3(data);

      expect(parsed.frames, hasLength(1));
      expect(parsed.sampleRate, 44100);
      expect(parsed.id3v2Length, 0);
      final frame = parsed.frames.single;
      expect(frame.offset, 0);
      // 144 * 128000 / 44100 = 417.86... -> floor 417
      expect(frame.length, 417);
      expect(frame.startMillis, 0);
      expect(frame.durationMillis, closeTo(1152 * 1000 / 44100, 1e-9));
    });

    test('the padding bit adds exactly one byte', () {
      final unpadded = buildFrame(bitrateKbps: 128, sampleRate: 44100);
      final padded = buildFrame(
        bitrateKbps: 128,
        sampleRate: 44100,
        padding: true,
      );

      final a = parseMp3(unpadded).frames.single.length;
      final b = parseMp3(padded).frames.single.length;

      expect(b, a + 1);
    });

    test('MPEG2 frames use 576 samples, half the MPEG1 duration', () {
      final mpeg1 = buildFrame(bitrateKbps: 128, sampleRate: 44100);
      final mpeg2 = buildFrame(
        bitrateKbps: 64,
        sampleRate: 22050,
        mpeg1: false,
      );

      final d1 = parseMp3(mpeg1).frames.single.durationMillis;
      final d2 = parseMp3(mpeg2).frames.single.durationMillis;

      // Same nominal duration per frame when sample rate is also halved —
      // what matters here is that 576 samples is being used at all, which
      // this equal-duration result confirms.
      expect(d2, closeTo(d1, 1e-6));
    });

    test('rejects a file with no valid frame at all', () {
      final garbage = Uint8List.fromList(List.filled(200, 0x00));

      expect(() => parseMp3(garbage), throwsA(isA<Mp3ParseException>()));
    });

    test(
        'a lone sync-like byte pair with no confirmable next frame is not '
        'treated as a real frame start', () {
      // 0xFF 0xFB looks like a sync, but what follows is not a valid header
      // and there's nothing after it to confirm — must not be picked up.
      final spurious = Uint8List.fromList([0xFF, 0xFB, 0x00, 0x00, 0x00]);
      final real = buildFrame(bitrateKbps: 128, sampleRate: 44100);
      final data = concatBytes([spurious, real]);

      final parsed = parseMp3(data);

      expect(parsed.frames, hasLength(1));
      expect(parsed.frames.single.offset, spurious.length);
    });
  });

  group('multi-frame streams', () {
    test('CBR frames land at exact, evenly-spaced offsets', () {
      final one = buildFrame(bitrateKbps: 128, sampleRate: 44100);
      final data = concatBytes(List.generate(5, (_) => one));

      final parsed = parseMp3(data);

      expect(parsed.frames, hasLength(5));
      for (var i = 0; i < 5; i++) {
        expect(parsed.frames[i].offset, i * one.length);
      }
      // Every frame covers the same nominal duration, so cumulative start
      // times must be exact multiples of it.
      final perFrame = parsed.frames[0].durationMillis;
      expect(parsed.frames[3].startMillis, closeTo(perFrame * 3, 1e-6));
    });

    test('VBR frames of different sizes still cover the file with no gaps', () {
      final frames = [
        buildFrame(bitrateKbps: 64, sampleRate: 44100),
        buildFrame(bitrateKbps: 320, sampleRate: 44100),
        buildFrame(bitrateKbps: 128, sampleRate: 44100),
      ];
      final data = concatBytes(frames);

      final parsed = parseMp3(data);

      expect(parsed.frames, hasLength(3));
      // No gaps or overlaps: each frame's end is exactly the next one's start.
      for (var i = 0; i < parsed.frames.length - 1; i++) {
        expect(parsed.frames[i].endOffset, parsed.frames[i + 1].offset);
      }
      expect(parsed.frames.last.endOffset, data.length);
    });

    test('total duration is the sum of every frame', () {
      final frames = List.generate(
        10,
        (_) => buildFrame(bitrateKbps: 128, sampleRate: 44100),
      );
      final data = concatBytes(frames);

      final parsed = parseMp3(data);

      final expected = parsed.frames.fold<double>(
        0,
        (sum, f) => sum + f.durationMillis,
      );
      expect(parsed.totalMillis, closeTo(expected, 1e-6));
    });
  });

  group('ID3v2 tag', () {
    test('is skipped, and its length is recorded for re-use on export', () {
      final tag = buildId3v2(contentLength: 30);
      final frame = buildFrame(bitrateKbps: 128, sampleRate: 44100);
      final data = concatBytes([tag, frame]);

      final parsed = parseMp3(data);

      expect(parsed.id3v2Length, tag.length);
      expect(parsed.frames.single.offset, tag.length);
      expect(parsed.id3v2Tag, tag);
    });

    test('a file with no ID3v2 tag starts frames at byte 0', () {
      final frame = buildFrame(bitrateKbps: 128, sampleRate: 44100);

      final parsed = parseMp3(frame);

      expect(parsed.id3v2Length, 0);
      expect(parsed.id3v2Tag, isEmpty);
    });

    test('the ID3v2 footer flag adds 10 bytes many implementations forget',
        () {
      final tagWithFooter = buildId3v2(contentLength: 15, footer: true);
      final frame = buildFrame(bitrateKbps: 128, sampleRate: 44100);
      final data = concatBytes([tagWithFooter, frame]);

      final parsed = parseMp3(data);

      expect(parsed.id3v2Length, tagWithFooter.length);
      expect(parsed.frames.single.offset, tagWithFooter.length);
    });
  });

  group('Xing/Info/VBRI header frame', () {
    test('the first frame is flagged when it carries a Xing marker', () {
      final header = buildFrame(
        bitrateKbps: 128,
        sampleRate: 44100,
        embed: 'Xing',
      );
      final real = buildFrame(bitrateKbps: 128, sampleRate: 44100);
      final data = concatBytes([header, real]);

      final parsed = parseMp3(data);

      expect(parsed.frames[0].isHeaderFrame, isTrue);
      expect(parsed.frames[1].isHeaderFrame, isFalse);
    });

    test('Info and VBRI markers are recognised too', () {
      for (final marker in ['Info', 'VBRI']) {
        final header = buildFrame(
          bitrateKbps: 128,
          sampleRate: 44100,
          embed: marker,
        );
        expect(parseMp3(header).frames.single.isHeaderFrame, isTrue);
      }
    });

    test('a normal first frame with no marker is not flagged', () {
      final frame = buildFrame(bitrateKbps: 128, sampleRate: 44100);

      expect(parseMp3(frame).frames.single.isHeaderFrame, isFalse);
    });

    test(
        'a Xing-like marker appearing later is not flagged — only frame 0 '
        'is ever a header frame', () {
      final real = buildFrame(bitrateKbps: 128, sampleRate: 44100);
      // A coincidental "Xing" string inside a later frame's payload must not
      // matter; only the very first frame of the stream can be a header.
      final withEmbed = buildFrame(
        bitrateKbps: 128,
        sampleRate: 44100,
        embed: 'Xing',
      );
      final data = concatBytes([real, withEmbed]);

      final parsed = parseMp3(data);

      expect(parsed.frames[0].isHeaderFrame, isFalse);
      expect(parsed.frames[1].isHeaderFrame, isFalse);
    });
  });

  group('nearestCuttableFrame', () {
    test('finds the frame closest to the requested time', () {
      final frames = List.generate(
        10,
        (_) => buildFrame(bitrateKbps: 128, sampleRate: 44100),
      );
      final parsed = parseMp3(concatBytes(frames));
      final perFrame = parsed.frames[0].durationMillis;

      // Ask for a time just past frame 4's start — frame 4 should win.
      final nearest = parsed.nearestCuttableFrame(perFrame * 4 + 1);

      expect(nearest, isNotNull);
      expect(nearest!.offset, parsed.frames[4].offset);
    });

    test('never returns the header frame', () {
      final header = buildFrame(
        bitrateKbps: 128,
        sampleRate: 44100,
        embed: 'Xing',
      );
      final real = buildFrame(bitrateKbps: 128, sampleRate: 44100);
      final parsed = parseMp3(concatBytes([header, real]));

      // Ask for time 0 — the header frame starts there, but it must be
      // skipped in favour of the first real frame.
      final nearest = parsed.nearestCuttableFrame(0);

      expect(nearest!.offset, parsed.frames[1].offset);
    });

    test('returns null when every frame is a header frame', () {
      final header = buildFrame(
        bitrateKbps: 128,
        sampleRate: 44100,
        embed: 'Xing',
      );
      final parsed = parseMp3(header);

      expect(parsed.nearestCuttableFrame(0), isNull);
    });
  });
}
