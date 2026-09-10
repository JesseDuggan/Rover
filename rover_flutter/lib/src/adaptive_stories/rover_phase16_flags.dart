class RoverPhase16Flags {
  const RoverPhase16Flags({this.enabled = true});

  final bool enabled;

  factory RoverPhase16Flags.fromEnvironment() => const RoverPhase16Flags(
    enabled: bool.fromEnvironment('ROVER_PHASE16_ENABLED', defaultValue: true),
  );
}
