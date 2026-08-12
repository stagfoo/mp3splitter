import 'dart:typed_data';

const bitrateMpeg1L3 = [
  0, 32, 40, 48, 56, 64, 80, 96,
  112, 128, 160, 192, 224, 256, 320, 0,
];
const bitrateMpeg2L3 = [
  0, 8, 16, 24, 32, 40, 48, 56,
  64, 80, 96, 112, 128, 144, 160, 0,
];
const sampleRatesMpeg1 = [44100, 48000, 32000];
const sampleRatesMpeg2 = [22050, 24000, 16000];

/// Builds one valid, synthetic MPEG Layer III frame: a correct 4-byte header
/// followed by payload bytes of 0x00. The payload is content the parser
/// never reads (it only walks by header.frameLength), so a fixed filler is
/// fine and — importantly — never coincidentally matches a frame sync.
Uint8List buildFrame({
  required int bitrateKbps,
  required int sampleRate,
  bool mpeg1 = true,
  bool padding = false,
  String? embed,
}) {
  final bitrateTable = mpeg1 ? bitrateMpeg1L3 : bitrateMpeg2L3;
  final sampleRateTable = mpeg1 ? sampleRatesMpeg1 : sampleRatesMpeg2;
  final bitrateIndex = bitrateTable.indexOf(bitrateKbps);
  final sampleRateIndex = sampleRateTable.indexOf(sampleRate);
  assert(bitrateIndex > 0, 'unknown bitrate $bitrateKbps for this table');
  assert(sampleRateIndex >= 0, 'unknown sample rate $sampleRate');

  final versionBits = mpeg1 ? 3 : 2;
  const layerBits = 1; // Layer III
  const protectionBit = 1; // no CRC, so no extra 2-byte CRC field to model

  final byte1 = 0xE0 | (versionBits << 3) | (layerBits << 1) | protectionBit;
  final byte2 =
      (bitrateIndex << 4) | (sampleRateIndex << 2) | ((padding ? 1 : 0) << 1);
  const byte3 = 0x00;

  final samplesPerFrame = mpeg1 ? 1152 : 576;
  final coefficient = samplesPerFrame ~/ 8;
  final frameLength =
      (coefficient * bitrateKbps * 1000) ~/ sampleRate + (padding ? 1 : 0);

  final frame = Uint8List(frameLength)
    ..[0] = 0xFF
    ..[1] = byte1
    ..[2] = byte2
    ..[3] = byte3;

  if (embed != null) {
    final codes = embed.codeUnits;
    for (var i = 0; i < codes.length; i++) {
      frame[4 + i] = codes[i];
    }
  }

  return frame;
}

Uint8List concatBytes(List<Uint8List> parts) {
  final total = parts.fold<int>(0, (sum, p) => sum + p.length);
  final out = Uint8List(total);
  var offset = 0;
  for (final part in parts) {
    out.setRange(offset, offset + part.length, part);
    offset += part.length;
  }
  return out;
}

Uint8List buildId3v2({int contentLength = 20, bool footer = false}) {
  final tag = Uint8List(10 + contentLength);
  tag[0] = 0x49; // I
  tag[1] = 0x44; // D
  tag[2] = 0x33; // 3
  tag[3] = 0x03; // version
  tag[4] = 0x00;
  tag[5] = footer ? 0x10 : 0x00;
  // Synchsafe size, 7 bits per byte.
  tag[6] = (contentLength >> 21) & 0x7F;
  tag[7] = (contentLength >> 14) & 0x7F;
  tag[8] = (contentLength >> 7) & 0x7F;
  tag[9] = contentLength & 0x7F;
  return footer ? concatBytes([tag, Uint8List(10)]) : tag;
}
