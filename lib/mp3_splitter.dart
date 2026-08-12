import 'dart:typed_data';

import 'mp3_frame_parser.dart';

/// One exported clip: the finished bytes of a standalone, playable MP3, plus
/// the timing it covers for naming/display.
class Mp3SplitResult {
  const Mp3SplitResult({
    required this.index,
    required this.startMillis,
    required this.endMillis,
    required this.bytes,
  });

  final int index;
  final double startMillis;
  final double endMillis;
  final Uint8List bytes;

  double get durationMillis => endMillis - startMillis;

  /// 1-based, human-facing.
  String get label => 'Part ${index + 1}';
}

/// Splits [parsed] at the given [cutMillis], losslessly.
///
/// Every cut is snapped to the nearest real audio frame boundary — MP3
/// frames are independently decodable, so cutting exactly between two of
/// them costs nothing: no re-encoding, no generation loss, no silence or
/// glitch at the seam. That snap is also why the *requested* millisecond and
/// the segment's *actual* boundary can differ by a frame or two (at 44.1kHz,
/// a Layer III frame is ~26ms) — far below what's audible or noticeable when
/// picking a cut point by ear off a waveform.
///
/// The original ID3v2 tag (title, artist, artwork) is copied onto every
/// segment, so none of them lose their metadata. A Xing/Info/VBRI header
/// frame, if the source has one, is dropped from every segment rather than
/// copied into whichever one contains frame 0: it advertises stream-level
/// facts (total frame count, seek table) about the *original* file, which
/// would be wrong for any segment shorter than the whole thing. Losing it
/// costs nothing but the fast-seek optimisation — every player still plays
/// the file fine by reading frames directly.
///
/// An empty [cutMillis] returns the whole (header-frame-stripped) track as a
/// single segment.
List<Mp3SplitResult> splitMp3(ParsedMp3 parsed, List<double> cutMillis) {
  final realFrames = parsed.frames.where((f) => !f.isHeaderFrame).toList();
  if (realFrames.isEmpty) return const [];

  final startOffset = realFrames.first.offset;
  final endOffset = realFrames.last.endOffset;
  final startMillis = realFrames.first.startMillis;
  final endMillis = realFrames.last.endMillis;

  // Snap every requested cut to a real frame boundary, then dedupe and drop
  // anything at or beyond either end — those wouldn't produce a usable
  // segment on one side.
  final boundaryOffsets = <int>{};
  for (final millis in cutMillis) {
    // Reject out-of-range requests before snapping, not after: "nearest
    // frame" always finds *something* — for a time far past the end, that's
    // the last frame's own start, which the post-snap offset check below
    // would not catch (a frame's start is always < endOffset by
    // construction, even when the frame itself is the very last one).
    if (millis <= startMillis || millis >= endMillis) continue;

    final frame = parsed.nearestCuttableFrame(millis);
    if (frame == null) continue;
    if (frame.offset <= startOffset || frame.offset >= endOffset) continue;
    boundaryOffsets.add(frame.offset);
  }

  final sortedBoundaries = boundaryOffsets.toList()..sort();
  final offsets = [startOffset, ...sortedBoundaries, endOffset];

  // Byte offset -> the frame starting there, so each segment's reported
  // timing comes from real frame data rather than being recomputed.
  final frameByOffset = {for (final f in realFrames) f.offset: f};

  final results = <Mp3SplitResult>[];
  for (var i = 0; i < offsets.length - 1; i++) {
    final from = offsets[i];
    final to = offsets[i + 1];

    final bytes = Uint8List(parsed.id3v2Length + (to - from))
      ..setRange(0, parsed.id3v2Length, parsed.id3v2Tag)
      ..setRange(parsed.id3v2Length, parsed.id3v2Length + (to - from),
          parsed.bytes, from);

    results.add(
      Mp3SplitResult(
        index: i,
        startMillis: i == 0 ? startMillis : frameByOffset[from]!.startMillis,
        endMillis: to == endOffset ? endMillis : frameByOffset[to]!.startMillis,
        bytes: bytes,
      ),
    );
  }

  return results;
}
