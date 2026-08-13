import 'dart:async';
import 'dart:io';

import 'package:audio_decoder/audio_decoder.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'cut_timeline.dart';
import 'export_screen.dart';
import 'mp3_frame_parser.dart';
import 'waveform_geometry.dart';
import 'waveform_painter.dart';

/// The main screen: load a track, scrub it, drop cuts, export the pieces.
///
/// Layout follows an InShot-style video editor rather than a conventional
/// audio app — a waveform strip docked at the bottom that *scrolls under a
/// fixed, centred playhead* (rather than a stationary waveform with a
/// moving cursor), with every action living in a bottom toolbar. Dragging
/// directly on an existing cut line moves it; dragging anywhere else scrolls
/// the timeline, which is how scrubbing and adjusting a cut end up sharing
/// one gesture without needing separate handle widgets.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.filePath});

  final String filePath;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final _player = AudioPlayer();
  final _scrollController = ScrollController();

  static const double _pixelsPerSecond = 50;

  /// How close (in track milliseconds) a drag's start has to land to an
  /// existing cut to grab it instead of scrolling. At the default zoom this
  /// is comfortably wider than a fingertip, so accidental scroll-instead-of-
  /// drag misses are rare without making every scroll near a cut feel sticky.
  static const double _cutHitToleranceMillis = 350;

  /// A generous upper bound on how long native waveform extraction should
  /// take, even for a long track — if it hasn't returned by then, something
  /// is stuck rather than just slow, and the editor should fall back to no
  /// waveform rather than hang the loading screen indefinitely.
  static const _waveformExtractionTimeout = Duration(seconds: 20);

  /// Above this track length, native waveform extraction is skipped
  /// entirely rather than attempted and caught. `audio_decoder`'s Android
  /// implementation appears to decode the *whole* file to raw PCM before
  /// computing amplitude peaks — for a long track that's plausibly hundreds
  /// of megabytes, risking an out-of-memory kill deep in native code. That
  /// kind of failure happens before any Dart handler — try/catch, timeout,
  /// even `runZonedGuarded` in main.dart — gets a chance to run, so it can't
  /// be caught, only avoided. 10 minutes is a conservative guess, not a
  /// measured limit (no crash log exists yet to measure the real one from);
  /// the editor still works fully from playback and the cut list alone
  /// without a waveform.
  static const _maxWaveformDecodeMillis = 10 * 60 * 1000;

  /// A sanity ceiling on the source file itself, checked before anything
  /// else is attempted. Well beyond any real mp3 (even several hours at a
  /// high bitrate stays under this) — this exists to turn "picked the wrong
  /// file" or a corrupt/oversized file into a clear error message instead
  /// of an open-ended read + parse of an arbitrarily large file.
  static const _maxFileSizeBytes = 500 * 1024 * 1024;

  ParsedMp3? _parsed;
  CutTimeline? _timeline;
  List<double> _amplitudes = const [];
  String? _selectedCutId;
  bool _isLoading = true;
  String? _error;

  bool _userIsScrolling = false;
  String? _draggingCutId;
  double _viewportWidth = 0;
  StreamSubscription<Duration>? _positionSub;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _player.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final file = File(widget.filePath);
      final sizeBytes = await file.length();
      if (sizeBytes > _maxFileSizeBytes) {
        final sizeMb = (sizeBytes / (1024 * 1024)).round();
        throw Mp3ParseException(
          "This file is $sizeMb MB, too large to open. Try a smaller file.",
        );
      }

      final bytes = await file.readAsBytes();
      // Frame-walking a large file is real work; keep it off the UI thread.
      final parsed = await compute(parseMp3, bytes);

      await _player.setFilePath(widget.filePath);

      final tooLongForWaveform =
          parsed.totalMillis > _maxWaveformDecodeMillis;
      var amplitudes = const <double>[];
      if (!tooLongForWaveform) {
        try {
          amplitudes = await AudioDecoder.getWaveform(
            widget.filePath,
            numberOfSamples: 2400,
          ).timeout(
            _waveformExtractionTimeout,
            onTimeout: () => const <double>[],
          );
        } catch (_) {
          // The waveform is a visual aid, not a requirement — the editor
          // still works from playback and the cut list alone without it. (A
          // timeout only unblocks the Dart side — it can't cancel whatever
          // the native decoder is doing, and neither this nor the catch
          // above can help if the native side crashes outright rather than
          // throwing.)
        }
      }

      if (!mounted) return;
      setState(() {
        _parsed = parsed;
        _timeline = CutTimeline(trackMillis: parsed.totalMillis.round());
        _amplitudes = amplitudes;
        _isLoading = false;
      });

      if (tooLongForWaveform) {
        // Deferred a frame: the Scaffold this needs is the one about to be
        // built from the setState above, not necessarily present yet.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showMessage(
            "Track is long, so there's no waveform preview — playback and "
            'cutting still work normally.',
          );
        });
      }

      _positionSub = _player.positionStream.listen(_onPlaybackPosition);
    } on Mp3ParseException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Couldn't open this file: $e";
        _isLoading = false;
      });
    }
  }

  WaveformGeometry? get _geometry {
    final timeline = _timeline;
    if (timeline == null || _viewportWidth <= 0) return null;
    return WaveformGeometry.forTrack(
      trackMillis: timeline.trackMillis,
      basePixelsPerSecond: _pixelsPerSecond,
      viewportWidth: _viewportWidth,
    );
  }

  /// Keeps the timeline scrolled so "now" stays under the playhead — unless
  /// the user is the one currently scrolling, in which case following would
  /// just fight their finger.
  void _onPlaybackPosition(Duration position) {
    if (_userIsScrolling || _draggingCutId != null) return;
    final geometry = _geometry;
    if (geometry == null || !_scrollController.hasClients) return;

    final target = geometry.scrollOffsetFor(position.inMilliseconds);
    final clamped = target.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.jumpTo(clamped);
  }

  void _handleScrollNotification(ScrollNotification notification) {
    if (_draggingCutId != null) return; // a cut drag owns this gesture

    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _userIsScrolling = true;
    } else if (notification is ScrollEndNotification) {
      _userIsScrolling = false;
    } else if (notification is ScrollUpdateNotification && _userIsScrolling) {
      final geometry = _geometry;
      if (geometry == null) return;
      final millis = geometry.millisAtScrollOffset(notification.metrics.pixels);
      _player.seek(Duration(milliseconds: millis));
    }
  }

  void _onPanStart(DragStartDetails details) {
    final geometry = _geometry;
    final timeline = _timeline;
    if (geometry == null || timeline == null) return;

    final contentX = details.localPosition.dx + _scrollController.offset;
    final cutsById = {for (final c in timeline.cuts) c.id: c.millis};
    final hit = geometry.cutNear(
      contentX,
      cutsById: cutsById,
      toleranceMillis: _cutHitToleranceMillis,
    );

    if (hit != null) {
      setState(() {
        _draggingCutId = hit;
        _selectedCutId = hit;
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final draggingId = _draggingCutId;
    final geometry = _geometry;
    final timeline = _timeline;
    if (draggingId == null || geometry == null || timeline == null) return;

    final contentX = details.localPosition.dx + _scrollController.offset;
    timeline.moveCut(draggingId, geometry.millisForX(contentX));
    setState(() {}); // repaint the moved cut line
  }

  void _onPanEnd(DragEndDetails details) {
    if (_draggingCutId == null) return;
    setState(() => _draggingCutId = null);
  }

  void _addCutAtPlayhead() {
    final timeline = _timeline;
    if (timeline == null) return;

    final cut = timeline.addCut(_player.position.inMilliseconds);
    if (cut == null) {
      _showMessage('Too close to another cut, or the start/end of the track.');
      return;
    }
    setState(() => _selectedCutId = cut.id);
  }

  void _deleteSelectedCut() {
    final timeline = _timeline;
    final selected = _selectedCutId;
    if (timeline == null || selected == null) return;

    timeline.removeCut(selected);
    setState(() => _selectedCutId = null);
  }

  Future<void> _resetCuts() async {
    final timeline = _timeline;
    if (timeline == null || timeline.cuts.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove every cut?'),
        content: Text(
          '${timeline.cuts.length} '
          '${timeline.cuts.length == 1 ? 'cut' : 'cuts'} will be removed. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove all'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      timeline.clear();
      setState(() => _selectedCutId = null);
    }
  }

  Future<void> _export() async {
    final parsed = _parsed;
    final timeline = _timeline;
    if (parsed == null || timeline == null) return;

    await _player.pause();
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ExportScreen(
          parsed: parsed,
          cutMillis: timeline.cuts.map((c) => c.millis.toDouble()).toList(),
          sourceFileName: sourceFileNameFrom(widget.filePath),
        ),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          sourceFileNameFrom(widget.filePath),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _ErrorView(message: _error!)
            : _buildEditor(theme),
      ),
    );
  }

  Widget _buildEditor(ThemeData theme) {
    final timeline = _timeline!;

    return Column(
      children: [
        Expanded(
          child: Center(
            // Cuts/segments only ever change through methods in this State
            // that already call setState, so this just needs to read the
            // current count each rebuild — no separate listenable needed.
            child: Text(
              '${timeline.cuts.length} '
              '${timeline.cuts.length == 1 ? 'cut' : 'cuts'} · '
              '${timeline.segments.length} '
              '${timeline.segments.length == 1 ? 'segment' : 'segments'}',
              style: theme.textTheme.titleMedium,
            ),
          ),
        ),
        _PositionReadout(player: _player, totalMillis: _parsed!.totalMillis),
        _TransportRow(player: _player),
        SizedBox(
          height: 120,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              _handleScrollNotification(notification);
              return false;
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                _viewportWidth = constraints.maxWidth;
                final geometry = WaveformGeometry.forTrack(
                  trackMillis: timeline.trackMillis,
                  basePixelsPerSecond: _pixelsPerSecond,
                  viewportWidth: _viewportWidth,
                );

                return Stack(
                  children: [
                    GestureDetector(
                      onPanStart: _onPanStart,
                      onPanUpdate: _onPanUpdate,
                      onPanEnd: _onPanEnd,
                      onPanCancel: () => setState(() => _draggingCutId = null),
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        scrollDirection: Axis.horizontal,
                        physics: _draggingCutId != null
                            ? const NeverScrollableScrollPhysics()
                            : null,
                        child: SizedBox(
                          width: geometry.contentWidth,
                          height: constraints.maxHeight,
                          child: CustomPaint(
                            painter: WaveformPainter(
                              geometry: geometry,
                              amplitudes: _amplitudes,
                              cutsById: {
                                for (final c in timeline.cuts) c.id: c.millis,
                              },
                              selectedCutId: _selectedCutId,
                              barColor: theme.colorScheme.primary.withValues(
                                alpha: 0.6,
                              ),
                              cutColor: theme.colorScheme.secondary,
                              selectedCutColor: theme.colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // The playhead: fixed in the viewport, never scrolls.
                    Positioned(
                      left: _viewportWidth / 2 - 1,
                      top: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        child: Container(
                          width: 2,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        _BottomToolbar(
          hasSelection: _selectedCutId != null,
          hasCuts: timeline.cuts.isNotEmpty,
          onCut: _addCutAtPlayhead,
          onDelete: _deleteSelectedCut,
          onReset: _resetCuts,
          onExport: timeline.cuts.isEmpty && timeline.segments.length <= 1
              ? null
              : _export,
        ),
      ],
    );
  }
}

class _PositionReadout extends StatelessWidget {
  const _PositionReadout({required this.player, required this.totalMillis});

  final AudioPlayer player;
  final double totalMillis;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            '${_formatMillis(position.inMilliseconds)} / '
            '${_formatMillis(totalMillis.round())}',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontFeatures: const [
              FontFeature.tabularFigures(),
            ]),
          ),
        );
      },
    );
  }
}

class _TransportRow extends StatelessWidget {
  const _TransportRow({required this.player});

  final AudioPlayer player;

  void _skip(int deltaMillis) {
    final target = player.position + Duration(milliseconds: deltaMillis);
    final duration = player.duration ?? Duration.zero;
    player.seek(
      target < Duration.zero
          ? Duration.zero
          : (target > duration ? duration : target),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          iconSize: 28,
          icon: const Icon(Icons.replay_5),
          onPressed: () => _skip(-5000),
        ),
        const SizedBox(width: 16),
        StreamBuilder<PlayerState>(
          stream: player.playerStateStream,
          builder: (context, snapshot) {
            final playing = snapshot.data?.playing ?? false;
            return IconButton.filled(
              iconSize: 36,
              icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              onPressed: () => playing ? player.pause() : player.play(),
            );
          },
        ),
        const SizedBox(width: 16),
        IconButton(
          iconSize: 28,
          icon: const Icon(Icons.forward_5),
          onPressed: () => _skip(5000),
        ),
      ],
    );
  }
}

class _BottomToolbar extends StatelessWidget {
  const _BottomToolbar({
    required this.hasSelection,
    required this.hasCuts,
    required this.onCut,
    required this.onDelete,
    required this.onReset,
    required this.onExport,
  });

  final bool hasSelection;
  final bool hasCuts;
  final VoidCallback onCut;
  final VoidCallback onDelete;
  final VoidCallback onReset;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ToolButton(icon: Icons.content_cut, label: 'Cut', onTap: onCut),
            _ToolButton(
              icon: Icons.delete_outline,
              label: 'Delete',
              onTap: hasSelection ? onDelete : null,
            ),
            _ToolButton(
              icon: Icons.restart_alt,
              label: 'Reset',
              onTap: hasCuts ? onReset : null,
            ),
            _ToolButton(
              icon: Icons.ios_share,
              label: 'Export',
              onTap: onExport,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = onTap == null
        ? theme.disabledColor
        : theme.colorScheme.onSurface;

    return InkResponse(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 2),
            Text(label, style: theme.textTheme.labelSmall?.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

String _formatMillis(int millis) {
  final totalSeconds = millis ~/ 1000;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// Extracted so tests can check filename handling without a real path.
String sourceFileNameFrom(String path) => path.split(Platform.pathSeparator).last;
