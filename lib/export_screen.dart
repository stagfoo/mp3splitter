import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

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
  List<ExportedFile>? _files;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final files = await exportSegments(
        parsed: widget.parsed,
        cutMillis: widget.cutMillis,
        sourceFileName: widget.sourceFileName,
      );
      if (!mounted) return;
      setState(() => _files = files);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = "Export failed: $e");
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
            : files == null
            ? const Center(child: CircularProgressIndicator())
            : files.isEmpty
            ? const Center(child: Text('Nothing to export.'))
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: files.length,
                itemBuilder: (context, index) {
                  final file = files[index];
                  return ListTile(
                    leading: const Icon(Icons.audiotrack),
                    title: Text(file.result.label),
                    subtitle: Text(
                      '${_formatMillis(file.result.durationMillis.round())} · '
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
