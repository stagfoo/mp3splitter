import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'editor_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('MP3 Splitter')),
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
            ],
          ),
        ),
      ),
    );
  }
}
