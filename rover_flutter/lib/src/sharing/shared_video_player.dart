import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class SharedVideoPlayer extends StatelessWidget {
  const SharedVideoPlayer({
    super.key,
    required this.controller,
    required this.enabled,
    required this.onToggle,
  });
  final VideoPlayerController controller;
  final bool enabled;
  final VoidCallback onToggle;
  String time(Duration value) =>
      '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<VideoPlayerValue>(
    valueListenable: controller,
    builder: (context, value, _) => SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: value.aspectRatio,
                    child: VideoPlayer(controller),
                  ),
                ),
                if (!value.isPlaying)
                  Center(
                    child: IconButton.filled(
                      tooltip: 'Play video',
                      iconSize: 48,
                      onPressed: enabled ? onToggle : null,
                      icon: const Icon(Icons.play_arrow),
                    ),
                  ),
              ],
            ),
          ),
          if (value.hasError)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'Video playback failed. Close this viewer and try again.',
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: VideoProgressIndicator(controller, allowScrubbing: enabled),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 16, 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: value.isPlaying ? 'Pause' : 'Play',
                  onPressed: enabled ? onToggle : null,
                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                ),
                const SizedBox(width: 8),
                Text('${time(value.position)} / ${time(value.duration)}'),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
