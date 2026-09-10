import 'package:flutter/services.dart';

import 'rover_voice_state.dart';

const voiceChannel = MethodChannel('ai.myrover.rover/voice');

abstract class RoverTextToSpeech {
  Future<void> configure({required double rate});
  Future<void> speak(String text);
  Future<void> pause();
  Future<void> stop();
  Future<void> dispose();
}

abstract class RoverSpeechRecognizer {
  Future<MicrophonePermissionState> ensurePermission();
  Future<bool> initialize({
    required void Function(String text, bool finalResult) onResult,
    required void Function(String message) onError,
  });
  Future<void> listen();
  Future<void> stop();
  Future<void> cancel();
}

abstract class RoverAudioSessionCoordinator {
  Future<void> configure();
}

class DeviceAudioSessionCoordinator implements RoverAudioSessionCoordinator {
  @override
  Future<void> configure() async {
    await voiceChannel.invokeMethod<void>('audioConfigure');
  }
}

class DeviceTextToSpeech implements RoverTextToSpeech {
  @override
  Future<void> configure({required double rate}) async {
    await voiceChannel.invokeMethod<void>('ttsConfigure', {
      'rate': rate.clamp(0.3, 0.65),
    });
  }

  @override
  Future<void> speak(String text) async {
    await voiceChannel.invokeMethod<void>('ttsSpeak', {'text': text});
  }

  @override
  Future<void> pause() async {
    await voiceChannel.invokeMethod<void>('ttsPause');
  }

  @override
  Future<void> stop() async {
    await voiceChannel.invokeMethod<void>('ttsStop');
  }

  @override
  Future<void> dispose() => stop();
}

class DeviceSpeechRecognizer implements RoverSpeechRecognizer {
  void Function(String text, bool finalResult)? _onResult;
  void Function(String message)? _onError;

  @override
  Future<MicrophonePermissionState> ensurePermission() async {
    final status = await voiceChannel.invokeMethod<String>(
      'speechRequestPermission',
    );
    return _permissionStateFromNative(status);
  }

  @override
  Future<bool> initialize({
    required void Function(String text, bool finalResult) onResult,
    required void Function(String message) onError,
  }) async {
    _onResult = onResult;
    _onError = onError;
    final available = await voiceChannel.invokeMethod<bool>('speechInitialize');
    return available ?? false;
  }

  @override
  Future<void> listen() async {
    try {
      final text = await voiceChannel.invokeMethod<String>('speechListen');
      _onResult?.call(text ?? '', true);
    } on PlatformException catch (error) {
      _onError?.call(error.message ?? error.code);
    }
  }

  @override
  Future<void> stop() async {
    await voiceChannel.invokeMethod<void>('speechStop');
  }

  @override
  Future<void> cancel() => stop();
}

Future<bool> openNativeVoiceSettings() async {
  return await voiceChannel.invokeMethod<bool>('openSettings') ?? false;
}

MicrophonePermissionState _permissionStateFromNative(String? status) {
  return switch (status) {
    'granted' => MicrophonePermissionState.granted,
    'permanentlyDenied' => MicrophonePermissionState.permanentlyDenied,
    'unavailable' => MicrophonePermissionState.unavailable,
    _ => MicrophonePermissionState.denied,
  };
}
