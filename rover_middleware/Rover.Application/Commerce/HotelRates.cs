namespace Rover.Application.Commerce;

public enum HotelRateSearchStatus
{
    Available,
    NoAvailability,
    ProviderUnavailable,
    AmbiguousProperty
}

public sealed record HotelRateSearchQuery(
    string HotelName,
    string? PlaceId,
    double Latitude,
    double Longitude,
    DateOnly CheckInDate,
    DateOnly CheckOutDate,
    int Adults,
    int Rooms,
    string Currency);

public sealed record HotelRateOffer(
    string ProviderName,
    string RoomName,
    decimal TotalAmount,
    string Currency,
    bool IncludesTaxesAndFees,
    bool? Refundable,
    Uri BookingUri,
    string Disclosure);

public sealed record HotelRateProviderResult(
    HotelRateSearchStatus Status,
    string ResolvedHotelName,
    IReadOnlyList<HotelRateOffer> Offers,
    string Message,
    string Disclosure);

public sealed record HotelRateSearchResult(
    HotelRateSearchStatus Status,
    string ResolvedHotelName,
    DateTimeOffset CheckedAtUtc,
    IReadOnlyList<HotelRateOffer> Offers,
    string Message,
    string Disclosure);

public interface IHotelRateProvider
{
    Task<HotelRateProviderResult> SearchAsync(
        HotelRateSearchQuery query,
        CancellationToken cancellationToken);
}

public interface IHotelRateSearchService
{
    Task<HotelRateSearchResult> SearchAsync(
        HotelRateSearchQuery query,
        CancellationToken cancellationToken);
}

public sealed class HotelRateSearchService : IHotelRateSearchService
{
    private readonly IHotelRateProvider _provider;
    private readonly TimeProvider _timeProvider;

    public HotelRateSearchService(IHotelRateProvider provider, TimeProvider timeProvider)
    {
        _provider = provider;
        _timeProvider = timeProvider;
    }

    public async Task<HotelRateSearchResult> SearchAsync(
        HotelRateSearchQuery query,
        CancellationToken cancellationToken)
    {
        Validate(query);

        var providerResult = await _provider.SearchAsync(query, cancellationToken);
        var offers = providerResult.Offers
            .Where(offer => offer.TotalAmount >= 0)
            .OrderBy(offer => offer.TotalAmount)
            .ThenByDescending(offer => offer.IncludesTaxesAndFees)
            .ThenBy(offer => offer.ProviderName, StringComparer.OrdinalIgnoreCase)
            .ToArray();

        var status = providerResult.Status == HotelRateSearchStatus.Available && offers.Length == 0
            ? HotelRateSearchStatus.NoAvailability
            : providerResult.Status;

        return new HotelRateSearchResult(
            status,
            providerResult.ResolvedHotelName,
            _timeProvider.GetUtcNow(),
            offers,
            providerResult.Message,
            providerResult.Disclosure);
    }

    private static void Validate(HotelRateSearchQuery query)
    {
        if (string.IsNullOrWhiteSpace(query.HotelName) || query.HotelName.Trim().Length > 200)
        {
            throw new ArgumentException("Hotel name is required and must be 200 characters or fewer.");
        }

        if (query.Latitude is < -90 or > 90 || query.Longitude is < -180 or > 180)
        {
            throw new ArgumentException("Hotel coordinates are invalid.");
        }

        if (query.CheckOutDate <= query.CheckInDate)
        {
            throw new ArgumentException("Check-out must be after check-in.");
        }

        if (query.CheckOutDate.DayNumber - query.CheckInDate.DayNumber > 30)
        {
            throw new ArgumentException("Hotel stays may not exceed 30 nights.");
        }

        if (query.Adults is < 1 or > 12 || query.Rooms is < 1 or > 6 || query.Rooms > query.Adults)
        {
            throw new ArgumentException("Adults and rooms are outside the supported range.");
        }

        if (query.Currency.Length != 3 || !query.Currency.All(char.IsLetter))
        {
            throw new ArgumentException("Currency must be a three-letter code.");
        }
    }
}
