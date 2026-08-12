# MP3 Splitter

Split an mp3 by ear and export clean new mp3s. Losslessly — every cut lands on
a real MPEG frame boundary, so exporting is a byte-for-byte copy of the
original file, not a re-encode.

## How it works

Pick a track and the editor opens on an InShot-style layout: the waveform
docks at the bottom as a strip that **scrolls under a fixed, centred
playhead**, rather than a stationary waveform with a moving cursor. Every
action — Cut, Delete, Reset, Export — lives in a bottom toolbar.

- **Scroll to scrub**, then tap **Cut** to drop a marker at the playhead.
- **Drag an existing cut line** to nudge it — the same gesture that scrubs
  the timeline grabs a cut instead when the drag starts on top of one, so
  there's no separate handle UI to reach for.
- **Export** writes each segment as its own standalone `.mp3` and hands you a
  share sheet.

## Why it's lossless

`lib/mp3_frame_parser.dart` is a from-scratch MPEG Layer III frame parser —
no decode, no re-encode, just enough header-walking to know exactly where
every frame starts. `lib/mp3_splitter.dart` snaps each requested cut to the
nearest real frame boundary and byte-copies the ranges between them. The
original ID3v2 tag is copied onto every segment so none of them lose their
title/artist/artwork; a leading Xing/Info/VBRI header frame (if present) is
dropped from every segment, since its stream-level metadata (total frames,
seek table) would be wrong for anything shorter than the whole original file.

Both are pure Dart with no Flutter dependency, and are the most thoroughly
tested part of the app — byte-exact fixtures built by hand, not sampled from
a real file.

## Layout

| File | What it holds |
| --- | --- |
| `lib/mp3_frame_parser.dart` | Frame-accurate parsing: ID3v2, MPEG headers, Xing/VBRI detection |
| `lib/mp3_splitter.dart` | Snaps cuts to frame boundaries, produces lossless segments |
| `lib/cut_timeline.dart` | Pure cut-point logic: add/remove/drag, minimum-gap enforcement |
| `lib/waveform_geometry.dart` | Scroll-offset ⇄ time ⇄ canvas-x conversions for the scrolling strip |
| `lib/editor_screen.dart` | The InShot-style editor: playback, gestures, toolbar |
| `lib/mp3_export.dart` | Writes segments to disk off the UI thread |

## Running it

```sh
flutter pub get
flutter run
flutter test
```

Android only. Pushes and PRs build a debug APK — see `.github/workflows`.
