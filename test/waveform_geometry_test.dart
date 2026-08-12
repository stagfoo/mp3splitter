import 'package:flutter_test/flutter_test.dart';
import 'package:mp3splitter/waveform_geometry.dart';

void main() {
  const geometry = WaveformGeometry(
    trackMillis: 60000,
    pixelsPerSecond: 40,
    viewportWidth: 300,
  );

  group('layout', () {
    test('content width is the track plus one full viewport of padding', () {
      // 60s * 40px/s = 2400px of track, plus 300 for the leading+trailing
      // half-viewport padding combined.
      expect(geometry.contentWidth, 2400 + 300);
    });

    test('half viewport is half the viewport width', () {
      expect(geometry.halfViewport, 150);
    });
  });

  group('scroll offset for a time (following playback)', () {
    test('time zero has a scroll offset of zero', () {
      expect(geometry.scrollOffsetFor(0), 0);
    });

    test('scales linearly with time', () {
      expect(geometry.scrollOffsetFor(10000), 400); // 10s * 40px/s
      expect(geometry.scrollOffsetFor(30000), 1200);
    });

    test('is the exact inverse of millisAtScrollOffset', () {
      for (final millis in [0, 1500, 15000, 45000, 60000]) {
        final offset = geometry.scrollOffsetFor(millis);
        expect(geometry.millisAtScrollOffset(offset), millis);
      }
    });
  });

  group('millis at a scroll offset (dragging to seek)', () {
    test('clamps to the start of the track', () {
      expect(geometry.millisAtScrollOffset(-500), 0);
    });

    test('clamps to the end of the track', () {
      expect(geometry.millisAtScrollOffset(999999), 60000);
    });
  });

  group('content x for a time (drawing on the canvas)', () {
    test('millisecond 0 draws at the padding offset, not the canvas edge',
        () {
      // So it can still be scrolled under the centred playhead.
      expect(geometry.xForMillis(0), geometry.halfViewport);
    });

    test('the last millisecond draws at halfViewport + trackWidth', () {
      expect(
        geometry.xForMillis(60000),
        geometry.halfViewport + geometry.trackWidth,
      );
    });

    test('xForMillis and millisForX are exact inverses', () {
      for (final millis in [0, 2500, 20000, 59999, 60000]) {
        final x = geometry.xForMillis(millis);
        expect(geometry.millisForX(x), millis);
      }
    });
  });

  group('cutNear (drag hit-testing)', () {
    test('finds a cut within tolerance', () {
      final id = geometry.cutNear(
        geometry.xForMillis(10000),
        cutsById: {'a': 10000, 'b': 30000},
        toleranceMillis: 500,
      );

      expect(id, 'a');
    });

    test('returns null when nothing is within tolerance', () {
      final id = geometry.cutNear(
        geometry.xForMillis(10000),
        cutsById: {'a': 30000},
        toleranceMillis: 500,
      );

      expect(id, isNull);
    });

    test('picks the closest cut when two are both within tolerance', () {
      final id = geometry.cutNear(
        geometry.xForMillis(10200),
        cutsById: {'near': 10000, 'far': 10400},
        toleranceMillis: 1000,
      );

      expect(id, 'near');
    });

    test('an empty cut set never matches', () {
      final id = geometry.cutNear(
        geometry.xForMillis(10000),
        cutsById: const {},
        toleranceMillis: 1000,
      );

      expect(id, isNull);
    });
  });
}
