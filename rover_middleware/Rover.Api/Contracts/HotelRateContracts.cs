namespace Rover.Api.Contracts;

public sealed record HotelRateSearchRequest(
    string HotelName,
    string? PlaceId,
    double Latitude,
    double Longitude,
    DateOnly CheckInDate,
    DateOnly CheckOutDate,
    int Adults,
    int Rooms,
    string? Currency);

public sealed record HotelRateOfferResponse(
    string ProviderName,
    string RoomName,
    decimal TotalAmount,
    string Currency,
    bool IncludesTaxesAndFees,
    bool? Refundable,
    string BookingUrl,
    string Disclosure);

public sealed record HotelRateSearchResponse(
    string Status,
    string ResolvedHotelName,
    DateTimeOffset CheckedAtUtc,
    IReadOnlyList<HotelRateOfferResponse> Offers,
    string Message,
    string Disclosure);
