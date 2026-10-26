import 'package:flutter/material.dart';

import '../adventure/roam.dart';
import 'rover_voice_controller.dart';
import 'rover_voice_state.dart';

class StopNarrationControls extends StatelessWidget {
  const StopNarrationControls({
    super.key,
    required this.stop,
    required this.voice,
  });
  final RoverStop stop;
  final RoverVoiceController voice;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: voice,
    builder: (context, _) {
      final active =
          voice.narrationStopId == stop.id && voice.activeStoryId == null;
      final playing =
          active && voice.state == RoverAudioState.speakingNarration;
      final paused =
          active &&
          voice.pausedNarrationStopId == stop.id &&
          voice.state == RoverAudioState.narrationPaused;
      final preparing =
          active && voice.state == RoverAudioState.preparingNarration;
      final otherAudio =
          [
            RoverAudioState.listening,
            RoverAudioState.transcribing,
            RoverAudioState.thinking,
          ].contains(voice.state) ||
          (voice.state == RoverAudioState.speakingAnswer &&
              voice.activeStoryId == null) ||
          !active &&
              (voice.state == RoverAudioState.speakingNarration ||
                  voice.state == RoverAudioState.preparingNarration);
      return Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: preparing || otherAudio
                ? null
                : playing
                ? voice.pauseNarration
                : paused
                ? voice.resumeNarration
                : () => voice.playNarration(stop),
            icon: Icon(playing ? Icons.pause : Icons.play_arrow),
            label: Text(
              preparing
                  ? 'Preparing audio'
                  : playing
                  ? 'Pause'
                  : paused
                  ? 'Resume'
                  : 'Play stop information',
            ),
          ),
          IconButton.outlined(
            tooltip: 'Stop stop information',
            onPressed: playing || paused || preparing
                ? voice.stopNarration
                : null,
            icon: const Icon(Icons.stop),
          ),
        ],
      );
    },
  );
}
