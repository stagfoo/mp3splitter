import 'models.dart';

/// Owns the cut points for one editing session and derives the segments they
/// imply. Pure Dart, no Flutter or platform dependency — this is the part of
/// the editor worth getting right independent of any device, so it's kept
/// separate from the audio playback and waveform rendering that do need one.
class CutTimeline {
  CutTimeline({required this.trackMillis});

  /// Total track length. Cuts only ever land strictly between 0 and this.
  final int trackMillis;

  final List<CutPoint> _cuts = [];
  int _nextId = 0;

  /// The minimum gap kept between two cuts (and between a cut and either end
  /// of the track), so a segment can never be squeezed down to nothing by
  /// two cuts landing on top of each other.
  static const int minGapMillis = 300;

  List<CutPoint> get cuts {
    final sorted = [..._cuts]..sort((a, b) => a.millis.compareTo(b.millis));
    return List.unmodifiable(sorted);
  }

  List<Segment> get segments =>
      segmentsFromCuts(_cuts, trackMillis: trackMillis);

  /// Adds a cut at [millis]. Returns the new cut, or null if [millis] is too
  /// close to either end of the track or to a cut that already exists —
  /// silently refusing is better than adding a cut the user can't see the
  /// point of, or one that produces a segment too short to export.
  CutPoint? addCut(int millis) {
    if (millis < minGapMillis || millis > trackMillis - minGapMillis) {
      return null;
    }
    for (final existing in _cuts) {
      if ((existing.millis - millis).abs() < minGapMillis) return null;
    }

    final cut = CutPoint(id: 'cut-${_nextId++}', millis: millis);
    _cuts.add(cut);
    return cut;
  }

  void removeCut(String id) => _cuts.removeWhere((c) => c.id == id);

  void clear() => _cuts.clear();

  bool contains(String id) => _cuts.any((c) => c.id == id);

  /// Moves an existing cut — the drag-to-adjust handle. Clamped so it can
  /// never cross a neighbouring cut or either end of the track, using each
  /// neighbour's position *before this move* to decide which side it's on.
  /// That's what keeps a multi-step drag stable: a single call can never
  /// jump past a neighbour (the clamp forbids it), so the left/right
  /// classification computed from the cut's last position remains correct
  /// for the next call, and the one after that.
  void moveCut(String id, int millis) {
    final index = _cuts.indexWhere((c) => c.id == id);
    if (index < 0) return;
    final current = _cuts[index];

    var lowerBound = minGapMillis;
    var upperBound = trackMillis - minGapMillis;
    for (final other in _cuts) {
      if (other.id == id) continue;
      if (other.millis <= current.millis) {
        final bound = other.millis + minGapMillis;
        if (bound > lowerBound) lowerBound = bound;
      } else {
        final bound = other.millis - minGapMillis;
        if (bound < upperBound) upperBound = bound;
      }
    }
    // Neighbours already closer together than two gaps would make this
    // unsatisfiable — leave the cut where it is rather than throw.
    if (lowerBound > upperBound) return;

    _cuts[index] = current.copyWith(millis: millis.clamp(lowerBound, upperBound));
  }
}
