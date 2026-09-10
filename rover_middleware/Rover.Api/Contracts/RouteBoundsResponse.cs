namespace Rover.Api.Contracts;

public sealed record RouteBoundsResponse(RouteCoordinateResponse Southwest, RouteCoordinateResponse Northeast);
