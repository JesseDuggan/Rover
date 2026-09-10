import 'hotel_rate_models.dart';
import 'rover_api_client.dart';

abstract interface class HotelRateRepository {
  Future<HotelRateSearchResult> search(HotelRateSearchRequest request);
}

class HttpHotelRateRepository implements HotelRateRepository {
  HttpHotelRateRepository({RoverApiClient? client})
    : _client = client ?? RoverApiClient();

  final RoverApiClient _client;

  @override
  Future<HotelRateSearchResult> search(HotelRateSearchRequest request) {
    return _client.searchHotelRates(request);
  }
}
