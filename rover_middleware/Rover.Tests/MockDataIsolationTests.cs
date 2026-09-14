using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Rover.Application;
using Rover.Application.Adaptations;
using Rover.Application.Conversation;
using Rover.Application.Speech;
using Rover.Application.Walks;
using Rover.Infrastructure;

internal static class MockDataIsolationTests
{
    public static Task ProductionNeverEnablesFixtures()
    {
        var keys = new[] { "ROVER_LOCAL_DISCOVERY_MODE", "ROVER_ROUTING_MODE", "ROVER_DISCOVERY_MODE", "ROVER_CONVERSATION_MODE" };
        var previous = keys.ToDictionary(key => key, Environment.GetEnvironmentVariable);
        try
        {
            foreach (var key in keys) Environment.SetEnvironmentVariable(key, null);
            foreach (var environment in new[] { "Production", "Development" })
            {
                var configuration = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["Rover:Testing:AllowMockData"] = environment == "Production" ? "true" : "false",
                    ["Rover:LocalDiscovery:Mode"] = "None",
                    ["Rover:Routing:Mode"] = "Mock",
                    ["Rover:Discovery:Mode"] = "Mock",
                    ["Rover:Conversation:Mode"] = "Mock"
                }).Build();
                var services = new ServiceCollection();
                services.AddLogging();
                services.AddSingleton<IHostEnvironment>(new TestHostEnvironment(environment));
                services.AddApplication();
                services.AddInfrastructure(configuration);
                using var provider = services.BuildServiceProvider();
                using var scope = provider.CreateScope();
                foreach (var contract in new[] { typeof(ILocalDiscoveryProvider), typeof(IWalkRouteProvider), typeof(INearbyDiscoveryProvider), typeof(IRoverConversationProvider) })
                {
                    try
                    {
                        scope.ServiceProvider.GetRequiredService(contract);
                    }
                    catch (InvalidOperationException exception) when (exception.Message.Contains("disabled", StringComparison.Ordinal))
                    {
                        continue;
                    }
                    throw new InvalidOperationException($"{environment} unexpectedly resolved a mock {contract.Name}.");
                }
                if (scope.ServiceProvider.GetRequiredService<ITextToSpeechProvider>() is DevelopmentFakeSpeechProvider)
                    throw new InvalidOperationException("Fake speech must not be selected.");
            }
        }
        finally
        {
            foreach (var entry in previous) Environment.SetEnvironmentVariable(entry.Key, entry.Value);
        }
        return Task.CompletedTask;
    }
}
