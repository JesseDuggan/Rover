import '../location/rover_location.dart';

class AskRoverRequest {
  const AskRoverRequest({
    required this.questionText,
    required this.recordedAtUtc,
    this.currentStopId,
    this.location,
    this.conversationId,
  });

  final String questionText;
  final DateTime recordedAtUtc;
  final String? currentStopId;
  final RoverLatLng? location;
  final String? conversationId;

  Map<String, Object?> toJson() {
    return {
      'questionText': questionText,
      'currentStopId': currentStopId,
      'latitude': location?.latitude,
      'longitude': location?.longitude,
      'recordedAtUtc': recordedAtUtc.toUtc().toIso8601String(),
      'conversationId': conversationId,
    };
  }
}

class AskRoverResponse {
  const AskRoverResponse({
    required this.conversationId,
    required this.turnId,
    required this.answerText,
    required this.createdAtUtc,
    required this.provider,
    required this.suggestedAction,
    this.currentStopId,
    this.safetyNotice,
  });

  final String conversationId;
  final String turnId;
  final String answerText;
  final DateTime createdAtUtc;
  final String? currentStopId;
  final String provider;
  final String suggestedAction;
  final String? safetyNotice;

  factory AskRoverResponse.fromJson(Map<String, dynamic> json) {
    return AskRoverResponse(
      conversationId: json['conversationId'] as String,
      turnId: json['turnId'] as String,
      answerText: json['answerText'] as String,
      createdAtUtc: DateTime.parse(json['createdAtUtc'] as String),
      currentStopId: json['currentStopId'] as String?,
      provider: json['provider'] as String,
      suggestedAction: json['suggestedAction'] as String,
      safetyNotice: json['safetyNotice'] as String?,
    );
  }
}
