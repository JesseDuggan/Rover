using System.Text;
using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Application.LocationIntelligence;

public sealed class CandidateObservationResolutionService : ICandidateObservationResolutionService
{
    private const double VerifiedThreshold = 0.80;
    private const double VerifiedNameThreshold = 0.78;
    private const double AmbiguousThreshold = 0.55;
    private const double RequiredMargin = 0.10;

    private readonly ILocationStoryContextService _locationContext;
    private readonly LocationIntelligenceOptions _options;
    private readonly IReadOnlyList<ICandidateObservationSearchProvider> _searchProviders;

    public CandidateObservationResolutionService(
        ILocationStoryContextService locationContext,
        LocationIntelligenceOptions options,
        IEnumerable<ICandidateObservationSearchProvider>? searchProviders = null)
    {
        _locationContext = locationContext;
        _options = options;
        _searchProviders = searchProviders?.ToArray()
            ?? Array.Empty<ICandidateObservationSearchProvider>();
    }

    public async Task<CandidateObservationResolution> ResolveAsync(
        CandidateObservationQuery query,
        CancellationToken cancellationToken)
    {
        Validate(query);
        var contextTask = _locationContext.GetContextAsync(
            new LocationContextQuery(
                query.UserLocation,
                query.RadiusMeters,
                query.RouteId,
                null,
                Array.Empty<GeoLocation>(),
                Array.Empty<string>()),
            cancellationToken);
        var searchTasks = _searchProviders
            .Select(provider => SearchSafelyAsync(provider, query, cancellationToken))
            .ToArray();
        var context = await contextTask;
        var searchResults = searchTasks.Length == 0
            ? Array.Empty<CandidateObservationSearchResult>()
            : await Task.WhenAll(searchTasks);

        var nearbyIds = query.NearbyPlaceIds.ToHashSet(StringComparer.OrdinalIgnoreCase);
        var places = context.RankedPlaces
            .Concat(searchResults.SelectMany(result => result.Places))
            .GroupBy(place => place.CanonicalId, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.First());
        var warnings = context.SourceWarnings
            .Concat(searchResults.SelectMany(result => result.Warnings))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var matches = places
            .Select(place => Score(place, query, nearbyIds))
            .Where(match => match.NameSimilarity >= 0.35 && match.MatchConfidence >= 0.45)
            .OrderByDescending(match => match.MatchConfidence)
            .ThenBy(match => match.Place.DistanceFromUserMeters ?? double.MaxValue)
            .Take(3)
            .ToArray();

        if (matches.Length == 0)
        {
            return new CandidateObservationResolution(
                CandidateObservationResolutionStatus.Unresolved,
                null,
                Array.Empty<CandidateObservationMatch>(),
                "observation_unresolved",
                warnings);
        }

        var best = matches[0];
        var margin = matches.Length == 1
            ? 1
            : best.MatchConfidence - matches[1].MatchConfidence;
        if (best.MatchConfidence >= VerifiedThreshold
            && best.NameSimilarity >= VerifiedNameThreshold
            && margin >= RequiredMargin)
        {
            return new CandidateObservationResolution(
                CandidateObservationResolutionStatus.Verified,
                best.Place.CanonicalId,
                matches,
                "observation_verified",
                warnings);
        }

        var status = best.MatchConfidence >= AmbiguousThreshold
            ? CandidateObservationResolutionStatus.Ambiguous
            : CandidateObservationResolutionStatus.Unresolved;
        return new CandidateObservationResolution(
            status,
            null,
            matches,
            status == CandidateObservationResolutionStatus.Ambiguous
                ? "observation_ambiguous"
                : "observation_unresolved",
            warnings);
    }

    private static async Task<CandidateObservationSearchResult> SearchSafelyAsync(
        ICandidateObservationSearchProvider provider,
        CandidateObservationQuery query,
        CancellationToken cancellationToken)
    {
        try
        {
            return await provider.SearchAsync(query, cancellationToken);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return new CandidateObservationSearchResult(
                provider.GetType().Name,
                Array.Empty<LocationPlace>(),
                new[] { "Business search timed out." });
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (HttpRequestException)
        {
            return new CandidateObservationSearchResult(
                provider.GetType().Name,
                Array.Empty<LocationPlace>(),
                new[] { "Business search was unavailable." });
        }
        catch (Exception)
        {
            return new CandidateObservationSearchResult(
                provider.GetType().Name,
                Array.Empty<LocationPlace>(),
                new[] { "Business search could not be completed." });
        }
    }

    private static CandidateObservationMatch Score(
        LocationPlace place,
        CandidateObservationQuery query,
        IReadOnlySet<string> nearbyIds)
    {
        var nameSimilarity = NameSimilarity(query.RecognizedText, place.Name);
        var distance = place.DistanceFromUserMeters
            ?? RouteMath.DistanceMeters(query.UserLocation, place.Coordinates);
        var distanceScore = Math.Clamp(1 - distance / Math.Max(1, query.RadiusMeters), 0, 1);
        var headingScore = query.HeadingDegrees is null
            ? 0.5
            : Math.Clamp(1 - HeadingDifference(query.HeadingDegrees.Value, Bearing(query.UserLocation, place.Coordinates)) / 90, 0, 1);
        var evidenceScore = place.SourceReferences.Count > 0 ? 1 : 0.35;
        var hintBoost = nearbyIds.Contains(place.CanonicalId) ? 0.04 : 0;
        var confidence = Math.Clamp(
            nameSimilarity * 0.72
            + distanceScore * 0.12
            + headingScore * 0.10
            + evidenceScore * 0.06
            + hintBoost,
            0,
            1);

        var reasons = new List<string>();
        if (nameSimilarity >= 0.9)
        {
            reasons.Add("recognized text closely matches the place name");
        }
        else if (nameSimilarity >= 0.6)
        {
            reasons.Add("recognized text partially matches the place name");
        }

        if (distance <= 150)
        {
            reasons.Add("place is very close to the observation");
        }

        if (query.HeadingDegrees is not null && headingScore >= 0.75)
        {
            reasons.Add("place is in the observed direction");
        }

        if (nearbyIds.Contains(place.CanonicalId))
        {
            reasons.Add("place was already present in nearby sourced context");
        }

        return new CandidateObservationMatch(
            place,
            Math.Round(confidence, 3),
            Math.Round(nameSimilarity, 3),
            Math.Round(distanceScore, 3),
            Math.Round(headingScore, 3),
            reasons);
    }

    internal static double NameSimilarity(string recognizedText, string placeName)
    {
        var name = Normalize(placeName);
        var text = Normalize(recognizedText);
        if (name.Length == 0 || text.Length == 0)
        {
            return 0;
        }

        if ($" {text} ".Contains($" {name} ", StringComparison.Ordinal))
        {
            return 1;
        }

        var nameTokens = name.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        var textTokens = text.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        var candidates = new List<string> { text };
        var minimumWindow = Math.Max(1, nameTokens.Length - 1);
        var maximumWindow = Math.Min(textTokens.Length, nameTokens.Length + 1);
        for (var window = minimumWindow; window <= maximumWindow; window++)
        {
            for (var start = 0; start + window <= textTokens.Length; start++)
            {
                candidates.Add(string.Join(' ', textTokens.Skip(start).Take(window)));
            }
        }

        return candidates.Max(candidate => Math.Max(
            TokenSimilarity(candidate, name),
            EditSimilarity(candidate, name)));
    }

    private static double TokenSimilarity(string left, string right)
    {
        var leftTokens = left.Split(' ', StringSplitOptions.RemoveEmptyEntries).ToHashSet(StringComparer.Ordinal);
        var rightTokens = right.Split(' ', StringSplitOptions.RemoveEmptyEntries).ToHashSet(StringComparer.Ordinal);
        if (leftTokens.Count == 0 || rightTokens.Count == 0)
        {
            return 0;
        }

        var overlap = leftTokens.Intersect(rightTokens, StringComparer.Ordinal).Count();
        return 2d * overlap / (leftTokens.Count + rightTokens.Count);
    }

    private static double EditSimilarity(string left, string right)
    {
        var rows = left.Length + 1;
        var columns = right.Length + 1;
        var distances = new int[rows, columns];
        for (var row = 0; row < rows; row++) distances[row, 0] = row;
        for (var column = 0; column < columns; column++) distances[0, column] = column;
        for (var row = 1; row < rows; row++)
        {
            for (var column = 1; column < columns; column++)
            {
                var cost = left[row - 1] == right[column - 1] ? 0 : 1;
                distances[row, column] = Math.Min(
                    Math.Min(distances[row - 1, column] + 1, distances[row, column - 1] + 1),
                    distances[row - 1, column - 1] + cost);
            }
        }

        return 1d - (double)distances[rows - 1, columns - 1] / Math.Max(left.Length, right.Length);
    }

    private static string Normalize(string value)
    {
        var builder = new StringBuilder(value.Length);
        var pendingSpace = false;
        foreach (var character in value.ToLowerInvariant())
        {
            if (char.IsLetterOrDigit(character))
            {
                if (pendingSpace && builder.Length > 0) builder.Append(' ');
                builder.Append(character);
                pendingSpace = false;
            }
            else
            {
                pendingSpace = true;
            }
        }

        return builder.ToString();
    }

    private static double Bearing(GeoLocation from, GeoLocation to)
    {
        var lat1 = from.Latitude * Math.PI / 180;
        var lat2 = to.Latitude * Math.PI / 180;
        var deltaLongitude = (to.Longitude - from.Longitude) * Math.PI / 180;
        var y = Math.Sin(deltaLongitude) * Math.Cos(lat2);
        var x = Math.Cos(lat1) * Math.Sin(lat2)
            - Math.Sin(lat1) * Math.Cos(lat2) * Math.Cos(deltaLongitude);
        return (Math.Atan2(y, x) * 180 / Math.PI + 360) % 360;
    }

    private static double HeadingDifference(double left, double right)
    {
        var difference = Math.Abs((left - right) % 360);
        return difference > 180 ? 360 - difference : difference;
    }

    private void Validate(CandidateObservationQuery query)
    {
        if (string.IsNullOrWhiteSpace(query.RecognizedText) || query.RecognizedText.Trim().Length is < 2 or > 2000)
        {
            throw new ArgumentException("Recognized text must contain between 2 and 2000 characters.");
        }

        if (query.UserLocation.Latitude is < -90 or > 90 || query.UserLocation.Longitude is < -180 or > 180)
        {
            throw new ArgumentException("Latitude and longitude must be valid coordinates.");
        }

        if (query.AccuracyMeters is < 0 or > 200)
        {
            throw new ArgumentException("Accuracy must be between 0 and 200 meters when supplied.");
        }

        if (query.HeadingDegrees is < 0 or >= 360)
        {
            throw new ArgumentException("Heading must be between 0 and less than 360 degrees when supplied.");
        }

        if (query.RadiusMeters <= 0 || query.RadiusMeters > _options.MaxRadiusMeters)
        {
            throw new ArgumentException($"Radius must be between 1 and {_options.MaxRadiusMeters} meters.");
        }
    }
}
