class WalkPlaceSelection {
  const WalkPlaceSelection({
    required this.query,
    required this.placeId,
    required this.isDestination,
  });
  final String query;
  final String placeId;
  final bool isDestination;
  Map<String, Object?> toJson() => {
    'query': query,
    'placeId': placeId,
    'isDestination': isDestination,
  };
}

class WalkPlaceOption {
  const WalkPlaceOption({
    required this.placeId,
    required this.name,
    required this.address,
    required this.attribution,
  });
  final String placeId;
  final String name;
  final String? address;
  final String attribution;
  factory WalkPlaceOption.fromJson(Map<String, dynamic> json) =>
      WalkPlaceOption(
        placeId: json['placeId'] as String,
        name: json['name'] as String,
        address: json['address'] as String?,
        attribution: json['attribution'] as String? ?? '',
      );
}

class WalkPlaceSearchResult {
  const WalkPlaceSearchResult(this.places, this.warnings);
  final List<WalkPlaceOption> places;
  final List<String> warnings;
  factory WalkPlaceSearchResult.fromJson(Map<String, dynamic> json) =>
      WalkPlaceSearchResult(
        (json['places'] as List? ?? [])
            .map(
              (item) => WalkPlaceOption.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(),
        (json['warnings'] as List? ?? []).cast<String>(),
      );
}

abstract class WalkPlaceRepository {
  Future<WalkPlaceSearchResult> searchWalkPlaces({
    required String query,
    required double latitude,
    required double longitude,
  });
}
