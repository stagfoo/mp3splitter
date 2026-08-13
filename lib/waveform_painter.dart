import 'package:flutter/material.dart';

import 'waveform_geometry.dart';

/// Draws the scrolling waveform strip: amplitude bars across the whole
/// track, a vertical line at every cut point (highlighted if selected), and
/// the tolerance-margin-style shaded backing for context. The playhead
/// itself is drawn separately, as a fixed overlay in the viewport — it never
/// moves relative to the screen, only the content underneath it does.
class WaveformPainter extends CustomPainter {
  WaveformPainter({
    required this.geometry,
    required this.amplitudes,
    required this.cutsById,
    required this.selectedCutId,
    required this.barColor,
    required this.cutColor,
    required this.selectedCutColor,
  });

  final WaveformGeometry geometry;

  /// Normalised 0.0–1.0 amplitude values evenly spaced across the track.
  final List<double> amplitudes;

  final Map<String, int> cutsById;
  final String? selectedCutId;
  final Color barColor;
  final Color cutColor;
  final Color selectedCutColor;

  @override
  void paint(Canvas canvas, Size size) {
    _paintBars(canvas, size);
    _paintCuts(canvas, size);
  }

  void _paintBars(Canvas canvas, Size size) {
    if (geometry.trackWidth <= 0) return;

    final paint = Paint()..color = barColor;

    if (amplitudes.isEmpty) {
      // No amplitude data (extraction skipped, failed, or not attempted) —
      // a flat bar still gives the track a visible strip to scrub and drop
      // cuts on, rather than an empty gap.
      final barHeight = size.height * 0.5;
      canvas.drawRect(
        Rect.fromLTWH(
          geometry.halfViewport,
          (size.height - barHeight) / 2,
          geometry.trackWidth,
          barHeight,
        ),
        paint,
      );
      return;
    }

    final barGap = geometry.trackWidth / amplitudes.length;
    // Leave a sliver of gap between bars once they're wide enough for it to
    // read as bars rather than a solid block; below that, drawing them
    // edge-to-edge looks cleaner than a field of hairline gaps.
    final barWidth = barGap > 2 ? barGap * 0.7 : barGap;
    final midY = size.height / 2;

    for (var i = 0; i < amplitudes.length; i++) {
      final x = geometry.halfViewport + i * barGap;
      final barHeight = (amplitudes[i].clamp(0.0, 1.0)) * size.height * 0.9;
      canvas.drawRect(
        Rect.fromLTWH(x, midY - barHeight / 2, barWidth, barHeight),
        paint,
      );
    }
  }

  void _paintCuts(Canvas canvas, Size size) {
    cutsById.forEach((id, millis) {
      final isSelected = id == selectedCutId;
      final x = geometry.xForMillis(millis);
      final paint = Paint()
        ..color = isSelected ? selectedCutColor : cutColor
        ..strokeWidth = isSelected ? 3 : 2;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    });
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) =>
      oldDelegate.geometry.trackMillis != geometry.trackMillis ||
      oldDelegate.geometry.pixelsPerSecond != geometry.pixelsPerSecond ||
      oldDelegate.amplitudes != amplitudes ||
      oldDelegate.cutsById != cutsById ||
      oldDelegate.selectedCutId != selectedCutId;
}
