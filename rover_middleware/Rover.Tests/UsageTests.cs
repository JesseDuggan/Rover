using System.Net;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Rover.Api.Usage;
using Rover.Infrastructure.Usage;

internal static class UsageTests
{
    public static async Task TracksProviderAndPrice()
    {
        var dir=Path.Combine(Path.GetTempPath(),"walkabout-usage-"+Guid.NewGuid().ToString("N"));
        var config=new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?> { ["Usage:Directory"]=dir }).Build();
        using var store=new UsageStore(config,NullLogger<UsageStore>.Instance);
        await store.StartAsync(default);
        try {
            using var client=new HttpClient(new UsageHandler(store,"Classifier"){InnerHandler=new Stub()});
            using var request=new HttpRequestMessage(HttpMethod.Post,"https://api.openai.com/example?key=never-store-this");
            var scope=new UsageScope("Test route");
            UsageScope.Current.Value=scope;
            using var response=await client.SendAsync(request);
            using var receipt=JsonDocument.Parse("""{"model":"gpt-5-mini","usage":{"input_tokens":1000,"input_tokens_details":{"cached_tokens":100},"output_tokens":100},"output":[{"type":"web_search_call"}]}""");
            ModelReceipt.Report(request,receipt.RootElement);
            scope.Link("private-walk-id");
            store.Record(scope.Event("API request","Walkabout","Test route","200"));
            for(int i=0;i<100;i++) {
                await Task.Delay(25);
                var rows=store.Rows("SELECT kind,provider,purpose,journey,usd FROM events WHERE at>=$since AND journey=$journey ORDER BY rowid",1,scope.Journey);
                if(rows.Count!=3) continue;
                if(rows[0][0]!="Provider call" || rows[0][1]!="OpenAI" || rows[1][0]!="Model usage" ||
                   Math.Abs(double.Parse(rows[1][4],System.Globalization.CultureInfo.InvariantCulture)-.0104275)>.0000001 ||
                   rows.Any(r=>r.Any(c=>c.Contains("never-store") || c.Contains("private-walk")))) throw new Exception("Unexpected provider receipt or attribution");
                return;
            }
            throw new Exception("Usage timeline failed to persist or link to the walk");
        } finally {
            UsageScope.Current.Value=null;
            await store.StopAsync(default);
            Microsoft.Data.Sqlite.SqliteConnection.ClearAllPools();
            Directory.Delete(dir,true);
        }
    }

    private sealed class Stub : HttpMessageHandler {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken token) =>
            Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK));
    }
}
