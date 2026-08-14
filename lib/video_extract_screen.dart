import 'package:flutter/material.dart';

import 'editor_screen.dart';
import 'video_audio_extractor.dart';

/// Shown while a video's audio is being pulled out and encoded to mp3.
/// Pushed in place of jumping straight to [EditorScreen] because, unlike
/// opening an mp3 (fast — it's just parsing frame headers), transcoding a
/// video can take anywhere from a couple of seconds to a while depending on
/// its length, so there needs to be somewhere to show that it's working.
class VideoExtractScreen extends StatefulWidget {
  const VideoExtractScreen({super.key, required this.videoPath});

  final String videoPath;

  @override
  State<VideoExtractScreen> createState() => _VideoExtractScreenState();
}

class _VideoExtractScreenState extends State<VideoExtractScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _extract();
  }

  Future<void> _extract() async {
    try {
      final mp3Path = await extractAudioToMp3(widget.videoPath);
      if (!mounted) return;
      // Replace, not push: the extraction screen has nothing to come back
      // to, so the back gesture from the editor should land on Home.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (context) => EditorScreen(filePath: mp3Path),
        ),
      );
    } on VideoExtractionException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = "Couldn't extract audio: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(videoFileNameFrom(widget.videoPath))),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: _error != null
                ? _ErrorView(message: _error!)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 24),
                      Text(
                        'Extracting audio…',
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back'),
        ),
      ],
    );
  }
}
