// ignore_for_file: prefer_initializing_formals

import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../api/speech_models.dart';
import '../api/walk_repository.dart';
import 'rover_audio_services.dart';

abstract class RoverPremiumAudioPlayer {
  Future<void> play(List<int> bytes);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
}

class NativePremiumAudioPlayer implements RoverPremiumAudioPlayer {
  @override
  Future<void> play(List<int> bytes) async {
    await voiceChannel.invokeMethod<void>('premiumAudioPlayBytes', {
      'bytes': Uint8List.fromList(bytes),
    });
  }

  @override
  Future<void> pause() async {
    await voiceChannel.invokeMethod<void>('premiumAudioPause');
  }

  @override
  Future<void> resume() async {
    await voiceChannel.invokeMethod<void>('premiumAudioResume');
  }

  @override
  Future<void> stop() async {
    await voiceChannel.invokeMethod<void>('premiumAudioStop');
  }
}

class RoverPremiumVoiceCoordinator {
  RoverPremiumVoiceCoordinator({
    required WalkRepository walkRepository,
    RoverPremiumAudioPlayer? player,
    this.enabled = true,
    this.fallbackEnabled = true,
  }) : _walkRepository = walkRepository,
       _player = player ?? NativePremiumAudioPlayer();

  final WalkRepository _walkRepository;
  final RoverPremiumAudioPlayer _player;
  final bool enabled;
  final bool fallbackEnabled;
  final Map<String, Future<RenderedSpeechAudio>> _audioRequests = {};

  String statusMessage = 'Premium Rover voice ready.';
  RenderedSpeechAudio? lastAudio;
  String? lastPlaybackError;

  Future<void> prefetch({
    required String text,
    required String purpose,
    String? walkSessionId,
    String? stopId,
    bool audioCacheEligible = false,
    DateTime? cacheExpiresUtc,
    String? storyId,
    String? variantId,
  }) async {
    if (!enabled || text.trim().isEmpty) {
      return;
    }

    final key = _cacheKey(
      text: text,
      purpose: purpose,
      walkSessionId: walkSessionId,
      stopId: stopId,
    );
    _audioRequests.putIfAbsent(
      key,
      () => _renderSpeech(
        text: text,
        purpose: purpose,
        walkSessionId: walkSessionId,
        stopId: stopId,
        audioCacheEligible: audioCacheEligible,
        cacheExpiresUtc: cacheExpiresUtc,
        storyId: storyId,
        variantId: variantId,
      ),
    );
    try {
      final audio = await _audioRequests[key];
      if (audio?.usedFallback == true) {
        _audioRequests.remove(key);
        statusMessage =
            'Premium voice unavailable during prefetch; playback will retry.';
      } else {
        statusMessage = 'Premium Rover voice warmed for upcoming story.';
      }
    } catch (error) {
      _audioRequests.remove(key);
      lastPlaybackError = '$error';
      statusMessage = 'Premium Rover voice prefetch failed: $error';
    }
  }

  Future<bool> speak({
    required String text,
    required String purpose,
    String? walkSessionId,
    String? stopId,
    bool audioCacheEligible = false,
    DateTime? cacheExpiresUtc,
    String? storyId,
    String? variantId,
  }) async {
    if (!enabled) {
      statusMessage = 'Using device voice.';
      return false;
    }

    try {
      lastPlaybackError = null;
      final key = _cacheKey(
        text: text,
        purpose: purpose,
        walkSessionId: walkSessionId,
        stopId: stopId,
      );
      final audio = await _audioRequests.putIfAbsent(
        key,
        () => _renderSpeech(
          text: text,
          purpose: purpose,
          walkSessionId: walkSessionId,
          stopId: stopId,
          audioCacheEligible: audioCacheEligible,
          cacheExpiresUtc: cacheExpiresUtc,
          storyId: storyId,
          variantId: variantId,
        ),
      );
      lastAudio = audio;
      if (audio.usedFallback) {
        final reason = audio.fallbackReason;
        statusMessage = reason == null || reason.isEmpty
            ? 'Using device voice. Premium provider returned fallback audio.'
            : 'Using device voice. Premium fallback: $reason';
        return false;
      }

      await _player.play(audio.bytes);
      statusMessage =
          'Using premium Rover voice (${audio.provider}, ${audio.cacheStatus}, ${audio.bytes.length} bytes).';
      return true;
    } catch (error) {
      lastPlaybackError = '$error';
      statusMessage =
          'Using device voice. Premium playback/request failed: $error';
      return false;
    }
  }

  Future<RenderedSpeechAudio> _renderSpeech({
    required String text,
    required String purpose,
    String? walkSessionId,
    String? stopId,
    bool audioCacheEligible = false,
    DateTime? cacheExpiresUtc,
    String? storyId,
    String? variantId,
  }) {
    return _walkRepository.renderSpeech(
      RenderSpeechRequest(
        text: text,
        purpose: purpose,
        walkSessionId: walkSessionId,
        stopId: stopId,
        idempotencyKey: _cacheKey(
          text: text,
          purpose: purpose,
          walkSessionId: walkSessionId,
          stopId: stopId,
        ),
        cacheEligible: audioCacheEligible,
        cacheExpiresUtc: cacheExpiresUtc,
        storyId: storyId,
        variantId: variantId,
      ),
    );
  }

  String _cacheKey({
    required String text,
    required String purpose,
    String? walkSessionId,
    String? stopId,
  }) {
    return '$purpose:$walkSessionId:$stopId:${text.hashCode}';
  }

  Future<void> pause() => _player.pause();
  Future<void> resume() => _player.resume();
  Future<void> stop() => _player.stop();
}
