class LocalDiscoveryOptionsResult {
  const LocalDiscoveryOptionsResult({
    required this.provider,
    required this.radiusDegrees,
    required this.maximumDistanceMeters,
    required this.options,
    this.discoveryError,
  });

  final String provider;
  final double radiusDegrees;
  final int maximumDistanceMeters;
  final List<LocalDiscoveryOption> options;
  final String? discoveryError;

  bool get hasEnabledOptions =>
      options.any((option) => option.hasSelectableSamples);

  LocalDiscoveryOption? optionFor(String value) {
    for (final option in options) {
      if (option.value == value) {
        return option;
      }
    }
    return null;
  }

  factory LocalDiscoveryOptionsResult.fromJson(Map<String, dynamic> json) {
    return LocalDiscoveryOptionsResult(
      provider: json['provider'] as String? ?? 'Unknown',
      radiusDegrees: (json['radiusDegrees'] as num?)?.toDouble() ?? 0,
      maximumDistanceMeters: json['maximumDistanceMeters'] as int? ?? 0,
      discoveryError: json['discoveryError'] as String?,
      options: (json['options'] as List? ?? const [])
          .map(
            (item) =>
                LocalDiscoveryOption.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class LocalDiscoveryOption {
  const LocalDiscoveryOption({
    required this.value,
    required this.label,
    required this.count,
    required this.enabled,
    required this.samples,
  });

  final String value;
  final String label;
  final int count;
  final bool enabled;
  final List<LocalDiscoverySample> samples;

  int get selectableCount => samples.length;

  bool get hasSelectableSamples => enabled && samples.isNotEmpty;

  factory LocalDiscoveryOption.fromJson(Map<String, dynamic> json) {
    return LocalDiscoveryOption(
      value: json['value'] as String,
      label: json['label'] as String,
      count: json['count'] as int? ?? 0,
      enabled: json['enabled'] as bool? ?? false,
      samples: (json['samples'] as List? ?? const [])
          .map(
            (item) =>
                LocalDiscoverySample.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class LocalDiscoverySample {
  const LocalDiscoverySample({
    required this.stopId,
    required this.name,
    required this.category,
    required this.distanceMeters,
    this.address,
    this.websiteUrl,
    this.phoneNumber,
    this.menuUrl,
  });

  final String stopId;
  final String name;
  final String category;
  final int distanceMeters;
  final String? address;
  final String? websiteUrl;
  final String? phoneNumber;
  final String? menuUrl;

  factory LocalDiscoverySample.fromJson(Map<String, dynamic> json) {
    return LocalDiscoverySample(
      stopId: json['stopId'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      distanceMeters: json['distanceMeters'] as int? ?? 0,
      address: json['address'] as String?,
      websiteUrl: json['websiteUrl'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
      menuUrl: json['menuUrl'] as String?,
    );
  }
}
