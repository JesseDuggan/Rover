import 'package:flutter/foundation.dart';

import '../api/rover_api_client.dart';
import '../api/problem_details.dart';
import '../api/story_question_models.dart';
import '../location/rover_location.dart';

class StoryQuestionContext {
  const StoryQuestionContext({
    required this.reading,
    this.walkId,
    this.routeRevision,
    this.routeGeometry = const [],
  });
  final RoverLocationReading reading;
  final String? walkId;
  final int? routeRevision;
  final List<RoverLatLng> routeGeometry;

  bool isFresh(DateTime now) {
    final point = reading.location;
    final accuracy = reading.accuracyMeters;
    return point.latitude.isFinite &&
        point.longitude.isFinite &&
        point.latitude.abs() <= 90 &&
        point.longitude.abs() <= 180 &&
        accuracy != null &&
        accuracy.isFinite &&
        accuracy >= 0 &&
        accuracy <= 40 &&
        now.toUtc().difference(reading.recordedAtUtc).abs() <=
            const Duration(minutes: 2);
  }

  bool matches(StoryQuestionContext other) =>
      walkId == other.walkId &&
      routeRevision == other.routeRevision &&
      reading.location.distanceTo(other.reading.location) <= 500;

  // Preserve the ordered polyline and endpoints while bounding the API payload.
  List<RoverLatLng> get boundedGeometry {
    if (routeGeometry.length <= 120) return routeGeometry;
    return [
      for (var i = 0; i < 120; i++)
        routeGeometry[(i * (routeGeometry.length - 1) / 119).round()],
    ];
  }
}

class StoryQuestionController extends ChangeNotifier {
  StoryQuestionController({
    required this.currentContext,
    RoverApiClient Function()? createClient,
    DateTime Function()? clock,
  }) : _createClient = createClient ?? RoverApiClient.new,
       _clock = clock ?? DateTime.now;

  final StoryQuestionContext? Function() currentContext;
  final RoverApiClient Function() _createClient;
  final DateTime Function() _clock;
  RoverApiClient? _client;
  bool _disposed = false;
  int _generation = 0;
  bool busy = false;
  String? message;
  StoryQuestionResponse? response;
  StoryQuestionContext? answerContext;

  bool get answersAreCurrent {
    final current = currentContext();
    return current != null &&
        current.isFresh(_clock()) &&
        answerContext?.matches(current) == true;
  }

  Future<void> ask(
    String question, {
    String scope = 'Auto',
    String format = 'Auto',
    int? storyCount,
  }) async {
    if (_disposed || busy) return;
    final text = question.trim();
    response = null;
    answerContext = null;
    final context = currentContext();
    if (text.isEmpty || text.length > 1200) {
      message = 'Enter a question of up to 1200 characters.';
      notifyListeners();
      return;
    }
    if (context == null || !context.isFresh(_clock())) {
      message = 'Waiting for an accurate current location. Please try again.';
      notifyListeners();
      return;
    }
    final generation = ++_generation;
    busy = true;
    message = 'Researching your question...';
    notifyListeners();
    final client = _createClient();
    _client = client;
    try {
      final result = await client.researchStoryQuestion(
        StoryQuestionRequest(
          question: text,
          location: context.reading.location,
          scope: scope,
          format: format,
          storyCount: storyCount,
          routeGeometry: context.boundedGeometry,
        ),
      );
      if (_disposed || generation != _generation) return;
      final current = currentContext();
      if (current == null ||
          !current.isFresh(_clock()) ||
          !context.matches(current)) {
        message =
            'Your location or route changed. Ask again for your current area.';
        return;
      }
      response = result;
      answerContext = context;
      message = switch (result.status) {
        'ready' when result.answers.isNotEmpty => null,
        'partial' =>
          result.message ?? 'Only part of your question could be verified.',
        'empty' => result.message ?? 'Not enough verified evidence was found.',
        'needs_route' =>
          'This question needs a route. Choose a local area scope instead.',
        _ => 'Research could not finish. Please try again.',
      };
    } on RoverApiException catch (error) {
      if (_disposed || generation != _generation) return;
      message = switch (error.statusCode) {
        404 => 'Question research is not available on this API version yet.',
        429 =>
          'Research is busy. Please wait a few minutes before trying again.',
        401 || 403 => 'Access to question research was denied. Check your app connection settings.',
        _ => 'Could not research your question. Check your connection and try again.',
      };
    } catch (_) {
      if (!_disposed && generation == _generation) {
        message = 'Could not research your question. Please try again.';
      }
    } finally {
      client.close(force: true);
      if (identical(_client, client)) _client = null;
      if (!_disposed && generation == _generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  void cancel() {
    _generation++;
    _client?.close(force: true);
    _client = null;
    busy = false;
    message = 'Research cancelled.';
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }
}
