using System.Text;
using System.Text.RegularExpressions;

namespace Rover.Application.Speech;

public static partial class SpeechTextPreparer
{
    public static PreparedSpeechText Prepare(RenderSpeechCommand command, int maximumCharacters)
    {
        var text = Normalize(command.Text);
        if (string.IsNullOrWhiteSpace(text))
        {
            throw new ArgumentException("Speech text is required.");
        }

        if (text.Length > maximumCharacters)
        {
            throw new ArgumentException($"Speech text must be {maximumCharacters} characters or fewer.");
        }

        return new PreparedSpeechText(
            text,
            command.Purpose,
            string.IsNullOrWhiteSpace(command.Locale) ? "en-US" : command.Locale.Trim(),
            $"{command.Purpose}:v1");
    }

    private static string Normalize(string value)
    {
        var builder = new StringBuilder(value.Length);
        foreach (var ch in value)
        {
            if (char.IsControl(ch) && ch is not '\r' and not '\n' and not '\t')
            {
                continue;
            }

            builder.Append(ch);
        }

        var text = WhitespaceRegex().Replace(builder.ToString(), " ").Trim();
        text = text.Replace(" St.", " Street", StringComparison.Ordinal);
        text = text.Replace(" Ave.", " Avenue", StringComparison.Ordinal);
        text = text.Replace(" Rd.", " Road", StringComparison.Ordinal);
        return text;
    }

    [GeneratedRegex(@"\s+")]
    private static partial Regex WhitespaceRegex();
}
