using System.Text.RegularExpressions;

namespace Rover.Application.Journeys;

// Formatting equivalence only, not fuzzy matching or inferred historical aliases.
// Callers must still validate cited claims and the subject's geographic anchor.
public static class PlaceNameEvidence
{
    private static string Normalize(string value) => Regex.Replace(
        Regex.Replace(value.ToLowerInvariant().Replace('’', '\''), @"(?<=\p{L})'s\b", ""),
        @"[^\p{L}\p{N}]+", " ").Trim();

    public static bool Equivalent(string evidenceName, string suppliedName)
    {
        var name = Normalize(suppliedName);
        if (name.Length == 0) return false;
        var evidence = Normalize(evidenceName);
        if (evidence == name) return true;
        var parts = Regex.Split(suppliedName, @"\s+[-–—]\s+");
        return parts.Length == 2 && parts.All(p => Normalize(p).Length > 0)
            && evidence == Normalize(parts[1]) + " " + Normalize(parts[0]);
    }

    public static bool Contains(string evidence, string suppliedName)
    {
        var text = " " + Normalize(evidence) + " ";
        var name = Normalize(suppliedName);
        if (name.Length == 0) return false;
        if (text.Contains(" " + name + " ", StringComparison.Ordinal)) return true;
        // Map labels sometimes append locality after a spaced dash. Retain every
        // token; only allow the two intact phrases to exchange position.
        var parts = Regex.Split(suppliedName, @"\s+[-–—]\s+");
        return parts.Length == 2 && parts.All(p => Normalize(p).Length > 0)
            && text.Contains(" " + Normalize(parts[1]) + " " + Normalize(parts[0]) + " ", StringComparison.Ordinal);
    }
}
