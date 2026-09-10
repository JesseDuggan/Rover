using Rover.Application.Commerce;

namespace Rover.Infrastructure.Commerce;

public sealed class HotelRateOptions
{
    public bool Enabled { get; set; }
    public string Provider { get; set; } = "None";
    public string DefaultCurrency { get; set; } = "CAD";
}

public sealed class UnavailableHotelRateProvider : IHotelRateProvider
{
    public Task<HotelRateProviderResult> SearchAsync(
        HotelRateSearchQuery query,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult(
            new HotelRateProviderResult(
                HotelRateSearchStatus.ProviderUnavailable,
                query.HotelName.Trim(),
                Array.Empty<HotelRateOffer>(),
                "Live hotel rates are not available right now. You can keep exploring this place in Rover.",
                "No booking provider is configured. Rover has not estimated or fabricated a price."));
    }
}
