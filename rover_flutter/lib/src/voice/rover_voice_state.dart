enum RoverAudioState {
  idle,
  preparingNarration,
  speakingNarration,
  narrationPaused,
  listening,
  transcribing,
  thinking,
  speakingAnswer,
  error,
}

enum MicrophonePermissionState {
  unknown,
  granted,
  denied,
  permanentlyDenied,
  unavailable,
}

class RoverVoiceTurn {
  const RoverVoiceTurn({
    required this.questionText,
    required this.answerText,
    required this.provider,
    required this.suggestedAction,
    this.safetyNotice,
  });

  final String questionText;
  final String answerText;
  final String provider;
  final String suggestedAction;
  final String? safetyNotice;
}
