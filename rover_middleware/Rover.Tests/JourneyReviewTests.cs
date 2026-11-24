using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Rover.Api.Usage;
using Rover.Application.Journeys;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.DependencyInjection;
using System.Net;
using System.Net.Http.Json;
using System.Text;
using Microsoft.Extensions.Logging;

internal static class JourneyReviewTests
{
    static JourneyReviewRequest Request() => new("0123456789abcdef","Perth","Ontario","Canada",["history"],"deep",[new("Museum",44.9,-76.25)]);
    public static Task Analysis()
    {
        var accepted=new ReviewObservation("id","Museum","Prepared","Eligible","",string.Join(" ",Enumerable.Repeat("The museum preserves a specific detail from the former workshop.",10)),["https://museum.example/history"],"deep");
        var rejected=accepted with { Outcome="Rejected",Narration="",Reason="identity mismatch" };
        if(JourneyReviewAgent.Analyze([accepted,rejected]).Count!=0)throw new Exception("Historical failure wrongly overrides latest success");
        if(JourneyReviewAgent.Analyze([accepted,accepted with {Story="",Narration="",Stage="Spoken edit"}]).Count!=0)
            throw new Exception("Legacy edit record was counted as a missing story despite a uniquely linked final draft");
        if(!JourneyReviewAgent.Analyze([rejected,accepted]).Any(x=>x.Code=="latest-attempt-failed"))throw new Exception("Later failure hidden by old draft");
        var weak=accepted with { Narration="Nestled in the heart of town, rich in history.",Sources=[] };
        if(JourneyReviewAgent.Analyze([weak]).Count!=3)throw new Exception("Expected source, length and editorial flags");
        if(!JourneyReviewAgent.Valid(Request()) || JourneyReviewAgent.Valid(Request() with { Places=[new("Museum",double.NaN,0)] }) ||
           JourneyReviewAgent.Valid(Request() with { Walk="' OR 1=1 --" }) || JourneyReviewAgent.Valid(Request() with { Places=[new("a",0,0),new("b",0,0),new("c",0,0)] }))
            throw new Exception("Review bounds failed");
        return Task.CompletedTask;
    }
    public static async Task BoundedResearch()
    {
        var folder=Path.Combine(Path.GetTempPath(),"walkabout-review-tests-"+Guid.NewGuid().ToString("N"));
        using var store=new UsageStore(new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?>{["Usage:Directory"]=folder}).Build(),NullLogger<UsageStore>.Instance);
        var fake=new Researcher();var agent=new JourneyReviewAgent(store,fake);
        await store.StartAsync(default);
        try {
            try {await agent.RunAsync(Request(),default);throw new Exception("Missing evidence accepted");}
            catch(InvalidOperationException) {}
            if(fake.Calls!=0)throw new Exception("Paid research without evidence");
            var original=new UsageEvent("Story inspection","Walkabout","Prepared","Eligible","test","1234567890abcdef",Request().Walk) {
                Details="{\"story\":\"m\",\"title\":\"Museum\",\"narration\":\"Rich in history.\",\"depth\":\"deep\",\"sources\":[]}" };
            store.Record(original);
            for(var i=0;i<100 && store.Rows("SELECT details FROM events WHERE at >= $since",1,"").Count==0;i++)await Task.Delay(25);
            var before=new UsageScope("caller");UsageScope.Current.Value=before;
            var report=await agent.RunAsync(Request() with {Places=[new("Museum",44.9,-76.25),new("Unknown",44.9,-76.25)]},default);
            if(fake.Calls!=1 || report.Proposals.Count!=2 || report.Proposals[1].Status!="Not researched" || UsageScope.Current.Value!=before)
                throw new Exception("Subject bounds or scope isolation failed");
            if(fake.Query!.Interests.Single()!="history" || fake.Query.ContentDepth!="deep" || fake.Query.MaximumStories!=1)
                throw new Exception("Profile or depth lost");
            fake.Failed=true;
            var failed=await agent.RunAsync(Request(),default);
            if(failed.Status!="Partial" || !failed.Findings.Any(x=>x.Code=="research-pipeline"&&x.Evidence.Contains("rejected for length")))
                throw new Exception("Research extraction failure lost its diagnostic evidence");
            if(store.Rows("SELECT details FROM events WHERE kind='Story inspection' AND journey=$journey AND at >= $since",1,Request().Walk).Single()[0]!=original.Details)
                throw new Exception("Original journey changed");
            using var cancel=new CancellationTokenSource();cancel.Cancel();
            try {await agent.RunAsync(Request(),cancel.Token);throw new Exception("Cancellation ignored");}catch(OperationCanceledException){}
        } finally {
            UsageScope.Current.Value=null;await store.StopAsync(default);Microsoft.Data.Sqlite.SqliteConnection.ClearAllPools();
            Directory.Delete(folder,true);
        }
    }
    sealed class Researcher : ILocalRouteResearcher
    {
        public int Calls;public LocalRouteResearchQuery? Query;public bool Failed;
        public Task<LocalRouteResearchResult> ResearchAsync(LocalRouteResearchQuery query,CancellationToken token)
        {token.ThrowIfCancellationRequested();Calls++;Query=query;
            if(Failed)StoryInspection.Record("Citation extraction","No usable passages","1 cited paragraph rejected for length");
            return Task.FromResult(new LocalRouteResearchResult([],null){Failed=Failed});}
    }
    public static async Task ProtectedPage()
    {
        var folder=Path.Combine(Path.GetTempPath(),"walkabout-review-page-"+Guid.NewGuid().ToString("N"));
        var builder=WebApplication.CreateBuilder();builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Logging.ClearProviders();
        var password=new string('x',32);
        builder.Configuration.AddInMemoryCollection(new Dictionary<string,string?>{["Usage:Directory"]=folder,["WALKABOUT_USAGE_PASSWORD"]=password});
        builder.Services.AddUsage();builder.Services.AddSingleton<ILocalRouteResearcher,Researcher>();builder.Services.AddScoped<JourneyReviewAgent>();
        await using var app=builder.Build();JourneyReviewPage.Map(app);await app.StartAsync();
        try {
            using var client=new HttpClient{BaseAddress=new Uri(app.Urls.Single())};
            if((await client.GetAsync("/admin/research-review")).StatusCode!=HttpStatusCode.Unauthorized)throw new Exception("Unprotected review page");
            client.DefaultRequestHeaders.Authorization=new("Basic",Convert.ToBase64String(Encoding.UTF8.GetBytes("admin:"+password)));
            if((await client.PostAsJsonAsync("/admin/research-review",Request())).StatusCode!=HttpStatusCode.Forbidden)throw new Exception("Missing CSRF header allowed");
            client.DefaultRequestHeaders.Add("X-Walkabout-Review","1");
            client.DefaultRequestHeaders.Add("Origin","https://foreign.example");
            if((await client.PostAsJsonAsync("/admin/research-review",Request())).StatusCode!=HttpStatusCode.Forbidden)throw new Exception("Foreign origin allowed");
            client.DefaultRequestHeaders.Remove("Origin");
            // HttpClient's streaming JSON uses chunked transfer. Use buffered content, like fetch.
            Task<HttpResponseMessage> Post() => client.PostAsync("/admin/research-review",new StringContent(System.Text.Json.JsonSerializer.Serialize(Request() with {Places=[]}),Encoding.UTF8,"application/json"));
            var store=app.Services.GetRequiredService<UsageStore>();
            store.Record(new("Story inspection","Walkabout","Prepared","Eligible","test","0123456789abcdef",Request().Walk){Details="{\"title\":\"<script>alert(1)</script>\",\"narration\":\"Rich in history\",\"sources\":[]}"});
            for(var i=0;i<100&&store.Rows("SELECT kind FROM events WHERE at >= $since",1,"").Count==0;i++)await Task.Delay(25);
            var first=await Post();first.EnsureSuccessStatusCode();var a=await first.Content.ReadFromJsonAsync<JourneyReviewReport>();
            var second=await Post();second.EnsureSuccessStatusCode();var b=await second.Content.ReadFromJsonAsync<JourneyReviewReport>();
            if(a!.Id!=b!.Id)throw new Exception("Identical review was not reused");
            var html=await client.GetStringAsync("/admin/research-review?id="+a.Id);
            if(html.Contains("<script>alert(1)</script>") || !html.Contains("&lt;script&gt;"))throw new Exception("Report did not escape untrusted titles");
        } finally {await app.StopAsync();Microsoft.Data.Sqlite.SqliteConnection.ClearAllPools();Directory.Delete(folder,true);}
    }
}
