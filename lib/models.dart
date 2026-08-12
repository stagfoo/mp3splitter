/// A point in the track, in milliseconds, where the user wants to cut.
///
/// Stored separately from the derived [Segment] list because the user edits
/// cut points one at a time (add, delete, drag) while the segments are just
/// "whatever lies between consecutive cut points" — recomputing them from
/// scratch after every edit is simpler than patching a segment list by hand.
class CutPoint {
  const CutPoint({required this.id, required this.millis});

  final String id;
  final int millis;

  CutPoint copyWith({int? millis}) =>
      CutPoint(id: id, millis: millis ?? this.millis);
}

/// One exportable piece of the track, bounded by two cut points (or the
/// start/end of the track).
class Segment {
  const Segment({
    required this.index,
    required this.startMillis,
    required this.endMillis,
  });

  final int index;
  final int startMillis;
  final int endMillis;

  int get durationMillis => endMillis - startMillis;

  /// 1-based, human-facing: "Part 1", "Part 2", ...
  String get label => 'Part ${index + 1}';
}

/// Turns a sorted-or-not list of cut points into the segments they imply.
/// Cut points at or beyond the track bounds are ignored — dragging a handle
/// past either end should shrink a segment to nothing, not create a
/// zero-or-negative-length one.
List<Segment> segmentsFromCuts(
  List<CutPoint> cuts, {
  required int trackMillis,
}) {
  final sorted = cuts.map((c) => c.millis).toSet().toList()..sort();
  final bounds = [
    0,
    ...sorted.where((m) => m > 0 && m < trackMillis),
    trackMillis,
  ];

  final segments = <Segment>[];
  for (var i = 0; i < bounds.length - 1; i++) {
    segments.add(
      Segment(index: i, startMillis: bounds[i], endMillis: bounds[i + 1]),
    );
  }
  return segments;
}
