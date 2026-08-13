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

  group('effectivePixelsPerSecond (long-track cap)', () {
    test('a short track is returned unchanged', () {
      expect(effectivePixelsPerSecond(60000, 50), 50);
    });

    test('exactly at the cap is returned unchanged', () {
      final trackMillis = (kMaxWaveformContentWidth / 50 * 1000).round();

      expect(effectivePixelsPerSecond(trackMillis, 50), 50);
    });

    test('a 30-minute track is scaled down to fit the cap', () {
      const trackMillis = 30 * 60 * 1000;

      final result = effectivePixelsPerSecond(trackMillis, 50);

      expect(result, lessThan(50));
      expect(
        result * (trackMillis / 1000),
        closeTo(kMaxWaveformContentWidth, 0.001),
      );
    });

    test('never scales up', () {
      // Already well under the cap at this zoom — must come back unchanged.
      expect(effectivePixelsPerSecond(30 * 60 * 1000, 2), 2);
    });

    test('a zero-length track does not divide by zero', () {
      expect(effectivePixelsPerSecond(0, 50), 50);
    });

    test('respects a custom maxWidth', () {
      final result = effectivePixelsPerSecond(600000, 50, maxWidth: 1000);

      expect(result * 600, closeTo(1000, 0.001));
    });
  });

  group('WaveformGeometry.forTrack', () {
    test('a short track uses the base zoom directly', () {
      final geometry = WaveformGeometry.forTrack(
        trackMillis: 60000,
        basePixelsPerSecond: 50,
        viewportWidth: 300,
      );

      expect(geometry.pixelsPerSecond, 50);
    });

    test('a long track is capped, and trackWidth stays within the cap', () {
      // The screenshot-triggering case: a 30-minute file at the naive 50
      // px/s zoom would be ~90,000px wide.
      final geometry = WaveformGeometry.forTrack(
        trackMillis: 30 * 60 * 1000,
        basePixelsPerSecond: 50,
        viewportWidth: 300,
      );

      expect(geometry.trackWidth, closeTo(kMaxWaveformContentWidth, 0.001));
    });

    test('an even longer track is still capped, not unboundedly wide', () {
      final geometry = WaveformGeometry.forTrack(
        trackMillis: 3 * 60 * 60 * 1000, // 3 hours
        basePixelsPerSecond: 50,
        viewportWidth: 300,
      );

      expect(geometry.trackWidth, lessThanOrEqualTo(kMaxWaveformContentWidth));
    });

    test('two calls with identical inputs cannot drift apart', () {
      // This is the actual bug class being guarded against: editor_screen
      // builds a WaveformGeometry in two separate places (scroll-follow
      // during playback, and the paint/gesture widget) — both must apply
      // the same cap or scrubbing and playback-follow disagree about where
      // "now" is.
      WaveformGeometry build() => WaveformGeometry.forTrack(
        trackMillis: 30 * 60 * 1000,
        basePixelsPerSecond: 50,
        viewportWidth: 300,
      );

      expect(build().pixelsPerSecond, build().pixelsPerSecond);
    });
  });
}
