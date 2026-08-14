import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'crash_log_file.dart';
import 'editor_screen.dart';
import 'video_extract_screen.dart';

/// The only other screen: pick an mp3, then go straight to editing it.
/// Nothing here persists between launches — each session is one file, start
/// to export, which is the whole point of "just split an mp3".
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _pickFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3'],
    );
    final path = result?.files.single.path;
    if (path == null || !context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => EditorScreen(filePath: path),
      ),
    );
  }

  Future<void> _pickVideo(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    final path = result?.files.single.path;
    if (path == null || !context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => VideoExtractScreen(videoPath: path),
      ),
    );
  }

  /// Shares the on-device crash log, if a crash has ever been recorded.
  /// Checked at tap time rather than pre-computed into an enabled/disabled
  /// button state — simpler, and avoids that state going stale if a crash
  /// is logged without a full app relaunch.
  Future<void> _shareCrashLog(BuildContext context) async {
    final file = await crashLogFile();
    if (!await file.exists()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No crashes recorded yet.')),
      );
      return;
    }
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('MP3 Splitter'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: 'Share crash log',
            onPressed: () => _shareCrashLog(context),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.content_cut,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Split an mp3 by ear, export clean new mp3s.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Cuts land on real frame boundaries, so every export is a '
                'byte-for-byte copy of the original — no re-encoding, no '
                'quality loss.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () => _pickFile(context),
                icon: const Icon(Icons.folder_open),
                label: const Text('Pick an MP3'),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => _pickVideo(context),
                icon: const Icon(Icons.movie_creation_outlined),
                label: const Text('Extract audio from a video'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
