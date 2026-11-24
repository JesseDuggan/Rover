using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Rover.Api.Usage;
using Rover.Application;
using Rover.Application.Journeys;
using Rover.Infrastructure;

// Explicit opt-in harness, never part of normal tests. Credentials arrive through environment,
// evidence and context through stdin. All output and research telemetry stay in a local directory.
internal static class JourneyReviewFixture
{
    public sealed record Input(string Directory, JourneyReviewRequest Request, UsageEvent[] Events);
    public static async Task Run()
    {
        var input=JsonSerializer.Deserialize<Input>(await Console.In.ReadToEndAsync(),new JsonSerializerOptions(JsonSerializerDefaults.Web))!;
        var config=new ConfigurationBuilder().AddEnvironmentVariables().AddInMemoryCollection(new Dictionary<string,string?> {
            ["Usage:Directory"]=input.Directory
        }).Build();
        var services=new ServiceCollection();services.AddLogging();services.AddSingleton<IConfiguration>(config);
        services.AddUsage();services.AddApplication();services.AddInfrastructure(config);services.AddScoped<JourneyReviewAgent>();
        await using var provider=services.BuildServiceProvider();
        var store=provider.GetRequiredService<UsageStore>();await store.StartAsync(default);
        try {
            foreach(var item in input.Events)store.Record(item);
            for(int i=0;i<200 && store.Rows("SELECT kind FROM events WHERE at >= $since",1,"").Count<input.Events.Length;i++)await Task.Delay(25);
            var report=await provider.GetRequiredService<JourneyReviewAgent>().RunAsync(input.Request,default);
            await File.WriteAllTextAsync(Path.Combine(input.Directory,"report.json"),JsonSerializer.Serialize(report,new JsonSerializerOptions{WriteIndented=true}));
            // Drain pending provider receipts before taking the cost snapshot.
        } finally {await store.StopAsync(default);}
        var usage=store.Rows("SELECT provider,purpose,outcome,ms,input,output,usd,trace FROM events WHERE at >= $since AND kind IN ('Model usage','Provider call')",1,"");
        await File.WriteAllTextAsync(Path.Combine(input.Directory,"research-usage.json"),JsonSerializer.Serialize(usage));
        Console.WriteLine("Review saved to "+input.Directory);
    }
}
