import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/api/hotel_rate_models.dart';

void main() {
  test('hotel rate request serializes date-only values', () {
    final request = HotelRateSearchRequest(
      hotelName: 'The Cove Country Inn',
      placeId: 'the-cove',
      latitude: 44.678,
      longitude: -76.397,
      checkInDate: DateTime(2026, 9, 1, 19, 30),
      checkOutDate: DateTime(2026, 9, 2, 10, 15),
      adults: 2,
      rooms: 1,
    );

    expect(request.toJson()['checkInDate'], '2026-09-01');
    expect(request.toJson()['checkOutDate'], '2026-09-02');
  });

  test('hotel rate response preserves provider status and disclosures', () {
    final result = HotelRateSearchResult.fromJson({
      'status': 'Available',
      'resolvedHotelName': 'The Cove Country Inn',
      'checkedAtUtc': '2026-08-31T12:00:00Z',
      'message': 'One offer found.',
      'disclosure': 'Rates may change.',
      'offers': [
        {
          'providerName': 'Test Provider',
          'roomName': 'Standard room',
          'totalAmount': 199.5,
          'currency': 'CAD',
          'includesTaxesAndFees': true,
          'refundable': true,
          'bookingUrl': 'https://example.test/book',
          'disclosure': 'Affiliate link.',
        },
      ],
    });

    expect(result.status, HotelRateSearchStatus.available);
    expect(result.offers, hasLength(1));
    expect(result.offers.single.totalAmount, 199.5);
    expect(result.offers.single.includesTaxesAndFees, isTrue);
    expect(result.offers.single.disclosure, 'Affiliate link.');
  });

  test('provider unavailable response never requires an offer', () {
    final result = HotelRateSearchResult.fromJson({
      'status': 'ProviderUnavailable',
      'resolvedHotelName': 'The Cove Country Inn',
      'checkedAtUtc': '2026-08-31T12:00:00Z',
      'message': 'Live rates are not available.',
      'disclosure': 'No price was fabricated.',
      'offers': <Object>[],
    });

    expect(result.status, HotelRateSearchStatus.providerUnavailable);
    expect(result.offers, isEmpty);
  });
}
