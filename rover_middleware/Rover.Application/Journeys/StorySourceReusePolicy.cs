using System.Text.RegularExpressions;
using Rover.Application.LocationIntelligence;

namespace Rover.Application.Journeys;

public static class StorySourceReusePolicy
{
    private const string LicenseUrl = "https://creativecommons.org/publicdomain/zero/1.0/";
    private const string RightsUrl = "https://www.wikidata.org/wiki/Wikidata:Copyright";
    private const string Version = "wikidata-structured-v1";

    // Only the structured-data provider can establish this grant, never a web citation.
    public static StorySourceReuse? FromLocationSource(LocationSource source) =>
        source.ProviderName == "Wikidata" && source.License is "CC0" or "CC0-1.0" &&
        IsEntity(source.SourceUrl, source.ProviderRecordId)
            ? new("CC0-1.0", LicenseUrl, RightsUrl, "structured-data", source.ProviderRecordId!, Version)
            : null;

    public static bool AllowsServerReuse(AdaptiveStorySource source) =>
        source.ProviderName == "Wikidata" &&
        !string.IsNullOrWhiteSpace(source.Attribution) &&
        source.Reuse is { LicenseId: "CC0-1.0", ContentScope: "structured-data" } rights &&
        rights.LicenseUrl == LicenseUrl && rights.RightsUrl == RightsUrl &&
        rights.PolicyVersion == Version && IsEntity(source.Url, rights.ProviderRecordId);

    private static bool IsEntity(string? url, string? id) =>
        id is not null && Regex.IsMatch(id, @"\AQ[1-9][0-9]*\z") &&
        Uri.TryCreate(url, UriKind.Absolute, out var uri) &&
        uri.Scheme == Uri.UriSchemeHttps && uri.IsDefaultPort &&
        uri.IdnHost == "www.wikidata.org" && uri.UserInfo.Length == 0 &&
        uri.Query.Length == 0 && uri.Fragment.Length == 0 &&
        (uri.AbsolutePath == $"/entity/{id}" || uri.AbsolutePath == $"/wiki/{id}");
}
