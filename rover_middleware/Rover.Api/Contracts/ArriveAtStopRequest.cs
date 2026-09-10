namespace Rover.Api.Contracts;

public sealed record ArriveAtStopRequest(
    double? Latitude,
    double? Longitude);
