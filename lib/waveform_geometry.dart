/// Maps between track milliseconds and the horizontal position on the
/// scrolling waveform strip.
///
/// The strip scrolls under a playhead fixed at the centre of the viewport —
/// the InShot-style interaction the editor uses — so converting a time to a
/// scroll offset (to follow playback) and a scroll offset back to a time (to
/// seek while the user drags) are both needed, and have to be exact inverses
/// of each other or dragging and playback would drift apart.
///
/// Kept free of Flutter/CustomPainter entirely so the coordinate math can be
/// unit tested without a widget test.
class WaveformGeometry {
  const WaveformGeometry({
    required this.trackMillis,
    required this.pixelsPerSecond,
    required this.viewportWidth,
  });

  /// Builds the geometry a real track should actually be drawn with: routes
  /// [basePixelsPerSecond] through [effectivePixelsPerSecond] first, so a
  /// long track is drawn at a lower zoom instead of an ever-wider canvas.
  ///
  /// This is the single choke point every real call site should go through
  /// — constructing two [WaveformGeometry]s for the same track via the plain
  /// constructor with hand-picked zoom values is how the scroll-follow and
  /// the on-screen paint/gesture geometry could end up disagreeing.
  factory WaveformGeometry.forTrack({
    required int trackMillis,
    required double basePixelsPerSecond,
    required double viewportWidth,
  }) {
    return WaveformGeometry(
      trackMillis: trackMillis,
      pixelsPerSecond: effectivePixelsPerSecond(trackMillis, basePixelsPerSecond),
      viewportWidth: viewportWidth,
    );
  }

  final int trackMillis;
  final double pixelsPerSecond;
  final double viewportWidth;

  /// Half the viewport is padded onto each end of the scrollable content, so
  /// even millisecond 0 or the very last millisecond can still be scrolled to
  /// the centre, under the playhead.
  double get halfViewport => viewportWidth / 2;

  double get trackWidth => trackMillis / 1000 * pixelsPerSecond;

  double get contentWidth => trackWidth + viewportWidth;

  /// The scroll offset that puts [millis] under the fixed centre playhead.
  double scrollOffsetFor(int millis) => millis / 1000 * pixelsPerSecond;

  /// The inverse: the time currently under the playhead for a given scroll
  /// offset, clamped to the track's own range.
  int millisAtScrollOffset(double offset) {
    final millis = (offset / pixelsPerSecond * 1000).round();
    return millis.clamp(0, trackMillis);
  }

  /// Where [millis] draws on the content canvas (not the viewport — the
  /// canvas is the full scrollable width, offset by the leading padding).
  double xForMillis(int millis) => halfViewport + millis / 1000 * pixelsPerSecond;

  /// The inverse of [xForMillis].
  int millisForX(double x) =>
      ((x - halfViewport) / pixelsPerSecond * 1000).round().clamp(0, trackMillis);

  /// The closest existing cut to content-x [x], or null if none are within
  /// [toleranceMillis] — used to decide whether a drag grabs an existing cut
  /// or scrolls the timeline instead.
  String? cutNear(
    double x, {
    required Map<String, int> cutsById,
    required double toleranceMillis,
  }) {
    final targetMillis = millisForX(x);
    String? closestId;
    int? closestDelta;
    cutsById.forEach((id, millis) {
      final delta = (millis - targetMillis).abs();
      if (delta <= toleranceMillis && (closestDelta == null || delta < closestDelta!)) {
        closestId = id;
        closestDelta = delta;
      }
    });
    return closestId;
  }
}

/// The maximum total scrollable waveform canvas width, in logical pixels,
/// that [WaveformGeometry.forTrack] will ever produce.
///
/// Not a precisely-measured hardware limit — GL_MAX_TEXTURE_SIZE varies by
/// device (spec-guaranteed minimum 2048 for OpenGL ES 2.0; most real Android
/// hardware in current use supports 4096-8192 or more) and it's unconfirmed
/// that a texture-size limit is what actually crashed on the device that
/// failed, since no crash log existed at the time this was added. Chosen
/// conservatively below the low end of that practical range as a defensive
/// cap regardless of the exact mechanism — a 30-minute track at a fixed
/// 50px/second would otherwise draw a ~90,000px-wide canvas. The cost is
/// reduced zoom (coarser amplitude bars, less precise scrubbing) only on
/// unusually long tracks; short tracks are unaffected.
const double kMaxWaveformContentWidth = 6000;

/// Scales [basePixelsPerSecond] down, if necessary, so a track [trackMillis]
/// long produces a canvas no wider than [maxWidth]. Never scales up — a
/// track already under the cap is returned unchanged. Pure function, so it's
/// directly unit-testable without a widget.
double effectivePixelsPerSecond(
  int trackMillis,
  double basePixelsPerSecond, {
  double maxWidth = kMaxWaveformContentWidth,
}) {
  if (trackMillis <= 0 || basePixelsPerSecond <= 0) return basePixelsPerSecond;
  final trackSeconds = trackMillis / 1000;
  final naiveWidth = trackSeconds * basePixelsPerSecond;
  if (naiveWidth <= maxWidth) return basePixelsPerSecond;
  return maxWidth / trackSeconds;
}
