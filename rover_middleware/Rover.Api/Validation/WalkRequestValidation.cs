using Rover.Api.Contracts;
using Rover.Application.Adaptations;
using Rover.Application.Conversation;
using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Api.Validation;

public static class WalkRequestValidation
{
    private const int MinimumAvailableMinutes = 15;
    private const int MaximumAvailableMinutes = 240;
    private const int MaximumStaleLocationSeconds = 120;
    private const int MaximumQuestionLength = 500;
    private const int MinimumRouteRevision = 1;

    public static bool TryCreateCommand(CreateWalkRequest? request, out CreateWalkCommand? command, out Dictionary<string, string[]> errors)
    {
        errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        command = null;

        if (request is null)
        {
            errors["request"] = new[] { "A JSON request body is required." };
            return false;
        }

        if (request.Latitude is null or < -90 or > 90)
        {
            errors["latitude"] = new[] { "Latitude is required and must be between -90 and 90." };
        }

        if (request.Longitude is null or < -180 or > 180)
        {
            errors["longitude"] = new[] { "Longitude is required and must be between -180 and 180." };
        }

        if (request.AvailableMinutes is null or < MinimumAvailableMinutes or > MaximumAvailableMinutes)
        {
            errors["availableMinutes"] = new[] { $"Available minutes is required and must be between {MinimumAvailableMinutes} and {MaximumAvailableMinutes}." };
        }

        if (!TryParseEnum(request.WalkingPace, out WalkingPace walkingPace))
        {
            errors["walkingPace"] = new[] { $"Walking pace must be one of: {EnumList<WalkingPace>()}." };
        }

        var accessibilityPreferences = new List<AccessibilityPreference>();
        foreach (var value in request.AccessibilityPreferences ?? Array.Empty<string>())
        {
            if (TryParseEnum(value, out AccessibilityPreference preference))
            {
                accessibilityPreferences.Add(preference);
                continue;
            }

            errors["accessibilityPreferences"] = new[] { $"Accessibility preferences must use: {EnumList<AccessibilityPreference>()}." };
            break;
        }

        if (errors.Count > 0)
        {
            return false;
        }

        command = new CreateWalkCommand(
            new GeoLocation(request.Latitude!.Value, request.Longitude!.Value),
            request.AvailableMinutes!.Value,
            NormalizeInterests(request.Interests),
            walkingPace,
            accessibilityPreferences);

        return true;
    }

    public static bool TryCreateLocation(ArriveAtStopRequest? request, out GeoLocation? location, out Dictionary<string, string[]> errors)
    {
        errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        location = null;

        if (request is null || request.Latitude is null && request.Longitude is null)
        {
            return true;
        }

        if (request.Latitude is null or < -90 or > 90)
        {
            errors["latitude"] = new[] { "Latitude must be between -90 and 90 when provided." };
        }

        if (request.Longitude is null or < -180 or > 180)
        {
            errors["longitude"] = new[] { "Longitude must be between -180 and 180 when provided." };
        }

        if (errors.Count > 0)
        {
            return false;
        }

        location = new GeoLocation(request.Latitude!.Value, request.Longitude!.Value);
        return true;
    }

    public static bool TryCreateLocationUpdate(LocationUpdateRequest? request, DateTimeOffset now, out LocationUpdateCommand? command, out Dictionary<string, string[]> errors)
    {
        errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        command = null;

        if (request is null)
        {
            errors["request"] = new[] { "A JSON request body is required." };
            return false;
        }

        if (request.Latitude is null or < -90 or > 90)
        {
            errors["latitude"] = new[] { "Latitude is required and must be between -90 and 90." };
        }

        if (request.Longitude is null or < -180 or > 180)
        {
            errors["longitude"] = new[] { "Longitude is required and must be between -180 and 180." };
        }

        if (request.AccuracyMeters is < 0 or > 5000)
        {
            errors["accuracyMeters"] = new[] { "Accuracy must be between 0 and 5000 meters when provided." };
        }

        if (request.HeadingDegrees is < 0 or >= 360)
        {
            errors["headingDegrees"] = new[] { "Heading must be at least 0 and less than 360 degrees when provided." };
        }

        if (request.SpeedMetersPerSecond is < 0 or > 25)
        {
            errors["speedMetersPerSecond"] = new[] { "Walking speed must be between 0 and 25 meters per second when provided." };
        }

        if (request.RecordedAtUtc is null)
        {
            errors["recordedAtUtc"] = new[] { "Recorded timestamp is required." };
        }
        else if (request.RecordedAtUtc.Value.Offset != TimeSpan.Zero)
        {
            errors["recordedAtUtc"] = new[] { "Recorded timestamp must be UTC." };
        }
        else if (now - request.RecordedAtUtc.Value > TimeSpan.FromSeconds(MaximumStaleLocationSeconds))
        {
            errors["recordedAtUtc"] = new[] { $"Location readings older than {MaximumStaleLocationSeconds} seconds are rejected." };
        }
        else if (request.RecordedAtUtc.Value - now > TimeSpan.FromSeconds(30))
        {
            errors["recordedAtUtc"] = new[] { "Location readings from the future are rejected." };
        }

        if (errors.Count > 0)
        {
            return false;
        }

        command = new LocationUpdateCommand(
            new GeoLocation(request.Latitude!.Value, request.Longitude!.Value),
            request.AccuracyMeters,
            request.HeadingDegrees,
            request.SpeedMetersPerSecond,
            request.RecordedAtUtc!.Value);
        return true;
    }

    public static bool TryCreateAskRoverCommand(AskRoverRequest? request, DateTimeOffset now, out AskRoverCommand? command, out Dictionary<string, string[]> errors)
    {
        errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        command = null;

        if (request is null)
        {
            errors["request"] = new[] { "A JSON request body is required." };
            return false;
        }

        var question = request.QuestionText?.Trim();
        if (string.IsNullOrWhiteSpace(question))
        {
            errors["questionText"] = new[] { "Question text is required." };
        }
        else if (question.Length > MaximumQuestionLength)
        {
            errors["questionText"] = new[] { $"Question text must be {MaximumQuestionLength} characters or fewer." };
        }

        if (request.Latitude is < -90 or > 90)
        {
            errors["latitude"] = new[] { "Latitude must be between -90 and 90 when provided." };
        }

        if (request.Longitude is < -180 or > 180)
        {
            errors["longitude"] = new[] { "Longitude must be between -180 and 180 when provided." };
        }

        if ((request.Latitude is null) != (request.Longitude is null))
        {
            errors["location"] = new[] { "Latitude and longitude must be provided together." };
        }

        if (request.RecordedAtUtc is null)
        {
            errors["recordedAtUtc"] = new[] { "Recorded timestamp is required." };
        }
        else if (request.RecordedAtUtc.Value.Offset != TimeSpan.Zero)
        {
            errors["recordedAtUtc"] = new[] { "Recorded timestamp must be UTC." };
        }
        else if (now - request.RecordedAtUtc.Value > TimeSpan.FromSeconds(MaximumStaleLocationSeconds))
        {
            errors["recordedAtUtc"] = new[] { $"Question timestamps older than {MaximumStaleLocationSeconds} seconds are rejected." };
        }
        else if (request.RecordedAtUtc.Value - now > TimeSpan.FromSeconds(30))
        {
            errors["recordedAtUtc"] = new[] { "Question timestamps from the future are rejected." };
        }

        if (errors.Count > 0)
        {
            return false;
        }

        var location = request.Latitude is null
            ? null
            : new GeoLocation(request.Latitude.Value, request.Longitude!.Value);
        command = new AskRoverCommand(
            question!,
            string.IsNullOrWhiteSpace(request.CurrentStopId) ? null : request.CurrentStopId.Trim(),
            location,
            request.RecordedAtUtc!.Value,
            string.IsNullOrWhiteSpace(request.ConversationId) ? null : request.ConversationId.Trim());
        return true;
    }

    public static bool TryCreateAdaptationCommand(WalkAdaptationEvaluateRequest? request, out WalkAdaptationCommand? command, out Dictionary<string, string[]> errors)
    {
        errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        command = null;

        if (request is null)
        {
            errors["request"] = new[] { "A JSON request body is required." };
            return false;
        }

        if (request.RouteRevision is null or < MinimumRouteRevision)
        {
            errors["routeRevision"] = new[] { "Route revision is required and must be positive." };
        }

        if (request.Latitude is < -90 or > 90)
        {
            errors["latitude"] = new[] { "Latitude must be between -90 and 90 when provided." };
        }

        if (request.Longitude is < -180 or > 180)
        {
            errors["longitude"] = new[] { "Longitude must be between -180 and 180 when provided." };
        }

        if ((request.Latitude is null) != (request.Longitude is null))
        {
            errors["location"] = new[] { "Latitude and longitude must be provided together." };
        }

        WalkAdaptationType? requestedType = null;
        if (!string.IsNullOrWhiteSpace(request.RequestedType))
        {
            if (TryParseEnum(request.RequestedType, out WalkAdaptationType parsed))
            {
                requestedType = parsed;
            }
            else
            {
                errors["requestedType"] = new[] { $"Requested type must be one of: {EnumList<WalkAdaptationType>()}." };
            }
        }

        if (request.AvailableMinutes is < MinimumAvailableMinutes or > MaximumAvailableMinutes)
        {
            errors["availableMinutes"] = new[] { $"Available minutes must be between {MinimumAvailableMinutes} and {MaximumAvailableMinutes} when provided." };
        }

        if (errors.Count > 0)
        {
            return false;
        }

        var location = request.Latitude is null
            ? null
            : new GeoLocation(request.Latitude.Value, request.Longitude!.Value);

        command = new WalkAdaptationCommand(
            location,
            request.RouteRevision!.Value,
            requestedType,
            request.AvailableMinutes,
            string.IsNullOrWhiteSpace(request.UserRequest) ? null : request.UserRequest.Trim(),
            string.IsNullOrWhiteSpace(request.Interest) ? null : request.Interest.Trim(),
            string.IsNullOrWhiteSpace(request.ProposedDiscoveryId) ? null : request.ProposedDiscoveryId.Trim(),
            NormalizeInterests(request.DismissedDiscoveryIds));
        return true;
    }

    public static bool TryGetRouteRevision(WalkAdaptationAcceptRequest? request, out int routeRevision, out Dictionary<string, string[]> errors)
    {
        errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        routeRevision = 0;

        if (request?.RouteRevision is null or < MinimumRouteRevision)
        {
            errors["routeRevision"] = new[] { "Route revision is required and must be positive." };
            return false;
        }

        routeRevision = request.RouteRevision.Value;
        return true;
    }

    private static IReadOnlyCollection<string> NormalizeInterests(IReadOnlyCollection<string>? interests)
    {
        return (interests ?? Array.Empty<string>())
            .Select(interest => interest.Trim())
            .Where(interest => interest.Length > 0)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    private static bool TryParseEnum<TEnum>(string? value, out TEnum result)
        where TEnum : struct
    {
        result = default;

        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        return Enum.TryParse(value.Trim(), ignoreCase: true, out result);
    }

    private static string EnumList<TEnum>()
        where TEnum : struct, Enum
    {
        return string.Join(", ", Enum.GetNames<TEnum>());
    }
}
