using System.Net;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Rover.Api.Usage;
using Rover.Infrastructure.Usage;

internal static class UsageTests
{
    public static Task ClientJourneyLinkage()
    {
        const string id = "1234567890abcdef1234567890abcdef";
        var plan = new UsageScope("Plan"); plan.LinkClientJourney(id);
        var story = new UsageScope("Research"); story.LinkClientJourney(id);
        story.Link("server-session-id");
        if (plan.Journey.Length != 16 || plan.Journey != story.Journey || plan.Trace == story.Trace)
            throw new Exception("Journey must span requests and survive later session attribution");
        var other = new UsageScope("Other walk"); other.LinkClientJourney(Guid.NewGuid().ToString("N"));
        if (other.Journey == plan.Journey) throw new Exception("Separate journeys merged");
        foreach (var invalid in new[] { "", "Perth", new string('a', 129), id + "," + id }) {
            var scope = new UsageScope("Invalid header"); scope.LinkClientJourney(invalid);
            if (scope.Journey != "") throw new Exception("Invalid client identity accepted");
            scope.Link("legacy-walk");
            if (scope.Journey.Length != 16) throw new Exception("Legacy session linkage lost");
        }
        return Task.CompletedTask;
    }

    public static async Task InspectionMigration()
    {
        var dir=Path.Combine(Path.GetTempPath(),"walkabout-inspector-"+Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        var config=new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?> { ["Usage:Directory"]=dir }).Build();
        // A deployed usage database from before the inspector must migrate without losing its records.
        using(var old=new Microsoft.Data.Sqlite.SqliteConnection("Data Source="+Path.Combine(dir,"usage.db"))) {
            old.Open(); using var command=old.CreateCommand();
            command.CommandText="CREATE TABLE events(at INTEGER, kind TEXT, provider TEXT, purpose TEXT, outcome TEXT, action TEXT, trace TEXT, journey TEXT, ms INTEGER, input INTEGER, output INTEGER, usd REAL, model TEXT, units INTEGER); INSERT INTO events VALUES(unixepoch(),'legacy','','','','','','',0,0,0,NULL,'',0)";
            command.ExecuteNonQuery();
        }
        using var store=new UsageStore(config,NullLogger<UsageStore>.Instance);
        await store.StartAsync(default);
        try {
            var scope=new UsageScope("Inspector test");
            var evt=InspectionDetails.Event(scope,new Rover.Application.Journeys.StoryInspectionEvent(
                "Prepared story","Eligible","Supported public record","private-story-id","<script>title</script>",
                new string('a',7000),["https://museum.example/record?token=secret","http://127.0.0.1/","javascript:alert(1)"]));
            using var data=JsonDocument.Parse(evt.Details);
            if(evt.Details.Contains("secret")||evt.Details.Contains("private-story-id")||data.RootElement.GetProperty("sources").GetArrayLength()!=1||
                data.RootElement.GetProperty("narration").GetString()!.Length!=6000) throw new Exception("Inspection bounds or private fields were not protected");
            store.Record(evt); scope.Link("private-walk-id");store.Record(scope.Event("API request","Walkabout","Inspector test","200"));
            for(int i=0;i<100;i++) {
                await Task.Delay(25);
                var rows=store.Rows("SELECT details,journey FROM events WHERE kind='Story inspection' AND at>=$since",1,"");
                if(rows.Count!=1) continue;
                if(rows[0][1]!=scope.Journey||store.Rows("SELECT kind FROM events WHERE kind='legacy' AND at>=$since",1,"").Count!=1)
                    throw new Exception("Migration lost history or trace-to-walk linking");
                // Diagnostics failures must never interrupt narration/research.
                Rover.Application.Journeys.StoryInspection.Listener.Value=_=>throw new Exception("Unavailable telemetry");
                Rover.Application.Journeys.StoryInspection.Record("Test","Ready","Test");
                return;
            }
            throw new Exception("Inspection events did not persist");
        } finally {
            Rover.Application.Journeys.StoryInspection.Listener.Value=null;
            await store.StopAsync(default);Microsoft.Data.Sqlite.SqliteConnection.ClearAllPools();Directory.Delete(dir,true);
        }
    }

    public static async Task TracksProviderAndPrice()
    {
        using (var priceRequest = new HttpRequestMessage()) {
            ModelReceipt? captured = null;
            priceRequest.Options.Set(ModelReceipt.Callback, receipt => captured = receipt);
            using var editorReceipt = JsonDocument.Parse("""{"model":"gpt-5.4-2026-03-05","usage":{"input_tokens":1000,"input_tokens_details":{"cached_tokens":100},"output_tokens":100}}""");
            ModelReceipt.Report(priceRequest, editorReceipt.RootElement);
            if (captured?.EstimatedUsd is not double estimate || Math.Abs(estimate-.003775)>.0000001)
                throw new Exception("Spoken editor token estimate must include discounted cached input.");
        }

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
