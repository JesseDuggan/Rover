import 'dart:math' as math;

import '../location/rover_location.dart';

class RoverStop {
  const RoverStop({
    required this.id,
    required this.name,
    required this.image,
    required this.shortDescription,
    required this.estimatedVisitMinutes,
    required this.coordinates,
    required this.category,
    required this.whySelected,
    this.distanceFromPreviousStopMeters = 0,
    this.arrivalRadiusMeters = 40,
    this.audio,
    this.narration,
    this.contentType,
    this.contentSource,
    this.sponsoredDisclosure,
    this.address,
    this.websiteUrl,
    this.phoneNumber,
    this.menuUrl,
    this.discoveryProviderName,
    this.providerPlaceId,
    this.sourceUrl,
    this.requiredAttribution = const [],
  });

  final String id;
  final String name;
  final String image;
  final String shortDescription;
  final int estimatedVisitMinutes;
  final RoverLatLng coordinates;
  final String category;
  final String whySelected;
  final int distanceFromPreviousStopMeters;
  final int arrivalRadiusMeters;
  final String? audio;
  final String? narration;
  final String? contentType;
  final String? contentSource;
  final String? sponsoredDisclosure;
  final String? address;
  final String? websiteUrl;
  final String? phoneNumber;
  final String? menuUrl;
  final String? discoveryProviderName;
  final String? providerPlaceId;
  final String? sourceUrl;
  final List<String> requiredAttribution;

  String? get attributionLabel => requiredAttribution.isEmpty
      ? null
      : requiredAttribution.toSet().join(', ');

  bool get isSponsored =>
      contentSource?.toLowerCase() == 'sponsored' ||
      sponsoredDisclosure != null;

  RoverStop copyWith({
    String? id,
    String? name,
    String? image,
    String? shortDescription,
    int? estimatedVisitMinutes,
    RoverLatLng? coordinates,
    String? category,
    String? whySelected,
    int? distanceFromPreviousStopMeters,
    int? arrivalRadiusMeters,
    String? audio,
    String? narration,
    String? contentType,
    String? contentSource,
    String? sponsoredDisclosure,
    String? address,
    String? websiteUrl,
    String? phoneNumber,
    String? menuUrl,
    String? discoveryProviderName,
    String? providerPlaceId,
    String? sourceUrl,
    List<String>? requiredAttribution,
  }) {
    return RoverStop(
      id: id ?? this.id,
      name: name ?? this.name,
      image: image ?? this.image,
      shortDescription: shortDescription ?? this.shortDescription,
      estimatedVisitMinutes:
          estimatedVisitMinutes ?? this.estimatedVisitMinutes,
      coordinates: coordinates ?? this.coordinates,
      category: category ?? this.category,
      whySelected: whySelected ?? this.whySelected,
      distanceFromPreviousStopMeters:
          distanceFromPreviousStopMeters ?? this.distanceFromPreviousStopMeters,
      arrivalRadiusMeters: arrivalRadiusMeters ?? this.arrivalRadiusMeters,
      audio: audio ?? this.audio,
      narration: narration ?? this.narration,
      contentType: contentType ?? this.contentType,
      contentSource: contentSource ?? this.contentSource,
      sponsoredDisclosure: sponsoredDisclosure ?? this.sponsoredDisclosure,
      address: address ?? this.address,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      menuUrl: menuUrl ?? this.menuUrl,
      discoveryProviderName:
          discoveryProviderName ?? this.discoveryProviderName,
      providerPlaceId: providerPlaceId ?? this.providerPlaceId,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      requiredAttribution: requiredAttribution ?? this.requiredAttribution,
    );
  }
}

class OrderedRoverStop {
  const OrderedRoverStop({required this.sequence, required this.stop});

  final int sequence;
  final RoverStop stop;
}

class RoverRouteManeuver {
  const RoverRouteManeuver({
    required this.sequenceNumber,
    required this.instruction,
    required this.distanceMeters,
    required this.durationMinutes,
    required this.maneuverType,
    this.location,
  });

  final int sequenceNumber;
  final String instruction;
  final int distanceMeters;
  final int durationMinutes;
  final String maneuverType;
  final RoverLatLng? location;
}

class RoverRoam {
  const RoverRoam({
    required this.title,
    required this.summary,
    required this.walkingMinutes,
    required this.distanceMiles,
    required this.startingPoint,
    required this.stops,
    required this.routeGeometry,
    required this.accessibilityNotes,
    required this.warnings,
    this.routeProvider = 'Unknown',
    this.routeManeuvers = const [],
    this.walkSessionId,
  });

  final String title;
  final String summary;
  final int walkingMinutes;
  final double distanceMiles;
  final String startingPoint;
  final List<RoverStop> stops;
  final List<RoverLatLng> routeGeometry;
  final List<String> accessibilityNotes;
  final List<String> warnings;
  final String routeProvider;
  final List<RoverRouteManeuver> routeManeuvers;
  final String? walkSessionId;

  int get contentMinutes {
    return stops.fold(0, (total, stop) => total + stop.estimatedVisitMinutes);
  }

  int get totalEstimatedMinutes => walkingMinutes + contentMinutes;

  List<OrderedRoverStop> get orderedStops {
    return [
      for (var index = 0; index < stops.length; index++)
        OrderedRoverStop(sequence: index + 1, stop: stops[index]),
    ];
  }

  RoverRoam copyWith({
    String? title,
    String? summary,
    int? walkingMinutes,
    double? distanceMiles,
    String? startingPoint,
    List<RoverStop>? stops,
    List<RoverLatLng>? routeGeometry,
    List<String>? accessibilityNotes,
    List<String>? warnings,
    String? routeProvider,
    List<RoverRouteManeuver>? routeManeuvers,
    String? walkSessionId,
  }) {
    final nextStops = stops ?? this.stops;
    final nextGeometry =
        routeGeometry ?? nextStops.map((stop) => stop.coordinates).toList();
    return RoverRoam(
      title: title ?? this.title,
      summary: summary ?? this.summary,
      walkingMinutes: walkingMinutes ?? _walkingMinutesFor(nextStops),
      distanceMiles: distanceMiles ?? _distanceFor(nextStops),
      startingPoint: startingPoint ?? this.startingPoint,
      stops: List.unmodifiable(nextStops),
      routeGeometry: List.unmodifiable(nextGeometry),
      accessibilityNotes: accessibilityNotes ?? this.accessibilityNotes,
      warnings: warnings ?? this.warnings,
      routeProvider: routeProvider ?? this.routeProvider,
      routeManeuvers: routeManeuvers ?? this.routeManeuvers,
      walkSessionId: walkSessionId ?? this.walkSessionId,
    );
  }

  RoverRoam removeStop(String stopId) {
    return copyWith(stops: stops.where((stop) => stop.id != stopId).toList());
  }

  RoverRoam replaceStop(String stopId, RoverStop replacement) {
    return copyWith(
      stops: [for (final stop in stops) stop.id == stopId ? replacement : stop],
    );
  }

  RoverRoam reorderStop(int oldIndex, int newIndex) {
    final updated = [...stops];
    final stop = updated.removeAt(oldIndex);
    updated.insert(newIndex.clamp(0, updated.length), stop);
    return copyWith(stops: updated);
  }

  bool fitsBudget(int availableMinutes) {
    return totalEstimatedMinutes <= availableMinutes;
  }

  static int _walkingMinutesFor(List<RoverStop> stops) {
    if (stops.isEmpty) {
      return 0;
    }
    if (stops.length <= 1) {
      return 8;
    }
    return 8 + ((stops.length - 1) * 7);
  }

  static double _distanceFor(List<RoverStop> stops) {
    if (stops.isEmpty) {
      return 0;
    }
    if (stops.length <= 1) {
      return 0.3;
    }
    var distance = 0.0;
    for (var index = 1; index < stops.length; index++) {
      distance += _distanceBetween(
        stops[index - 1].coordinates,
        stops[index].coordinates,
      );
    }
    return double.parse(math.max(0.3, distance).toStringAsFixed(1));
  }

  static double _distanceBetween(RoverLatLng a, RoverLatLng b) {
    final latMiles = (a.latitude - b.latitude).abs() * 69;
    final lngMiles =
        (a.longitude - b.longitude).abs() *
        69 *
        math.cos(a.latitude * math.pi / 180);
    return math.sqrt((latMiles * latMiles) + (lngMiles * lngMiles));
  }
}
