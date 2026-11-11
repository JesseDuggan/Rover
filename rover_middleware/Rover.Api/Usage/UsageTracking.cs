using System.Diagnostics;
using Rover.Application.Journeys;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Http;
using Rover.Infrastructure.Usage;

namespace Rover.Api.Usage;

public sealed class UsageScope(string action)
{
    public static readonly AsyncLocal<UsageScope?> Current = new();
    public string Action { get; set; } = action;
    public string Trace { get; } = Guid.NewGuid().ToString("N")[..16];
    public string Journey { get; private set; } = "";
    public void Link(string? id)
    {
        if (!string.IsNullOrWhiteSpace(id) && id.Length <= 128)
            Journey = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(id)))[..16].ToLowerInvariant();
    }
    public UsageEvent Event(string kind,string provider,string purpose,string outcome,long ms=0) =>
        new(kind,provider,purpose,outcome,Action,Trace,Journey,ms);
}

public sealed class UsageFilter(UsageStore store) : IHttpMessageHandlerBuilderFilter
{
    public Action<HttpMessageHandlerBuilder> Configure(Action<HttpMessageHandlerBuilder> next) => builder => {
        next(builder);
        builder.AdditionalHandlers.Add(new UsageHandler(store,builder.Name ?? "HTTP"));
    };
}

public sealed class UsageHandler(UsageStore store,string client) : DelegatingHandler
{
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken token)
    {
        var scope = UsageScope.Current.Value ?? new UsageScope("Background service");
        var provider = request.RequestUri?.Host switch {
            "api.openai.com" => "OpenAI", "places.googleapis.com" => "Google Places",
            "routes.googleapis.com" => "Google Routes", "api.elevenlabs.io" => "ElevenLabs",
            _ => client.Length is > 0 and < 100 ? client : "Other provider"
        };
        var purpose = request.Options.TryGetValue(new HttpRequestOptionsKey<string>("Walkabout.Usage.Purpose"),out var label) ? label : client;
        // Only code-defined client and operation labels enter storage. URLs can contain locations and keys.
        var watch = Stopwatch.StartNew();
        var outcome = "Transport error";
        if (provider == "OpenAI")
            request.Options.Set(ModelReceipt.Callback, receipt => store.Record(scope.Event("Model usage",provider,purpose,"Reported") with {
                Input=receipt.Input,Output=receipt.Output,Usd=receipt.EstimatedUsd,Model=receipt.Model,Units=receipt.Searches }));
        try {
            var response = await base.SendAsync(request,token);
            outcome = ((int)response.StatusCode).ToString();
            return response;
        } catch(OperationCanceledException) { outcome="Cancelled or timed out"; throw; }
        finally { store.Record(scope.Event("Provider call",provider,purpose,outcome,watch.ElapsedMilliseconds)); }
    }
}

public static class UsageTracking
{
    public static void AddUsage(this IServiceCollection services)
    {
        services.AddSingleton<UsageStore>();
        services.AddHostedService(sp => sp.GetRequiredService<UsageStore>());
        services.AddSingleton<IHttpMessageHandlerBuilderFilter,UsageFilter>();
    }
    public static void UseUsage(this WebApplication app)
    {
        var store=app.Services.GetRequiredService<UsageStore>();
        app.Use(async (http,next) => {
            var route=(http.GetEndpoint() as RouteEndpoint)?.RoutePattern.RawText;
            if (route == null || !route.StartsWith("/api/",StringComparison.OrdinalIgnoreCase)) { await next(); return; }
            var scope = new UsageScope(http.Request.Method+" "+route);
            scope.Link(http.Request.RouteValues["walkSessionId"]?.ToString());
            var previous=UsageScope.Current.Value;
            UsageScope.Current.Value=scope;
            var previousInspection = StoryInspection.Listener.Value;
            StoryInspection.Listener.Value = item => store.Record(InspectionDetails.Event(scope, item));
            var watch=Stopwatch.StartNew();
            var outcome="Failed";
            try { await next(); outcome=http.Response.StatusCode.ToString(); }
            finally {
                store.Record(scope.Event("API request","Walkabout",scope.Action,outcome,watch.ElapsedMilliseconds));
                UsageScope.Current.Value=previous;
                StoryInspection.Listener.Value=previousInspection;
            }
        });
    }
}
