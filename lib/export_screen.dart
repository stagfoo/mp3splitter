import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'audio_speed_changer.dart';
import 'mp3_export.dart';
import 'mp3_frame_parser.dart';

/// Runs the export and shows the resulting files, each shareable on its own
/// or all together.
class ExportScreen extends StatefulWidget {
  const ExportScreen({
    super.key,
    required this.parsed,
    required this.cutMillis,
    required this.sourceFileName,
  });

  final ParsedMp3 parsed;
  final List<double> cutMillis;
  final String sourceFileName;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  double _speed = 1.0;
  bool _started = false;
  String? _progressLabel;
  List<ExportedFile>? _files;
  String? _error;

  void _startExport() {
    setState(() => _started = true);
    _run();
  }

  Future<void> _run() async {
    try {
      final files = await exportSegments(
        parsed: widget.parsed,
        cutMillis: widget.cutMillis,
        sourceFileName: widget.sourceFileName,
      );

      if (_speed < 1.0) {
        await _applySlowDown(files);
      }

      if (!mounted) return;
      setState(() => _files = files);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = "Export failed: $e");
    }
  }

  /// Runs after the lossless split, re-encoding each already-written
  /// segment in place at [_speed]. Sequential rather than parallel so the
  /// progress label means something and multiple ffmpeg sessions don't
  /// contend for the same CPU at once.
  Future<void> _applySlowDown(List<ExportedFile> files) async {
    if (files.isEmpty) return;

    final sampleRate = await probeSampleRate(files.first.file.path);
    for (var i = 0; i < files.length; i++) {
      if (!mounted) return;
      setState(() => _progressLabel = 'Slowing down ${i + 1} of ${files.length}…');

      await slowDownInPlace(
        files[i].file.path,
        speed: _speed,
        sourceSampleRate: sampleRate,
      );
      files[i] = files[i].withSizeBytes(await files[i].file.length());
    }
  }

  Future<void> _shareOne(ExportedFile file) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.file.path)]),
    );
  }

  Future<void> _shareAll(List<ExportedFile> files) async {
    await SharePlus.instance.share(
      ShareParams(files: [for (final f in files) XFile(f.file.path)]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final files = _files;

    return Scaffold(
      appBar: AppBar(title: const Text('Export')),
      body: SafeArea(
        child: _error != null
            ? _ErrorView(message: _error!)
            : !_started
            ? _SpeedConfigView(
                speed: _speed,
                onSpeedChanged: (v) => setState(() => _speed = v),
                onExport: _startExport,
              )
            : files == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    if (_progressLabel != null) ...[
                      const SizedBox(height: 16),
                      Text(_progressLabel!),
                    ],
                  ],
                ),
              )
            : files.isEmpty
            ? const Center(child: Text('Nothing to export.'))
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: files.length,
                itemBuilder: (context, index) {
                  final file = files[index];
                  final durationMillis = _speed < 1.0
                      ? (file.result.durationMillis / _speed).round()
                      : file.result.durationMillis.round();
                  return ListTile(
                    leading: const Icon(Icons.audiotrack),
                    title: Text(file.result.label),
                    subtitle: Text(
                      '${_formatMillis(durationMillis)} · '
                      '${_formatSize(file.sizeBytes)}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.ios_share),
                      tooltip: 'Share',
                      onPressed: () => _shareOne(file),
                    ),
                  );
                },
              ),
      ),
      bottomNavigationBar: files == null || files.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton.icon(
                  onPressed: () => _shareAll(files),
                  icon: const Icon(Icons.ios_share),
                  label: Text('Share all ${files.length}'),
                ),
              ),
            ),
    );
  }
}

/// Lets the user pick an export speed before the (potentially slow, ffmpeg
/// re-encoded) export begins. 1.0 skips the speed-change pass entirely —
/// export stays the fast, lossless byte-copy split it always was.
class _SpeedConfigView extends StatelessWidget {
  const _SpeedConfigView({
    required this.speed,
    required this.onSpeedChanged,
    required this.onExport,
  });

  final double speed;
  final ValueChanged<double> onSpeedChanged;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSlowed = speed < 1.0;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.slow_motion_video, size: 48),
            const SizedBox(height: 16),
            Text(
              isSlowed ? '${(speed * 100).round()}% speed' : 'Normal speed',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              isSlowed
                  ? 'Pitch drops along with tempo — the classic slowed-down sound.'
                  : 'Drag the slider left to slow the track down before export.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            Slider(
              value: speed,
              min: 0.5,
              max: 1.0,
              divisions: 10,
              label: '${(speed * 100).round()}%',
              onChanged: onSpeedChanged,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onExport,
              icon: const Icon(Icons.ios_share),
              label: const Text('Export'),
            ),
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

String _formatSize(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
