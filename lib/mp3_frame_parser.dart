import 'dart:typed_data';

/// Parses the MPEG frame structure of an MP3 file well enough to find exact
/// frame boundaries — which is all a lossless split needs. This does not
/// decode audio; it only reads frame headers to work out where each frame
/// starts, how long it is, and when it plays.
///
/// Scope: Layer III only (what "MP3" means in practice). MPEG1, MPEG2 and
/// MPEG2.5 are all supported since real encoders use MPEG2/2.5 for low
/// sample rates. Layer I/II and free-format bitrates are rejected rather than
/// silently mishandled — they essentially never appear in a `.mp3` file.

/// A byte range in the source file, in milliseconds along the track.
class Mp3Frame {
  const Mp3Frame({
    required this.offset,
    required this.length,
    required this.startMillis,
    required this.durationMillis,
    required this.isHeaderFrame,
  });

  final int offset;
  final int length;
  final double startMillis;
  final double durationMillis;

  /// A Xing/Info/VBRI frame: metadata about the *whole original file*
  /// (total frames, seek table, encoder delay), not real audio. Copying it
  /// into an exported segment would embed a stream header describing a file
  /// that segment no longer is, so the splitter always excludes it.
  final bool isHeaderFrame;

  int get endOffset => offset + length;
  double get endMillis => startMillis + durationMillis;
}

/// The result of parsing one file: where the audio frames are, and enough
/// bookkeeping to reconstruct valid standalone MP3s from any sub-range.
class ParsedMp3 {
  const ParsedMp3({
    required this.bytes,
    required this.id3v2Length,
    required this.frames,
    required this.sampleRate,
  });

  /// The whole file, unmodified. Frame offsets are indices into this.
  final Uint8List bytes;

  /// Bytes `[0, id3v2Length)` are the original ID3v2 tag, or 0 if there was
  /// none. Kept so it can be prepended to every exported segment — otherwise
  /// every split loses its title/artist/album art.
  final int id3v2Length;

  /// Every audio frame found, in file order, covering the entire audio
  /// stream with no gaps.
  final List<Mp3Frame> frames;

  final int sampleRate;

  double get totalMillis => frames.isEmpty ? 0 : frames.last.endMillis;

  Uint8List get id3v2Tag => Uint8List.sublistView(bytes, 0, id3v2Length);

  /// The frame whose start is closest to [targetMillis], never the header
  /// frame (cutting "at" the Xing frame would mean nothing — it isn't
  /// audio). Used to snap a user-chosen cut time onto a real frame boundary.
  ///
  /// Returns null if there is no real audio frame to cut at (e.g. the file
  /// is nothing but a header frame).
  Mp3Frame? nearestCuttableFrame(double targetMillis) {
    Mp3Frame? best;
    double? bestDelta;
    for (final frame in frames) {
      if (frame.isHeaderFrame) continue;
      final delta = (frame.startMillis - targetMillis).abs();
      if (bestDelta == null || delta < bestDelta) {
        best = frame;
        bestDelta = delta;
      }
    }
    return best;
  }
}

/// Thrown when [parseMp3] cannot find a usable MPEG Layer III audio stream.
class Mp3ParseException implements Exception {
  Mp3ParseException(this.message);
  final String message;

  @override
  String toString() => 'Mp3ParseException: $message';
}

/// The four fields of a frame header this parser actually needs.
class _Header {
  const _Header({
    required this.frameLength,
    required this.samplesPerFrame,
    required this.sampleRate,
  });

  final int frameLength;
  final int samplesPerFrame;
  final int sampleRate;
}

// MPEG1 Layer III, kbps. Index 0 is "free" (unsupported), index 15 is "bad".
const List<int> _bitrateMpeg1L3 = [
  0, 32, 40, 48, 56, 64, 80, 96,
  112, 128, 160, 192, 224, 256, 320, 0,
];

// MPEG2/2.5 Layer III, kbps. Same table as MPEG2/2.5 Layer II.
const List<int> _bitrateMpeg2L3 = [
  0, 8, 16, 24, 32, 40, 48, 56,
  64, 80, 96, 112, 128, 144, 160, 0,
];

const List<int> _sampleRatesMpeg1 = [44100, 48000, 32000];
const List<int> _sampleRatesMpeg2 = [22050, 24000, 16000];
const List<int> _sampleRatesMpeg25 = [11025, 12000, 8000];

/// Reads a 4-byte MPEG frame header starting at [offset]. Returns null when
/// the bytes don't form a valid, supported (Layer III) header — including
/// deliberately-rejected reserved/free/bad field values.
_Header? _readHeader(Uint8List bytes, int offset) {
  if (offset + 4 > bytes.length) return null;

  final b0 = bytes[offset];
  final b1 = bytes[offset + 1];
  final b2 = bytes[offset + 2];

  // 11-bit frame sync: 0xFF followed by the top 3 bits of the next byte set.
  if (b0 != 0xFF || (b1 & 0xE0) != 0xE0) return null;

  final versionBits = (b1 >> 3) & 0x03; // 00=2.5, 01=reserved, 10=2, 11=1
  final layerBits = (b1 >> 1) & 0x03; // 01=Layer III
  if (versionBits == 1 || layerBits != 1) return null;

  final bitrateIndex = (b2 >> 4) & 0x0F;
  final sampleRateIndex = (b2 >> 2) & 0x03;
  final padding = (b2 >> 1) & 0x01;
  if (bitrateIndex == 0 || bitrateIndex == 15 || sampleRateIndex == 3) {
    return null;
  }

  final isMpeg1 = versionBits == 3;
  final sampleRate = isMpeg1
      ? _sampleRatesMpeg1[sampleRateIndex]
      : (versionBits == 2
            ? _sampleRatesMpeg2[sampleRateIndex]
            : _sampleRatesMpeg25[sampleRateIndex]);
  final bitrateKbps = isMpeg1
      ? _bitrateMpeg1L3[bitrateIndex]
      : _bitrateMpeg2L3[bitrateIndex];
  if (bitrateKbps == 0) return null;

  // MPEG1 Layer III carries 1152 samples/frame; MPEG2/2.5 carries 576.
  final samplesPerFrame = isMpeg1 ? 1152 : 576;
  final coefficient = samplesPerFrame ~/ 8; // 144 or 72
  final frameLength =
      (coefficient * bitrateKbps * 1000) ~/ sampleRate + padding;

  if (frameLength < 4) return null;

  return _Header(
    frameLength: frameLength,
    samplesPerFrame: samplesPerFrame,
    sampleRate: sampleRate,
  );
}

/// A sync match is only trusted if the *next* frame it implies also looks
/// like a valid header (or we've hit the end of the data). Raw compressed
/// audio occasionally contains two bytes that happen to match the sync
/// pattern; requiring the next frame to check out as well is the standard
/// way real MP3 parsers avoid a false positive derailing the whole parse.
bool _confirmedByNextFrame(Uint8List bytes, int offset, int dataEnd) {
  final header = _readHeader(bytes, offset)!;
  final next = offset + header.frameLength;
  if (next >= dataEnd - 3) return true; // too close to the end to check
  return _readHeader(bytes, next) != null;
}

int _id3v2Length(Uint8List bytes) {
  if (bytes.length < 10 ||
      bytes[0] != 0x49 /* I */ ||
      bytes[1] != 0x44 /* D */ ||
      bytes[2] != 0x33 /* 3 */ ) {
    return 0;
  }

  // Size is a 4-byte "synchsafe" integer: 7 significant bits per byte.
  final size =
      (bytes[6] & 0x7F) << 21 |
      (bytes[7] & 0x7F) << 14 |
      (bytes[8] & 0x7F) << 7 |
      (bytes[9] & 0x7F);
  final hasFooter = (bytes[5] & 0x10) != 0;
  return 10 + size + (hasFooter ? 10 : 0);
}

/// Loose substring search for the "Xing"/"Info"/"VBRI" marker a header frame
/// carries. Real parsers compute the exact offset from the side-info size,
/// but a whole-frame search is simpler, still essentially never false-
/// positives on real audio data, and the only cost of a miss is that one
/// frame's bytes end up in the export — a cosmetic wrinkle, not a bug.
bool _looksLikeHeaderFrame(Uint8List bytes, int start, int end) {
  const markers = ['Xing', 'Info', 'VBRI'];
  final scanEnd = end.clamp(0, bytes.length);
  for (var i = start; i < scanEnd - 4; i++) {
    for (final marker in markers) {
      final codes = marker.codeUnits;
      if (bytes[i] == codes[0] &&
          bytes[i + 1] == codes[1] &&
          bytes[i + 2] == codes[2] &&
          bytes[i + 3] == codes[3]) {
        return true;
      }
    }
  }
  return false;
}

/// Parses [bytes] into its ID3v2 tag length and its list of audio frames.
///
/// Throws [Mp3ParseException] if no valid MPEG Layer III frame can be found
/// at all — this is not an MP3, or it's too corrupt to split safely.
ParsedMp3 parseMp3(Uint8List bytes) {
  final id3Length = _id3v2Length(bytes);

  var offset = id3Length;
  final dataEnd = bytes.length;

  // Scan forward for the first sync that is confirmed by the frame after it.
  var firstOffset = -1;
  while (offset < dataEnd - 4) {
    if (_readHeader(bytes, offset) != null &&
        _confirmedByNextFrame(bytes, offset, dataEnd)) {
      firstOffset = offset;
      break;
    }
    offset++;
  }

  if (firstOffset < 0) {
    throw Mp3ParseException(
      'No MPEG Layer III audio frames found — not an MP3, or unsupported '
      '(e.g. Layer I/II, free-format bitrate).',
    );
  }

  final frames = <Mp3Frame>[];
  var cursor = firstOffset;
  var cumulativeMillis = 0.0;
  var sampleRate = 0;
  var isFirstFrame = true;

  while (true) {
    final header = _readHeader(bytes, cursor);
    if (header == null) break; // end of the audio stream (ID3v1, padding…)

    sampleRate = header.sampleRate;
    final durationMillis = header.samplesPerFrame * 1000 / header.sampleRate;
    final isHeaderFrame =
        isFirstFrame &&
        _looksLikeHeaderFrame(bytes, cursor, cursor + header.frameLength);

    frames.add(
      Mp3Frame(
        offset: cursor,
        length: header.frameLength,
        startMillis: cumulativeMillis,
        durationMillis: durationMillis,
        isHeaderFrame: isHeaderFrame,
      ),
    );

    cumulativeMillis += durationMillis;
    cursor += header.frameLength;
    isFirstFrame = false;

    if (cursor + 4 > dataEnd) break;
  }

  return ParsedMp3(
    bytes: bytes,
    id3v2Length: id3Length,
    frames: frames,
    sampleRate: sampleRate,
  );
}
