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
