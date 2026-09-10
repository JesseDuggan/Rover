using Microsoft.Extensions.DependencyInjection;
using Rover.Application.Accounts;
using Rover.Application.Adaptations;
using Rover.Application.Conversation;
using Rover.Application.Commerce;
using Rover.Application.Journeys;
using Rover.Application.LocationIntelligence;
using Rover.Application.LiveContext;
using Rover.Application.Profiles;
using Rover.Application.Speech;
using Rover.Application.Walks;

namespace Rover.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        services.AddSingleton(TimeProvider.System);
        services.AddScoped<IWalkSessionService, WalkSessionService>();
        services.AddSingleton<IRouteQualityAnalyzer, DeterministicRouteQualityAnalyzer>();
        services.AddSingleton<IStopLifecycleConsistencyService, StopLifecycleConsistencyService>();
        services.AddSingleton<RoverPromptBuilder>();
        services.AddSingleton<RoverConversationOptions>();
        services.AddScoped<IAskRoverService, AskRoverService>();
        services.AddScoped<IHotelRateSearchService, HotelRateSearchService>();
        services.AddScoped<IJourneyNarrationOrchestrator, JourneyNarrationOrchestrator>();
        services.AddSingleton<INarrativeScheduler, DeterministicNarrativeScheduler>();
        services.AddSingleton<ILiveContextStore, InMemoryLiveContextStore>();
        services.AddSingleton<DisabledLiveWeatherProvider>();
        services.AddSingleton<DisabledLiveEventProvider>();
        services.AddSingleton<DisabledLiveCurrentInformationProvider>();
        services.AddSingleton<ILiveWeatherProvider>(provider => provider.GetRequiredService<DisabledLiveWeatherProvider>());
        services.AddSingleton<ILiveEventProvider>(provider => provider.GetRequiredService<DisabledLiveEventProvider>());
        services.AddSingleton<ILiveCurrentInformationProvider>(provider => provider.GetRequiredService<DisabledLiveCurrentInformationProvider>());
        services.AddScoped<ILiveJourneyContextService, LiveJourneyContextService>();
        services.AddSingleton(new Phase15Options());
        services.AddSingleton<IRouteDirectionClassifier, DeterministicRouteDirectionClassifier>();
        services.AddSingleton<IRouteStoryPlanner, DeterministicRouteStoryPlanner>();
        services.AddSingleton<IRouteStoryPlanRepository, InMemoryRouteStoryPlanRepository>();
        services.AddScoped<IRouteStoryPlanService, RouteStoryPlanService>();
        services.AddSingleton(new Phase16Options());
        services.AddSingleton<IStoryIntentClassifier, DeterministicStoryIntentClassifier>();
        services.AddSingleton<IAdaptiveStoryLengthSelector, DeterministicAdaptiveStoryLengthSelector>();
        services.AddSingleton<IAdaptiveRouteStoryPackRepository, InMemoryAdaptiveRouteStoryPackRepository>();
        services.AddScoped<IAdaptiveRouteStoryPackService, AdaptiveRouteStoryPackService>();
        services.AddSingleton<IJourneyNarrativeArcBuilder, DeterministicJourneyNarrativeArcBuilder>();
        services.AddSingleton<IJourneyNarrativeArcRepository, InMemoryJourneyNarrativeArcRepository>();
        services.AddSingleton<IJourneyNarrativeArcService, JourneyNarrativeArcService>();
        services.AddSingleton<ILocationPlaceResolver, DeterministicLocationPlaceResolver>();
        services.AddSingleton<ILocationStoryRankingService, DeterministicLocationStoryRankingService>();
        services.AddSingleton<IStoryPackFactory, DeterministicStoryPackFactory>();
        services.AddSingleton<IStoryGroundingValidator, StrictStoryGroundingValidator>();
        services.AddSingleton<IStoryPackPersistencePolicy, DefaultStoryPackPersistencePolicy>();
        services.AddSingleton<IStoryPackRepository, NullStoryPackRepository>();
        services.AddSingleton<IEvidenceRepository, NullEvidenceRepository>();
        services.AddSingleton<SafeFallbackLocationStorySynthesizer>();
        services.AddScoped<ILocationStoryContextService, LocationStoryContextService>();
        services.AddScoped<ICandidateObservationResolutionService, CandidateObservationResolutionService>();
        services.AddScoped<IWalkAdaptationService, WalkAdaptationService>();
        services.AddScoped<IProfileService, ProfileService>();
        services.AddScoped<IAccountService, AccountService>();
        services.AddSingleton<DevelopmentFakeSpeechProvider>();
        services.AddScoped<IRoverSpeechService, RoverSpeechService>();

        return services;
    }
}
