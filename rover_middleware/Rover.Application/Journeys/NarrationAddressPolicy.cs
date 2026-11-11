using System.Text.RegularExpressions;

namespace Rover.Application.Journeys;

// Presentation only: never run this over place records, coordinates, evidence or map labels.
public static class NarrationAddressPolicy
{
    public const string Instructions = "In every spoken story variant, omit routine street addresses, building/unit numbers and postal/ZIP codes. Use the place name or a natural geographic reference instead. Keep street names only when relevant to the story. Preserve historical dates, quantities, distances and meaningful proper names such as Route 66. Addresses may be used for research and location verification, but belong in map/place metadata, not narration. Do not replace an address with 'here' or 'in front of you' unless the listener's presence is established.";

    // Deliberately constrained to explicit address phrases, not arbitrary numbers in historical prose.
    // Worldwide phrasing is handled by the research instruction; this guard covers common English
    // address leakage in older drafts without guessing whether an unrecognised number is an address.
    private static readonly Regex Address = new(
        @"\b(?<lead>(?i:at|located at|situated at|based at))\s+(?<number>\d{1,5}[A-Za-z]?(?:[-–]\d{1,5})?)\s+(?<street>(?:(?:[A-ZÀ-ÖØ-Þ][\p{L}'’.-]*|\d{1,3}(?:st|nd|rd|th)|de|la|du|des)\s+){1,6}(?i:Street|St\.?|Road|Rd\.?|Avenue|Ave\.?|Boulevard|Blvd\.?|Lane|Ln\.?|Drive|Dr\.?|Court|Ct\.?|Crescent|Terrace|Way|Place|Square)(?:\s+(?i:North|South|East|West|NW|NE|SW|SE))?)(?![\p{L}])",
        RegexOptions.CultureInvariant, TimeSpan.FromMilliseconds(100));
    private static readonly Regex PostalLabel = new(
        @"(?:,?\s*)(?i:postal code|postcode|zip code|zip)\s*:?\s*(?:[A-Z]\d[A-Z]\s?\d[A-Z]\d|[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}|\d{5}(?:-\d{4})?)(?![\p{L}\d])",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant, TimeSpan.FromMilliseconds(100));

    public static string ForStory(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return text;
        var cleaned = Address.Replace(text, match =>
        {
            // A negative or contrasting address can be the factual point; do not broaden it.
            var prefix = text[..match.Index];
            if (Regex.IsMatch(prefix, @"\b(not|never)\s+$", RegexOptions.IgnoreCase)) return match.Value;
            var lead = match.Groups["lead"].Value;
            return (lead.Equals("at", StringComparison.OrdinalIgnoreCase) ? (char.IsUpper(lead[0]) ? "On" : "on") : lead[..^2] + "on") + " " + match.Groups["street"].Value;
        });
        return PostalLabel.Replace(cleaned, "").Trim();
    }
}
