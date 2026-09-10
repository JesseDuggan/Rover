namespace Rover.Domain.Walks;

public sealed class WalkStop
{
    public WalkStop(
        string stopId,
        int sequenceNumber,
        string name,
        GeoLocation location,
        string shortDescription,
        string narration,
        string category,
        ContentType contentType,
        ContentSource contentSource,
        int estimatedVisitMinutes,
        int distanceFromPreviousStopMeters,
        int arrivalRadiusMeters,
        string? sponsoredDisclosure = null,
        string? address = null,
        string? websiteUrl = null,
        string? phoneNumber = null,
        string? menuUrl = null,
        string? discoveryProviderName = null,
        string? providerPlaceId = null,
        string? sourceUrl = null,
        IReadOnlyCollection<string>? requiredAttribution = null)
    {
        StopId = stopId;
        SequenceNumber = sequenceNumber;
        Name = name;
        Location = location;
        ShortDescription = shortDescription;
        Narration = narration;
        Category = category;
        ContentType = contentType;
        ContentSource = contentSource;
        EstimatedVisitMinutes = estimatedVisitMinutes;
        DistanceFromPreviousStopMeters = distanceFromPreviousStopMeters;
        ArrivalRadiusMeters = arrivalRadiusMeters;
        SponsoredDisclosure = sponsoredDisclosure;
        Address = address;
        WebsiteUrl = websiteUrl;
        PhoneNumber = phoneNumber;
        MenuUrl = menuUrl;
        DiscoveryProviderName = discoveryProviderName;
        ProviderPlaceId = providerPlaceId;
        SourceUrl = sourceUrl;
        RequiredAttribution = requiredAttribution?.ToArray() ?? Array.Empty<string>();
    }

    public string StopId { get; }
    public int SequenceNumber { get; }
    public string Name { get; }
    public GeoLocation Location { get; }
    public string ShortDescription { get; }
    public string Narration { get; }
    public string Category { get; }
    public ContentType ContentType { get; }
    public ContentSource ContentSource { get; }
    public int EstimatedVisitMinutes { get; }
    public int DistanceFromPreviousStopMeters { get; }
    public int ArrivalRadiusMeters { get; }
    public string? SponsoredDisclosure { get; }
    public string? Address { get; }
    public string? WebsiteUrl { get; }
    public string? PhoneNumber { get; }
    public string? MenuUrl { get; }
    public string? DiscoveryProviderName { get; }
    public string? ProviderPlaceId { get; }
    public string? SourceUrl { get; }
    public IReadOnlyCollection<string> RequiredAttribution { get; }
    public StopArrivalState ArrivalState { get; private set; } = StopArrivalState.Pending;
    public bool Visited => ArrivalState == StopArrivalState.Arrived;
    public DateTimeOffset? ArrivedAtUtc { get; private set; }

    public void MarkArrived(DateTimeOffset arrivedAtUtc)
    {
        ArrivalState = StopArrivalState.Arrived;
        ArrivedAtUtc = arrivedAtUtc;
    }
}
