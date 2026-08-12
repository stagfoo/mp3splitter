import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mp3splitter/mp3_frame_parser.dart';
import 'package:mp3splitter/mp3_splitter.dart';

import 'mp3_test_support.dart';

bool _containsBytes(Uint8List haystack, List<int> needle) {
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

void main() {
  group('splitMp3', () {
    test('no cut points returns the whole track as one segment', () {
      final frames = List.generate(
        5,
        (_) => buildFrame(bitrateKbps: 128, sampleRate: 44100),
      );
      final data = concatBytes(frames);
      final parsed = parseMp3(data);

      final segments = splitMp3(parsed, const []);

      expect(segments, hasLength(1));
      expect(segments.single.bytes, data);
      expect(segments.single.startMillis, 0);
      expect(segments.single.endMillis, closeTo(parsed.totalMillis, 1e-6));
    });

    test('one cut point produces two segments covering the whole file', () {
      final frames = List.generate(
        10,
        (_) => buildFrame(bitrateKbps: 128, sampleRate: 44100),
      );
      final data = concatBytes(frames);
      final parsed = parseMp3(data);
      final cutAt = parsed.frames[5].startMillis;

      final segments = splitMp3(parsed, [cutAt]);

      expect(segments, hasLength(2));
      expect(segments[0].startMillis, 0);
      expect(segments[0].endMillis, segments[1].startMillis);
      expect(segments[1].endMillis, closeTo(parsed.totalMillis, 1e-6));
    });

    test('every original audio byte appears in exactly one segment', () {
      final frames = List.generate(
        20,
        (_) => buildFrame(bitrateKbps: 128, sampleRate: 44100),
      );
      final data = concatBytes(frames);
      final parsed = parseMp3(data);
      final cuts = [
        parsed.frames[6].startMillis,
        parsed.frames[13].startMillis,
      ];

      final segments = splitMp3(parsed, cuts);

      // No ID3v2 tag in this fixture, so segment bytes are pure audio —
      // concatenating them back must reconstruct the original exactly.
      final rebuilt = concatBytes(
        segments.map((s) => s.bytes).toList(),
      );
      expect(rebuilt, data);
    });

    test('cuts are sorted regardless of the order given', () {
      final frames = List.generate(
        10,
        (_) => buildFrame(bitrateKbps: 128, sampleRate: 44100),
      );
      final parsed = parseMp3(concatBytes(frames));
      final a = parsed.frames[3].startMillis;
      final b = parsed.frames[7].startMillis;

      final forward = splitMp3(parsed, [a, b]);
      final backward = splitMp3(parsed, [b, a]);

      expect(forward, hasLength(3));
      expect(
        forward.map((s) => s.startMillis),
        backward.map((s) => s.startMillis),
      );
    });

    test('duplicate or near-duplicate cuts collapse to one boundary', () {
      final frames = List.generate(
        10,
        (_) => buildFrame(bitrateKbps: 128, sampleRate: 44100),
      );
      final parsed = parseMp3(concatBytes(frames));
      final cutAt = parsed.frames[5].startMillis;

      final segments = splitMp3(parsed, [cutAt, cutAt, cutAt + 0.001]);

      expect(segments, hasLength(2));
    });

    test('a cut at or past the very end produces no trailing empty segment',
        () {
      final frames = List.generate(
        5,
        (_) => buildFrame(bitrateKbps: 128, sampleRate: 44100),
      );
      final parsed = parseMp3(concatBytes(frames));

      final segments = splitMp3(parsed, [parsed.totalMillis + 1000]);

      expect(segments, hasLength(1));
    });

    test('a cut before the start produces no leading empty segment', () {
      final frames = List.generate(
        5,
        (_) => buildFrame(bitrateKbps: 128, sampleRate: 44100),
      );
      final parsed = parseMp3(concatBytes(frames));

      final segments = splitMp3(parsed, [-500]);

      expect(segments, hasLength(1));
    });

    test('segments are labelled and indexed in order', () {
      final frames = List.generate(
        10,
        (_) => buildFrame(bitrateKbps: 128, sampleRate: 44100),
      );
      final parsed = parseMp3(concatBytes(frames));
      final cuts = [
        parsed.frames[3].startMillis,
        parsed.frames[7].startMillis,
      ];

      final segments = splitMp3(parsed, cuts);

      expect(segments.map((s) => s.index), [0, 1, 2]);
      expect(segments.map((s) => s.label), ['Part 1', 'Part 2', 'Part 3']);
    });

    group('the ID3v2 tag', () {
      test('is prepended to every segment, not just the first', () {
        final tag = buildId3v2(contentLength: 24);
        final frames = List.generate(
          10,
          (_) => buildFrame(bitrateKbps: 128, sampleRate: 44100),
        );
        final data = concatBytes([tag, ...frames]);
        final parsed = parseMp3(data);
        final cuts = [
          parsed.frames[3].startMillis,
          parsed.frames[7].startMillis,
        ];

        final segments = splitMp3(parsed, cuts);

        expect(segments, hasLength(3));
        for (final segment in segments) {
          expect(
            Uint8List.sublistView(segment.bytes, 0, tag.length),
            tag,
            reason: '${segment.label} should start with the original tag',
          );
        }
      });

      test('every segment starts with a valid frame sync right after the tag',
          () {
        final tag = buildId3v2(contentLength: 24);
        final frames = List.generate(
          10,
          (_) => buildFrame(bitrateKbps: 128, sampleRate: 44100),
        );
        final data = concatBytes([tag, ...frames]);
        final parsed = parseMp3(data);
        final cuts = [parsed.frames[5].startMillis];

        final segments = splitMp3(parsed, cuts);

        for (final segment in segments) {
          // Re-parsing each exported segment must succeed on its own — this
          // is what "a valid, standalone, playable mp3" actually means.
          final reparsed = parseMp3(segment.bytes);
          expect(reparsed.frames, isNotEmpty);
          expect(reparsed.id3v2Length, tag.length);
        }
      });
    });

    group('a Xing/Info header frame', () {
      test('is excluded from every exported segment', () {
        final header = buildFrame(
          bitrateKbps: 128,
          sampleRate: 44100,
          embed: 'Xing',
        );
        final real = List.generate(
          9,
          (_) => buildFrame(bitrateKbps: 128, sampleRate: 44100),
        );
        final data = concatBytes([header, ...real]);
        final parsed = parseMp3(data);
        final cuts = [parsed.frames[4].startMillis];

        final segments = splitMp3(parsed, cuts);

        for (final segment in segments) {
          expect(_containsBytes(segment.bytes, 'Xing'.codeUnits), isFalse);
        }
        // The stronger check: total exported bytes is the real-audio bytes
        // only, i.e. original size minus the header frame's own length.
        final totalExported = segments.fold<int>(
          0,
          (sum, s) => sum + s.bytes.length,
        );
        expect(totalExported, data.length - header.length);
      });

      test('the first real segment still starts on a valid frame sync', () {
        final header = buildFrame(
          bitrateKbps: 128,
          sampleRate: 44100,
          embed: 'Xing',
        );
        final real = List.generate(
          5,
          (_) => buildFrame(bitrateKbps: 128, sampleRate: 44100),
        );
        final parsed = parseMp3(concatBytes([header, ...real]));

        final segments = splitMp3(parsed, const []);

        expect(segments, hasLength(1));
        // The 5 real frames survive; the leading Xing frame does not.
        final reparsed = parseMp3(segments.single.bytes);
        expect(reparsed.frames, hasLength(5));
        expect(reparsed.frames.every((f) => !f.isHeaderFrame), isTrue);
      });
    });

    test('an all-header-frame file splits to nothing rather than throwing',
        () {
      final header = buildFrame(
        bitrateKbps: 128,
        sampleRate: 44100,
        embed: 'Xing',
      );
      final parsed = parseMp3(header);

      expect(splitMp3(parsed, const []), isEmpty);
    });
  });
}
