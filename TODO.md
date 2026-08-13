# TODO

## Bring back a real waveform

Right now the editor shows a flat placeholder bar instead of an amplitude
waveform (see `WaveformPainter._paintBars`) — the `audio_decoder` package
that used to generate it was removed after it crashed on both long and
short tracks. Its `getWaveform` decoded the entire file to PCM and buffered
every sample into a boxed `MutableList<Short>` before reducing it — for a
30-minute stereo file that's 150M+ boxed objects, a reliable native OOM.

A proven reference for doing this properly: `dtrung98/MusicPlayer`
(https://github.com/dtrung98/MusicPlayer) ships a hand-rolled waveform
seekbar (`ui/widget/avsb/AudioVisualSeekBar` + `SoundFile.java`) built on a
lightly modified copy of Google's Ringdroid `SoundFile.java` (Apache 2.0).
It uses the same `MediaExtractor`/`MediaCodec` decode loop, but stores raw
PCM in a growable primitive `ByteBuffer` (2 bytes/sample, doubling capacity
as needed) instead of a boxed list — roughly 8-12x less memory for the same
audio — then reduces that buffer to a small `int[]` of per-frame gains in
one pass and lets the big buffer get GC'd.

Plan: implement a small custom Android platform channel in
`android/app/src/main/kotlin/com/mp3splitter/mp3splitter/` (no new Flutter
dependency) that streams the decode and folds each sample into its output
window's running RMS sum as it arrives, discarding it immediately —
memory bounded by `numberOfSamples` (2400), never by track length. This was
half-built earlier in a file called `WaveformExtractor.kt` before the
crash's real cause turned out to affect short files too and the whole
feature got pulled instead; that draft is a reasonable starting point if
revived, but should be re-verified from scratch.

Not started. Low priority — the flat bar works fine as a scrub/cut surface,
this is a nice-to-have.
