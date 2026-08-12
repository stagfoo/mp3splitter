import 'package:flutter_test/flutter_test.dart';
import 'package:mp3splitter/cut_timeline.dart';

void main() {
  group('adding cuts', () {
    test('adds a cut within bounds', () {
      final timeline = CutTimeline(trackMillis: 10000);

      final cut = timeline.addCut(5000);

      expect(cut, isNotNull);
      expect(cut!.millis, 5000);
      expect(timeline.cuts, hasLength(1));
    });

    test('refuses a cut too close to the start', () {
      final timeline = CutTimeline(trackMillis: 10000);

      expect(timeline.addCut(100), isNull);
      expect(timeline.cuts, isEmpty);
    });

    test('refuses a cut too close to the end', () {
      final timeline = CutTimeline(trackMillis: 10000);

      expect(timeline.addCut(9950), isNull);
      expect(timeline.cuts, isEmpty);
    });

    test('accepts a cut exactly at the minimum gap', () {
      final timeline = CutTimeline(trackMillis: 10000);

      expect(timeline.addCut(CutTimeline.minGapMillis), isNotNull);
      expect(
        timeline.addCut(10000 - CutTimeline.minGapMillis),
        isNotNull,
      );
    });

    test('refuses a cut too close to an existing one', () {
      final timeline = CutTimeline(trackMillis: 10000);
      timeline.addCut(5000);

      expect(timeline.addCut(5100), isNull);
      expect(timeline.addCut(4950), isNull);
      expect(timeline.cuts, hasLength(1));
    });

    test('accepts a second cut exactly at the minimum gap from the first',
        () {
      final timeline = CutTimeline(trackMillis: 10000);
      timeline.addCut(5000);

      final cut = timeline.addCut(5000 + CutTimeline.minGapMillis);

      expect(cut, isNotNull);
      expect(timeline.cuts, hasLength(2));
    });

    test('cuts come back sorted regardless of add order', () {
      final timeline = CutTimeline(trackMillis: 10000);
      timeline.addCut(7000);
      timeline.addCut(2000);
      timeline.addCut(5000);

      expect(timeline.cuts.map((c) => c.millis), [2000, 5000, 7000]);
    });

    test('each cut gets a distinct id', () {
      final timeline = CutTimeline(trackMillis: 10000);
      final a = timeline.addCut(2000)!;
      final b = timeline.addCut(5000)!;

      expect(a.id, isNot(b.id));
    });
  });

  group('removing and clearing', () {
    test('removes a cut by id', () {
      final timeline = CutTimeline(trackMillis: 10000);
      final cut = timeline.addCut(5000)!;

      timeline.removeCut(cut.id);

      expect(timeline.cuts, isEmpty);
    });

    test('removing an unknown id is a no-op', () {
      final timeline = CutTimeline(trackMillis: 10000);
      timeline.addCut(5000);

      timeline.removeCut('does-not-exist');

      expect(timeline.cuts, hasLength(1));
    });

    test('clear removes every cut', () {
      final timeline = CutTimeline(trackMillis: 10000);
      timeline.addCut(2000);
      timeline.addCut(5000);

      timeline.clear();

      expect(timeline.cuts, isEmpty);
    });

    test('contains reports whether an id is currently a cut', () {
      final timeline = CutTimeline(trackMillis: 10000);
      final cut = timeline.addCut(5000)!;

      expect(timeline.contains(cut.id), isTrue);
      timeline.removeCut(cut.id);
      expect(timeline.contains(cut.id), isFalse);
    });
  });

  group('moving a cut', () {
    test('moves freely when there are no neighbours nearby', () {
      final timeline = CutTimeline(trackMillis: 10000);
      final cut = timeline.addCut(5000)!;

      timeline.moveCut(cut.id, 6000);

      expect(timeline.cuts.single.millis, 6000);
    });

    test('clamps at the track start', () {
      final timeline = CutTimeline(trackMillis: 10000);
      final cut = timeline.addCut(5000)!;

      timeline.moveCut(cut.id, -1000);

      expect(timeline.cuts.single.millis, CutTimeline.minGapMillis);
    });

    test('clamps at the track end', () {
      final timeline = CutTimeline(trackMillis: 10000);
      final cut = timeline.addCut(5000)!;

      timeline.moveCut(cut.id, 50000);

      expect(
        timeline.cuts.single.millis,
        10000 - CutTimeline.minGapMillis,
      );
    });

    test('cannot be dragged past a neighbour to its right', () {
      final timeline = CutTimeline(trackMillis: 10000);
      final left = timeline.addCut(3000)!;
      timeline.addCut(6000);

      timeline.moveCut(left.id, 9000);

      final moved = timeline.cuts.firstWhere((c) => c.id == left.id);
      expect(moved.millis, 6000 - CutTimeline.minGapMillis);
    });

    test('cannot be dragged past a neighbour to its left', () {
      final timeline = CutTimeline(trackMillis: 10000);
      timeline.addCut(3000);
      final right = timeline.addCut(6000)!;

      timeline.moveCut(right.id, 0);

      final moved = timeline.cuts.firstWhere((c) => c.id == right.id);
      expect(moved.millis, 3000 + CutTimeline.minGapMillis);
    });

    test('is boxed in correctly between two neighbours on both sides', () {
      final timeline = CutTimeline(trackMillis: 10000);
      timeline.addCut(2000);
      final middle = timeline.addCut(5000)!;
      timeline.addCut(8000);

      timeline.moveCut(middle.id, 100);
      expect(
        timeline.cuts.firstWhere((c) => c.id == middle.id).millis,
        2000 + CutTimeline.minGapMillis,
      );

      timeline.moveCut(middle.id, 9999);
      expect(
        timeline.cuts.firstWhere((c) => c.id == middle.id).millis,
        8000 - CutTimeline.minGapMillis,
      );
    });

    test('a multi-step drag stays correct as it crosses the starting point',
        () {
      // Regression case for using stale neighbour classification: drag a cut
      // step by step from well left of a neighbour to well right of it. Since
      // the clamp never lets a single step jump past the neighbour, this
      // must still end up pinned just short of it, not tunnel through.
      final timeline = CutTimeline(trackMillis: 10000);
      final moving = timeline.addCut(1000)!;
      timeline.addCut(5000);

      for (final target in [1500, 2500, 3500, 4500, 5500, 6500]) {
        timeline.moveCut(moving.id, target);
      }

      expect(
        timeline.cuts.firstWhere((c) => c.id == moving.id).millis,
        5000 - CutTimeline.minGapMillis,
      );
    });

    test('moving an unknown id is a no-op', () {
      final timeline = CutTimeline(trackMillis: 10000);
      timeline.addCut(5000);

      timeline.moveCut('does-not-exist', 9000);

      expect(timeline.cuts.single.millis, 5000);
    });
  });

  group('segments', () {
    test('one segment covering the whole track when there are no cuts', () {
      final timeline = CutTimeline(trackMillis: 10000);

      expect(timeline.segments, hasLength(1));
      expect(timeline.segments.single.startMillis, 0);
      expect(timeline.segments.single.endMillis, 10000);
    });

    test('segments update live as cuts are added and removed', () {
      final timeline = CutTimeline(trackMillis: 10000);
      final cut = timeline.addCut(4000)!;

      expect(timeline.segments, hasLength(2));

      timeline.removeCut(cut.id);

      expect(timeline.segments, hasLength(1));
    });

    test('segments track a moved cut', () {
      final timeline = CutTimeline(trackMillis: 10000);
      final cut = timeline.addCut(4000)!;

      timeline.moveCut(cut.id, 7000);

      expect(timeline.segments[0].endMillis, 7000);
      expect(timeline.segments[1].startMillis, 7000);
    });
  });
}
