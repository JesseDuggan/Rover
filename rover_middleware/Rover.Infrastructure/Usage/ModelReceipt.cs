using System.Text.Json;

namespace Rover.Infrastructure.Usage;

public sealed record ModelReceipt(string Model, long Input, long Cached, long Output, int Searches, double? EstimatedUsd)
{
    public static readonly HttpRequestOptionsKey<Action<ModelReceipt>> Callback = new("Walkabout.Usage.Receipt");

    public static void Report(HttpRequestMessage request, JsonElement json)
    {
        if (!request.Options.TryGetValue(Callback, out var record) || json.ValueKind != JsonValueKind.Object ||
            !json.TryGetProperty("model", out var modelNode) || modelNode.ValueKind != JsonValueKind.String ||
            !json.TryGetProperty("usage", out var usage) || usage.ValueKind != JsonValueKind.Object) return;
        var model = modelNode.GetString() ?? "";
        long Count(JsonElement node, string key) => node.ValueKind == JsonValueKind.Object &&
            node.TryGetProperty(key, out var n) && n.ValueKind == JsonValueKind.Number && n.TryGetInt64(out var v) ? Math.Max(0,v) : 0;
        var input = Count(usage,"input_tokens");
        var output = Count(usage,"output_tokens");
        var cached = usage.TryGetProperty("input_tokens_details", out var details) ? Math.Min(input,Count(details,"cached_tokens")) : 0;
        var searches = json.TryGetProperty("output", out var items) && items.ValueKind == JsonValueKind.Array
            ? items.EnumerateArray().Count(item => item.ValueKind == JsonValueKind.Object && item.TryGetProperty("type", out var t) &&
                t.ValueKind == JsonValueKind.String && t.GetString() == "web_search_call") : 0;
        // Standard USD per million tokens. Store the estimate with the event.
        (double input, double cached, double output)? rates = model switch {
            var m when m == "gpt-5-mini" || m.StartsWith("gpt-5-mini-", StringComparison.Ordinal) => (.25,.025,2),
            var m when m == "gpt-4o-mini" || System.Text.RegularExpressions.Regex.IsMatch(m,@"^gpt-4o-mini-\d{4}-\d{2}-\d{2}$") => (.15,.075,.60),
            var m when m == "gpt-4.1-mini" || m.StartsWith("gpt-4.1-mini-", StringComparison.Ordinal) => (.40,.10,1.60),
            _ => null
        };
        var estimate = rates is {} r ? ((input-cached)*r.input + cached*r.cached + output*r.output)/1_000_000 + searches*.01 : (double?)null;
        record(new(model,input,cached,output,searches,estimate));
    }
}
