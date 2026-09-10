using Rover.Domain.Walks;

namespace Rover.Application.Walks;

public static class RouteMath
{
    private const double EarthRadiusMeters = 6371000;

    public static double DistanceMeters(GeoLocation a, GeoLocation b)
    {
        var lat1 = DegreesToRadians(a.Latitude);
        var lat2 = DegreesToRadians(b.Latitude);
        var dLat = DegreesToRadians(b.Latitude - a.Latitude);
        var dLon = DegreesToRadians(b.Longitude - a.Longitude);

        var h = Math.Sin(dLat / 2) * Math.Sin(dLat / 2)
            + Math.Cos(lat1) * Math.Cos(lat2) * Math.Sin(dLon / 2) * Math.Sin(dLon / 2);

        return EarthRadiusMeters * 2 * Math.Atan2(Math.Sqrt(h), Math.Sqrt(1 - h));
    }

    public static double DistanceFromRouteMeters(GeoLocation point, IReadOnlyList<GeoLocation> route)
    {
        if (route.Count == 0)
        {
            return double.MaxValue;
        }

        if (route.Count == 1)
        {
            return DistanceMeters(point, route[0]);
        }

        var best = double.MaxValue;
        for (var i = 1; i < route.Count; i++)
        {
            best = Math.Min(best, DistanceToSegmentMeters(point, route[i - 1], route[i]));
        }

        return best;
    }

    public static double ProgressPercentage(GeoLocation point, WalkRoute route)
    {
        var coordinates = route.Coordinates;
        if (coordinates.Count < 2 || route.DistanceMeters <= 0)
        {
            return 0;
        }

        var traveledBeforeSegment = 0d;
        var bestDistance = double.MaxValue;
        var bestProgressMeters = 0d;

        for (var i = 1; i < coordinates.Count; i++)
        {
            var start = coordinates[i - 1];
            var end = coordinates[i];
            var segmentLength = DistanceMeters(start, end);
            var (distance, ratio) = DistanceToSegmentMetersWithRatio(point, start, end);
            if (distance < bestDistance)
            {
                bestDistance = distance;
                bestProgressMeters = traveledBeforeSegment + segmentLength * ratio;
            }

            traveledBeforeSegment += segmentLength;
        }

        return Math.Clamp(Math.Round(bestProgressMeters / route.DistanceMeters * 100, 2), 0, 100);
    }

    public static int EstimateMinutesRemaining(WalkRoute route, double progressPercentage)
    {
        return Math.Max(0, (int)Math.Ceiling(route.DurationMinutes * (100 - Math.Clamp(progressPercentage, 0, 100)) / 100));
    }

    public static double DistanceToSegmentMeters(GeoLocation point, GeoLocation start, GeoLocation end)
    {
        return DistanceToSegmentMetersWithRatio(point, start, end).DistanceMeters;
    }

    private static (double DistanceMeters, double Ratio) DistanceToSegmentMetersWithRatio(GeoLocation point, GeoLocation start, GeoLocation end)
    {
        var originLat = DegreesToRadians(start.Latitude);
        var metersPerLat = 111320d;
        var metersPerLon = Math.Cos(originLat) * 111320d;

        var px = (point.Longitude - start.Longitude) * metersPerLon;
        var py = (point.Latitude - start.Latitude) * metersPerLat;
        var ex = (end.Longitude - start.Longitude) * metersPerLon;
        var ey = (end.Latitude - start.Latitude) * metersPerLat;
        var lengthSquared = ex * ex + ey * ey;

        if (lengthSquared == 0)
        {
            return (DistanceMeters(point, start), 0);
        }

        var ratio = Math.Clamp((px * ex + py * ey) / lengthSquared, 0, 1);
        var dx = px - ex * ratio;
        var dy = py - ey * ratio;
        return (Math.Sqrt(dx * dx + dy * dy), ratio);
    }

    private static double DegreesToRadians(double degrees) => degrees * Math.PI / 180;
}
