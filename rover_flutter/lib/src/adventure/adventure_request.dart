class AdventureRequest {
  const AdventureRequest({
    required this.availableMinutes,
    required this.startingPoint,
    required this.routeMode,
    required this.interests,
    required this.pace,
    required this.routeShape,
    required this.companions,
    required this.environment,
    required this.budget,
    required this.surpriseMe,
    required this.naturalRequest,
  });

  final int availableMinutes;
  final String startingPoint;
  final String routeMode;
  final List<String> interests;
  final String pace;
  final String routeShape;
  final String companions;
  final String environment;
  final String budget;
  final bool surpriseMe;
  final String naturalRequest;

  bool get isComplete =>
      validate().isEmpty &&
      routeMode.isNotEmpty &&
      (interests.isNotEmpty || surpriseMe) &&
      pace.isNotEmpty &&
      routeShape.isNotEmpty &&
      companions.isNotEmpty &&
      environment.isNotEmpty &&
      budget.isNotEmpty;

  AdventureRequest copyWith({
    int? availableMinutes,
    String? startingPoint,
    String? routeMode,
    List<String>? interests,
    String? pace,
    String? routeShape,
    String? companions,
    String? environment,
    String? budget,
    bool? surpriseMe,
    String? naturalRequest,
  }) {
    return AdventureRequest(
      availableMinutes: availableMinutes ?? this.availableMinutes,
      startingPoint: startingPoint ?? this.startingPoint,
      routeMode: routeMode ?? this.routeMode,
      interests: interests ?? this.interests,
      pace: pace ?? this.pace,
      routeShape: routeShape ?? this.routeShape,
      companions: companions ?? this.companions,
      environment: environment ?? this.environment,
      budget: budget ?? this.budget,
      surpriseMe: surpriseMe ?? this.surpriseMe,
      naturalRequest: naturalRequest ?? this.naturalRequest,
    );
  }

  List<String> validate() {
    final messages = <String>[];

    if (availableMinutes <= 0) {
      messages.add('Tell Riley how much time you have.');
    } else if (availableMinutes < 20) {
      messages.add(
        'Give Riley at least 20 minutes so the ROAM does not feel rushed.',
      );
    } else if (availableMinutes > 360) {
      messages.add(
        'That is a big day. Keep this request under 6 hours for now.',
      );
    }

    if (startingPoint.trim().isEmpty) {
      messages.add(
        'Add a starting point, even if it is just "near me" for now.',
      );
    }

    if (interests.isEmpty && !surpriseMe) {
      messages.add('Pick at least one interest, or choose Surprise me.');
    }

    return messages;
  }

  static const empty = AdventureRequest(
    availableMinutes: 90,
    startingPoint: '',
    routeMode: 'Walking',
    interests: [],
    pace: 'Easy',
    routeShape: 'Loop route',
    companions: 'Solo',
    environment: 'Either',
    budget: 'Free-only',
    surpriseMe: false,
    naturalRequest: 'I have 90 minutes. Take me for a walk.',
  );
}
