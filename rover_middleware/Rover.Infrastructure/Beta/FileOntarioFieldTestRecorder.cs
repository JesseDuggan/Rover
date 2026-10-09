using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Rover.Application.LocationIntelligence;
using Rover.Application.Beta;

namespace Rover.Infrastructure.Beta;

public sealed class FileOntarioFieldTestRecorder(OntarioFieldTestOptions options, TimeProvider clock,
    ILogger<FileOntarioFieldTestRecorder> logger) : IOntarioFieldTestRecorder
{
    private readonly object _gate = new();
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    public void Record(OntarioFieldTestEvent entry)
    {
        if (!options.Enabled || !options.Markets.TryGetValue(entry.Market, out var market)
            || entry.Market.Any(c => !char.IsAsciiLetterOrDigit(c) && c != '-')) return;
        try
        {
            lock (_gate)
            {
                var root = Path.GetFullPath(options.ReportDirectory);
                Directory.CreateDirectory(root);
                var now = clock.GetUtcNow();
                foreach (var path in Directory.EnumerateFiles(root, "*-events-????????.jsonl"))
                    if (File.GetLastWriteTimeUtc(path) < now.UtcDateTime.AddDays(-Math.Clamp(options.RetentionDays, 1, 90))) File.Delete(path);
                var file = Path.Combine(root, $"{entry.Market}-events-{now:yyyyMMdd}.jsonl");
                // Bound disk use; telemetry must never prevent a journey or narration.
                if (File.Exists(file) && new FileInfo(file).Length > 5_000_000)
                { logger.LogWarning("Ontario field-test daily report limit reached for {Market}", entry.Market); return; }
                var safe = entry with
                {
                    GeographicProfileId = entry.GeographicProfileId ?? market.GeographicProfileId,
                    WalkSessionId = entry.WalkSessionId is null ? null : Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(entry.WalkSessionId)))[..24],
                    Feedback = entry.Feedback is null ? null : entry.Feedback with { ProfileId = Guid.Empty,
                        Comments = RedactionService.Redact(entry.Feedback.Comments) }
                };
                File.AppendAllText(file, JsonSerializer.Serialize(new { recordedUtc = now, entry = safe }, Json) + Environment.NewLine);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException)
        { logger.LogWarning("Ontario field-test report could not be saved ({Kind})", error.GetType().Name); }
    }
}
