using System.Text.RegularExpressions;

namespace Rover.Application.Beta;

public static partial class RedactionService
{
    public static string Redact(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return string.Empty;
        }

        var redacted = EmailRegex().Replace(value, "[redacted-email]");
        redacted = SecretRegex().Replace(redacted, "[redacted-secret]");
        redacted = MapboxTokenRegex().Replace(redacted, "[redacted-mapbox-token]");
        redacted = TokenLabelRegex().Replace(redacted, "$1[redacted-token]");
        return CoordinateRegex().Replace(redacted, "[redacted-coordinate]");
    }

    [GeneratedRegex(@"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}", RegexOptions.IgnoreCase)]
    private static partial Regex EmailRegex();

    [GeneratedRegex(@"(?i)(sk|pk)_[A-Za-z0-9_\-]{20,}|AKIA[0-9A-Z]{16}")]
    private static partial Regex SecretRegex();

    [GeneratedRegex(@"pk\.eyJ[A-Za-z0-9_\-.]+")]
    private static partial Regex MapboxTokenRegex();

    [GeneratedRegex(@"(?i)\b(token|api[_ -]?key|access[_ -]?token)\s*[:= ]\s*([^\s,;]+)")]
    private static partial Regex TokenLabelRegex();

    [GeneratedRegex(@"-?\d{1,3}\.\d{5,}")]
    private static partial Regex CoordinateRegex();
}
