enum HotelRateSearchStatus {
  available,
  noAvailability,
  providerUnavailable,
  ambiguousProperty,
  unknown;

  static HotelRateSearchStatus fromJson(String? value) {
    switch (value?.toLowerCase()) {
      case 'available':
        return HotelRateSearchStatus.available;
      case 'noavailability':
        return HotelRateSearchStatus.noAvailability;
      case 'providerunavailable':
        return HotelRateSearchStatus.providerUnavailable;
      case 'ambiguousproperty':
        return HotelRateSearchStatus.ambiguousProperty;
      default:
        return HotelRateSearchStatus.unknown;
    }
  }
}

class HotelRateSearchRequest {
  const HotelRateSearchRequest({
    required this.hotelName,
    required this.placeId,
    required this.latitude,
    required this.longitude,
    required this.checkInDate,
    required this.checkOutDate,
    required this.adults,
    required this.rooms,
    this.currency = 'CAD',
  });

  final String hotelName;
  final String? placeId;
  final double latitude;
  final double longitude;
  final DateTime checkInDate;
  final DateTime checkOutDate;
  final int adults;
  final int rooms;
  final String currency;

  Map<String, Object?> toJson() => {
    'hotelName': hotelName,
    'placeId': placeId,
    'latitude': latitude,
    'longitude': longitude,
    'checkInDate': _dateOnly(checkInDate),
    'checkOutDate': _dateOnly(checkOutDate),
    'adults': adults,
    'rooms': rooms,
    'currency': currency,
  };
}

class HotelRateOffer {
  const HotelRateOffer({
    required this.providerName,
    required this.roomName,
    required this.totalAmount,
    required this.currency,
    required this.includesTaxesAndFees,
    required this.refundable,
    required this.bookingUrl,
    required this.disclosure,
  });

  factory HotelRateOffer.fromJson(Map<String, dynamic> json) => HotelRateOffer(
    providerName: json['providerName'] as String? ?? 'Booking provider',
    roomName: json['roomName'] as String? ?? 'Room',
    totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0,
    currency: json['currency'] as String? ?? 'CAD',
    includesTaxesAndFees: json['includesTaxesAndFees'] as bool? ?? false,
    refundable: json['refundable'] as bool?,
    bookingUrl: json['bookingUrl'] as String? ?? '',
    disclosure: json['disclosure'] as String? ?? '',
  );

  final String providerName;
  final String roomName;
  final double totalAmount;
  final String currency;
  final bool includesTaxesAndFees;
  final bool? refundable;
  final String bookingUrl;
  final String disclosure;
}

class HotelRateSearchResult {
  const HotelRateSearchResult({
    required this.status,
    required this.resolvedHotelName,
    required this.checkedAtUtc,
    required this.offers,
    required this.message,
    required this.disclosure,
  });

  factory HotelRateSearchResult.fromJson(Map<String, dynamic> json) =>
      HotelRateSearchResult(
        status: HotelRateSearchStatus.fromJson(json['status'] as String?),
        resolvedHotelName: json['resolvedHotelName'] as String? ?? '',
        checkedAtUtc:
            DateTime.tryParse(json['checkedAtUtc'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        offers: (json['offers'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(HotelRateOffer.fromJson)
            .toList(growable: false),
        message: json['message'] as String? ?? '',
        disclosure: json['disclosure'] as String? ?? '',
      );

  final HotelRateSearchStatus status;
  final String resolvedHotelName;
  final DateTime checkedAtUtc;
  final List<HotelRateOffer> offers;
  final String message;
  final String disclosure;
}

String _dateOnly(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}
