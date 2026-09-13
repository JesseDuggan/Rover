using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Rover.Application.Accounts;
using Rover.Application.Adaptations;
using Rover.Application.Beta;
using Rover.Application.Conversation;
using Rover.Application.Commerce;
using Rover.Application.LocationIntelligence;
using Rover.Application.LiveContext;
using Rover.Application.Journeys;
using Rover.Application.Performance;
using Rover.Application.Profiles;
using Rover.Application.Speech;
using Rover.Application.Walks;
using Rover.Infrastructure.Accounts;
using Rover.Infrastructure.Adaptations;
using Rover.Infrastructure.Beta;
using Rover.Infrastructure.Conversation;
using Rover.Infrastructure.Commerce;
using Rover.Infrastructure.Http;
using Rover.Infrastructure.LocationIntelligence;
using Rover.Infrastructure.Journeys;
using Rover.Infrastructure.LiveContext;
using Rover.Infrastructure.Performance;
using Rover.Infrastructure.Profiles;
using Rover.Infrastructure.Speech;
using Rover.Infrastructure.Storage;
using Rover.Infrastructure.Walks;

namespace Rover.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        var hotelRateOptions = new HotelRateOptions
        {
            Enabled = configuration.GetValue("Rover:Commerce:HotelRates:Enabled", false),
            Provider = configuration["Rover:Commerce:HotelRates:Provider"] ?? "None",
            DefaultCurrency = configuration["Rover:Commerce:HotelRates:DefaultCurrency"] ?? "CAD"
        };
        services.AddSingleton(hotelRateOptions);
        services.AddSingleton<UnavailableHotelRateProvider>();
        services.AddSingleton<IHotelRateProvider>(provider =>
        {
            var options = provider.GetRequiredService<HotelRateOptions>();
            if (options.Enabled && !options.Provider.Equals("None", StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException($"Hotel-rate provider '{options.Provider}' is enabled but no adapter is registered.");
            }

            return provider.GetRequiredService<UnavailableHotelRateProvider>();
        });

        services.Configure<MapboxRoutingOptions>(options =>
        {
            configuration.GetSection("Rover:Routing:Mapbox").Bind(options);
            options.AccessToken ??= Environment.GetEnvironmentVariable("MAPBOX_DIRECTIONS_TOKEN")
                ?? Environment.GetEnvironmentVariable("MAPBOX_PUBLIC_TOKEN");
        });
        services.Configure<GoogleRoutesOptions>(options =>
        {
            configuration.GetSection("Rover:Routing:Google").Bind(options);
            options.ApiKey ??= Environment.GetEnvironmentVariable("GOOGLE_ROUTES_API_KEY")
                ?? Environment.GetEnvironmentVariable("GOOGLE_PLACES_API_KEY")
                ?? Environment.GetEnvironmentVariable("GOOGLE_MAPS_API_KEY");
        });
        services.Configure<LocalDiscoveryOptions>(options =>
        {
            configuration.GetSection("Rover:LocalDiscovery:Mapbox").Bind(options);
            options.Enabled = configuration.GetValue("Rover:LocalDiscovery:Enabled", options.Enabled)
                || IsLiveDiscoveryMode(Environment.GetEnvironmentVariable("ROVER_LOCAL_DISCOVERY_MODE") ?? configuration["Rover:LocalDiscovery:Mode"]);
            options.AccessToken ??= Environment.GetEnvironmentVariable("MAPBOX_SEARCH_TOKEN")
                ?? Environment.GetEnvironmentVariable("MAPBOX_DIRECTIONS_TOKEN")
                ?? Environment.GetEnvironmentVariable("MAPBOX_PUBLIC_TOKEN");
        });
        var speechOptions = new ElevenLabsSpeechOptions
        {
            Enabled = configuration.GetValue("ElevenLabs:Enabled", false),
            ApiKey = Environment.GetEnvironmentVariable("ElevenLabs__ApiKey") ?? configuration["ElevenLabs:ApiKey"],
            VoiceId = Environment.GetEnvironmentVariable("ElevenLabs__VoiceId") ?? configuration["ElevenLabs:VoiceId"],
            ModelId = Environment.GetEnvironmentVariable("ElevenLabs__ModelId") ?? configuration["ElevenLabs:ModelId"],
            OutputFormat = Environment.GetEnvironmentVariable("ElevenLabs__OutputFormat") ?? configuration["ElevenLabs:OutputFormat"] ?? "mp3_44100_128",
            Stability = configuration.GetValue("ElevenLabs:Stability", 0.45d),
            Similarity = configuration.GetValue("ElevenLabs:Similarity", 0.75d),
            Style = configuration.GetValue("ElevenLabs:Style", 0d),
            SpeakerBoost = configuration.GetValue("ElevenLabs:SpeakerBoost", true),
            RequestTimeoutSeconds = configuration.GetValue("ElevenLabs:RequestTimeoutSeconds", 20),
            MaximumCharactersPerRequest = configuration.GetValue("ElevenLabs:MaximumCharactersPerRequest", 1800),
            DailyCharacterLimitPerUser = configuration.GetValue("ElevenLabs:DailyCharacterLimitPerUser", 12000),
            MonthlyCharacterLimit = configuration.GetValue("ElevenLabs:MonthlyCharacterLimit", 250000),
            CacheEnabled = configuration.GetValue("ElevenLabs:CacheEnabled", true),
            FallbackEnabled = configuration.GetValue("ElevenLabs:FallbackEnabled", true),
            CacheDirectory = configuration["ElevenLabs:CacheDirectory"] ?? "work/generated-audio-cache",
            CacheRetentionHours = int.TryParse(Environment.GetEnvironmentVariable("ROVER_AUDIO_CACHE_RETENTION_HOURS"), out var audioCacheHours)
                ? Math.Clamp(audioCacheHours, 1, 720)
                : configuration.GetValue("ElevenLabs:CacheRetentionHours", 168)
        };
        services.AddSingleton(speechOptions);
        services.AddTransient<TransientRetryHandler>();
        services.AddHttpClient("ElevenLabs")
            .AddHttpMessageHandler<TransientRetryHandler>();
        services.AddSingleton(new OpenAIRoverConversationOptions
        {
            ApiKey = Environment.GetEnvironmentVariable("OPENAI_API_KEY"),
            OrganizationId = Environment.GetEnvironmentVariable("OPENAI_ORGANIZATION"),
            ProjectId = Environment.GetEnvironmentVariable("OPENAI_PROJECT"),
            Model = Environment.GetEnvironmentVariable("OPENAI_MODEL") ?? configuration["Rover:Conversation:OpenAI:Model"],
            TimeoutSeconds = configuration.GetValue("Rover:Conversation:OpenAI:TimeoutSeconds", 20),
            WebSearchEnabled = bool.TryParse(Environment.GetEnvironmentVariable("OPENAI_WEB_SEARCH_ENABLED"), out var webSearchEnabled)
                ? webSearchEnabled
                : configuration.GetValue("Rover:Conversation:OpenAI:WebSearchEnabled", false)
        });
        var locationOptions = new LocationIntelligenceOptions
        {
            Enabled = configuration.GetValue("Rover:LocationIntelligence:Enabled", true),
            DefaultRadiusMeters = configuration.GetValue("Rover:LocationIntelligence:DefaultRadiusMeters", 1500),
            MaxRadiusMeters = configuration.GetValue("Rover:LocationIntelligence:MaxRadiusMeters", 5000),
            MaximumReturnedPlaces = configuration.GetValue("Rover:LocationIntelligence:MaximumReturnedPlaces", 12),
            OpenAISynthesisEnabled = bool.TryParse(Environment.GetEnvironmentVariable("ROVER_LOCATION_STORY_OPENAI_ENABLED"), out var storyOpenAIEnabled)
                ? storyOpenAIEnabled
                : configuration.GetValue("Rover:LocationIntelligence:OpenAISynthesisEnabled", false),
            HistoricalCacheMinutes = configuration.GetValue("Rover:LocationIntelligence:HistoricalCacheMinutes", 10080),
            PoiCacheMinutes = configuration.GetValue("Rover:LocationIntelligence:PoiCacheMinutes", 240),
            WeatherCacheMinutes = configuration.GetValue("Rover:LocationIntelligence:WeatherCacheMinutes", 20),
            GeneratedStoryCacheMinutes = configuration.GetValue("Rover:LocationIntelligence:GeneratedStoryCacheMinutes", 10080),
            EvidenceFreshnessMinutes = configuration.GetValue("Rover:LocationIntelligence:EvidenceFreshnessMinutes", 10080),
            SpatialEvidenceFreshnessMinutes = configuration.GetValue("Rover:LocationIntelligence:SpatialEvidenceFreshnessMinutes", 5),
            PersistentStorageEnabled = bool.TryParse(Environment.GetEnvironmentVariable("ROVER_LOCATION_STORAGE_ENABLED"), out var persistentStorageEnabled)
                ? persistentStorageEnabled
                : configuration.GetValue("Rover:LocationIntelligence:PersistentStorageEnabled", true),
            PersistentStorageDirectory = Environment.GetEnvironmentVariable("ROVER_LOCATION_STORAGE_DIRECTORY")
                ?? configuration["Rover:LocationIntelligence:PersistentStorageDirectory"]
                ?? "work/location-intelligence",
            MaximumStoredStoryPacks = configuration.GetValue("Rover:LocationIntelligence:MaximumStoredStoryPacks", 500),
            MaximumStoredEvidenceSets = configuration.GetValue("Rover:LocationIntelligence:MaximumStoredEvidenceSets", 1000),
            ProviderTimeoutSeconds = configuration.GetValue("Rover:LocationIntelligence:ProviderTimeoutSeconds", 8),
            MergeDistanceMeters = configuration.GetValue("Rover:LocationIntelligence:MergeDistanceMeters", 35d),
            RouteNearDistanceMeters = configuration.GetValue("Rover:LocationIntelligence:RouteNearDistanceMeters", 120d),
            UserAgent = configuration["Rover:LocationIntelligence:UserAgent"] ?? "RoverLocationIntelligence/1.0 (local development)"
        };
        services.AddSingleton(locationOptions);
        services.RemoveAll<Phase15Options>();
        var phase15Options = new Phase15Options
        {
            Enabled = EnvironmentFlag("ROVER_PHASE15_ENABLED", configuration.GetValue("Rover:Phase15:Enabled", false)),
            CorridorEnabled = EnvironmentFlag("ROVER_PHASE15_CORRIDOR_ENABLED", configuration.GetValue("Rover:Phase15:CorridorEnabled", false)),
            EvidencePrefetchEnabled = EnvironmentFlag("ROVER_PHASE15_EVIDENCE_PREFETCH_ENABLED", configuration.GetValue("Rover:Phase15:EvidencePrefetchEnabled", false)),
            StoryPackV2Enabled = EnvironmentFlag("ROVER_PHASE15_STORY_PACK_V2_ENABLED", configuration.GetValue("Rover:Phase15:StoryPackV2Enabled", false)),
            HistoricalRetrievalEnabled = EnvironmentFlag("ROVER_PHASE15_HISTORICAL_RETRIEVAL_ENABLED", configuration.GetValue("Rover:Phase15:HistoricalRetrievalEnabled", false)),
            LiveWeatherEnabled = EnvironmentFlag("ROVER_PHASE15_LIVE_WEATHER_ENABLED", configuration.GetValue("Rover:Phase15:LiveWeatherEnabled", false)),
            EventsEnabled = EnvironmentFlag("ROVER_PHASE15_EVENTS_ENABLED", configuration.GetValue("Rover:Phase15:EventsEnabled", false)),
            CurrentInfoEnabled = EnvironmentFlag("ROVER_PHASE15_CURRENT_INFO_ENABLED", configuration.GetValue("Rover:Phase15:CurrentInfoEnabled", false)),
            NarrativeArcEnabled = EnvironmentFlag("ROVER_PHASE15_NARRATIVE_ARC_ENABLED", configuration.GetValue("Rover:Phase15:NarrativeArcEnabled", false)),
            NarrativeSchedulerEnabled = EnvironmentFlag("ROVER_PHASE15_SCHEDULER_ENABLED", configuration.GetValue("Rover:Phase15:NarrativeSchedulerEnabled", false)),
            InteractionMemoryEnabled = EnvironmentFlag("ROVER_PHASE15_INTERACTION_MEMORY_ENABLED", configuration.GetValue("Rover:Phase15:InteractionMemoryEnabled", false)),
            TargetSegmentSeconds = configuration.GetValue("Rover:Phase15:TargetSegmentSeconds", 180),
            MinimumSegmentMeters = configuration.GetValue("Rover:Phase15:MinimumSegmentMeters", 80),
            MaximumSegmentMeters = configuration.GetValue("Rover:Phase15:MaximumSegmentMeters", 350),
            CorridorRadiusMeters = configuration.GetValue("Rover:Phase15:CorridorRadiusMeters", 175),
            MinimumNavigationGapSeconds = configuration.GetValue("Rover:Phase15:MinimumNavigationGapSeconds", 30),
            PrefetchSegmentCount = configuration.GetValue("Rover:Phase15:PrefetchSegmentCount", 3),
            PrefetchQueueCapacity = configuration.GetValue("Rover:Phase15:PrefetchQueueCapacity", 24),
            UrgentManeuverWindowSeconds = configuration.GetValue("Rover:Phase15:UrgentManeuverWindowSeconds", 35),
            StoryNavigationBufferSeconds = configuration.GetValue("Rover:Phase15:StoryNavigationBufferSeconds", 12),
            InteractionRetentionDays = configuration.GetValue("Rover:Phase15:InteractionRetentionDays", 90),
            MaximumInteractionEventsPerProfile = configuration.GetValue("Rover:Phase15:MaximumInteractionEventsPerProfile", 200),
            CompletedStoryWeight = configuration.GetValue("Rover:Phase15:Scoring:CompletedWeight", 1),
            SkippedStoryWeight = configuration.GetValue("Rover:Phase15:Scoring:SkippedWeight", -2),
            ReplayedStoryWeight = configuration.GetValue("Rover:Phase15:Scoring:ReplayedWeight", 2),
            TellMoreStoryWeight = configuration.GetValue("Rover:Phase15:Scoring:TellMoreWeight", 3),
            DismissedStoryWeight = configuration.GetValue("Rover:Phase15:Scoring:DismissedWeight", -3)
        };
        services.AddSingleton(phase15Options);
        services.RemoveAll<Phase16Options>();
        services.AddSingleton(new Phase16Options
        {
            Enabled = EnvironmentFlag("ROVER_PHASE16_ENABLED", configuration.GetValue("Rover:Phase16:Enabled", false)),
            MaximumStoriesPerPack = configuration.GetValue("Rover:Phase16:MaximumStoriesPerPack", 9),
            StorySearchRadiusMeters = configuration.GetValue("Rover:Phase16:StorySearchRadiusMeters", 225),
            NavigationSafetyBufferSeconds = configuration.GetValue("Rover:Phase16:NavigationSafetyBufferSeconds", 15),
            PackRetentionHours = configuration.GetValue("Rover:Phase16:PackRetentionHours", 48),
            PromptVersion = configuration["Rover:Phase16:PromptVersion"] ?? "phase16-story-first-v3"
        });
        services.RemoveAll<IAdaptiveRouteStoryPackRepository>();
        services.AddSingleton<IAdaptiveRouteStoryPackRepository, FileAdaptiveRouteStoryPackRepository>();
        var googleWeatherOptions = new GoogleWeatherLiveOptions
        {
            Enabled = phase15Options.Enabled && phase15Options.LiveWeatherEnabled,
            ApiKey = Environment.GetEnvironmentVariable("GOOGLE_WEATHER_API_KEY")
                ?? Environment.GetEnvironmentVariable("GOOGLE_MAPS_SERVER_API_KEY"),
            TimeoutSeconds = configuration.GetValue("Rover:Phase15:LiveContext:Weather:TimeoutSeconds", 6),
            ForecastHours = configuration.GetValue("Rover:Phase15:LiveContext:Weather:ForecastHours", 6)
        };
        var ticketmasterOptions = new TicketmasterLiveOptions
        {
            Enabled = phase15Options.Enabled && phase15Options.EventsEnabled,
            ApiKey = Environment.GetEnvironmentVariable("TICKETMASTER_DISCOVERY_API_KEY"),
            TimeoutSeconds = configuration.GetValue("Rover:Phase15:LiveContext:Events:TimeoutSeconds", 6),
            RadiusKilometers = configuration.GetValue("Rover:Phase15:LiveContext:Events:RadiusKilometers", 25),
            MaximumResults = configuration.GetValue("Rover:Phase15:LiveContext:Events:MaximumResults", 10)
        };
        var currentInformationOptions = new OpenAICurrentInformationOptions
        {
            Enabled = phase15Options.Enabled && phase15Options.CurrentInfoEnabled,
            ApiKey = Environment.GetEnvironmentVariable("OPENAI_API_KEY"),
            Model = Environment.GetEnvironmentVariable("OPENAI_MODEL") ?? configuration["Rover:Conversation:OpenAI:Model"],
            TimeoutSeconds = configuration.GetValue("Rover:Phase15:LiveContext:CurrentInformation:TimeoutSeconds", 12),
            TrustedDomains = configuration.GetSection("Rover:Phase15:LiveContext:CurrentInformation:TrustedDomains").Get<string[]>() ?? Array.Empty<string>()
        };
        services.AddSingleton(googleWeatherOptions);
        services.AddSingleton(ticketmasterOptions);
        services.AddSingleton(currentInformationOptions);
        services.AddSingleton(new LocalRouteResearchOptions
        {
            Enabled = EnvironmentFlag("ROVER_PHASE16_ENABLED", configuration.GetValue("Rover:Phase16:Enabled", false))
                && EnvironmentFlag("ROVER_LOCAL_RESEARCH_ENABLED", false),
            ApiKey = Environment.GetEnvironmentVariable("OPENAI_API_KEY"),
            Model = Environment.GetEnvironmentVariable("ROVER_LOCAL_RESEARCH_MODEL") ?? currentInformationOptions.Model,
            TimeoutSeconds = configuration.GetValue("Rover:Phase16:LocalResearch:TimeoutSeconds", 60),
            SearchMaxOutputTokens = configuration.GetValue("Rover:Phase16:LocalResearch:SearchMaxOutputTokens", 8192),
            ClassificationMaxOutputTokens = configuration.GetValue("Rover:Phase16:LocalResearch:ClassificationMaxOutputTokens", 4096),
            CaptureRejectedResponses = EnvironmentFlag("ROVER_LOCAL_RESEARCH_CAPTURE_REJECTIONS", false)
        });
        services.AddHttpClient<ILocalRouteResearcher, OpenAILocalRouteResearcher>();
        services.AddHttpClient("MapboxDirections")
            .AddHttpMessageHandler<TransientRetryHandler>();
        services.AddHttpClient("GoogleRoutes")
            .AddHttpMessageHandler<TransientRetryHandler>();
        services.AddSingleton<GooglePlacesQuotaCooldown>();
        services.AddTransient<GooglePlacesQuotaHandler>();
        services.AddHttpClient("MapboxSearch")
            .AddHttpMessageHandler<TransientRetryHandler>();
        services.AddHttpClient("Wikipedia", client => client.DefaultRequestHeaders.UserAgent.ParseAdd(locationOptions.UserAgent))
            .AddHttpMessageHandler<TransientRetryHandler>();
        services.AddHttpClient("Wikidata", client => client.DefaultRequestHeaders.UserAgent.ParseAdd(locationOptions.UserAgent))
            .AddHttpMessageHandler<TransientRetryHandler>();
        services.AddHttpClient("ParksCanadaHeritage", client => client.DefaultRequestHeaders.UserAgent.ParseAdd(locationOptions.UserAgent))
            .AddHttpMessageHandler<TransientRetryHandler>();
        services.AddHttpClient("GooglePlaces", client => client.DefaultRequestHeaders.UserAgent.ParseAdd(locationOptions.UserAgent))
            .AddHttpMessageHandler<GooglePlacesQuotaHandler>();
        services.AddHttpClient("Overpass", client => client.DefaultRequestHeaders.UserAgent.ParseAdd(locationOptions.UserAgent))
            .AddHttpMessageHandler<TransientRetryHandler>();
        services.AddHttpClient("Weather", client => client.DefaultRequestHeaders.UserAgent.ParseAdd(locationOptions.UserAgent))
            .AddHttpMessageHandler<TransientRetryHandler>();
        services.AddHttpClient<OpenAIRoverConversationProvider>()
            .AddHttpMessageHandler<TransientRetryHandler>();
        services.AddHttpClient<OpenAILocationStorySynthesizer>()
            .AddHttpMessageHandler<TransientRetryHandler>();
        services.AddHttpClient<GoogleWeatherLiveProvider>()
            .AddHttpMessageHandler<TransientRetryHandler>();
        services.AddHttpClient<TicketmasterLiveEventProvider>()
            .AddHttpMessageHandler<TransientRetryHandler>();
        services.AddHttpClient<OpenAICurrentInformationProvider>()
            .AddHttpMessageHandler<TransientRetryHandler>();
        services.RemoveAll<ILiveWeatherProvider>();
        services.RemoveAll<ILiveEventProvider>();
        services.RemoveAll<ILiveCurrentInformationProvider>();
        services.AddScoped<ILiveWeatherProvider>(provider => googleWeatherOptions.Enabled
            ? provider.GetRequiredService<GoogleWeatherLiveProvider>()
            : provider.GetRequiredService<DisabledLiveWeatherProvider>());
        services.AddScoped<ILiveEventProvider>(provider => ticketmasterOptions.Enabled
            ? provider.GetRequiredService<TicketmasterLiveEventProvider>()
            : provider.GetRequiredService<DisabledLiveEventProvider>());
        services.AddScoped<ILiveCurrentInformationProvider>(provider => currentInformationOptions.Enabled
            ? provider.GetRequiredService<OpenAICurrentInformationProvider>()
            : provider.GetRequiredService<DisabledLiveCurrentInformationProvider>());
        services.AddSingleton<ILocationContextCache, InMemoryLocationContextCache>();
        services.AddSingleton<FileLocationIntelligenceRepository>();
        services.AddSingleton<IStoryPackRepository>(provider => provider.GetRequiredService<FileLocationIntelligenceRepository>());
        services.AddSingleton<IEvidenceRepository>(provider => provider.GetRequiredService<FileLocationIntelligenceRepository>());
        services.AddScoped<MapboxLocationContextProvider>(provider => new MapboxLocationContextProvider(
            provider.GetRequiredService<IHttpClientFactory>(),
            provider.GetRequiredService<ILocationContextCache>(),
            provider.GetRequiredService<TimeProvider>(),
            ProviderOptions(configuration, "Mapbox", locationOptions.PoiCacheMinutes, Environment.GetEnvironmentVariable("MAPBOX_SEARCH_TOKEN") ?? Environment.GetEnvironmentVariable("MAPBOX_PUBLIC_TOKEN"))));
        services.AddScoped<WikipediaLocationContextProvider>(provider => new WikipediaLocationContextProvider(
            provider.GetRequiredService<IHttpClientFactory>(),
            provider.GetRequiredService<ILocationContextCache>(),
            provider.GetRequiredService<TimeProvider>(),
            ProviderOptions(configuration, "Wikipedia", locationOptions.HistoricalCacheMinutes)));
        services.AddScoped<WikidataLocationContextProvider>(provider => new WikidataLocationContextProvider(
            provider.GetRequiredService<IHttpClientFactory>(),
            provider.GetRequiredService<ILocationContextCache>(),
            provider.GetRequiredService<TimeProvider>(),
            ProviderOptions(configuration, "Wikidata", locationOptions.HistoricalCacheMinutes)));
        services.AddScoped<ParksCanadaHeritageLocationContextProvider>(provider =>
        {
            var options = ProviderOptions(configuration, "ParksCanadaHeritage", locationOptions.HistoricalCacheMinutes);
            options.Enabled = options.Enabled && phase15Options.Enabled && phase15Options.HistoricalRetrievalEnabled;
            return new ParksCanadaHeritageLocationContextProvider(
                provider.GetRequiredService<IHttpClientFactory>(),
                provider.GetRequiredService<ILocationContextCache>(),
                provider.GetRequiredService<TimeProvider>(),
                options);
        });
        services.AddScoped<GooglePlacesLocationContextProvider>(provider => new GooglePlacesLocationContextProvider(
            provider.GetRequiredService<IHttpClientFactory>(),
            provider.GetRequiredService<ILocationContextCache>(),
            provider.GetRequiredService<TimeProvider>(),
            ProviderOptions(
                configuration,
                "GooglePlaces",
                0,
                Environment.GetEnvironmentVariable("GOOGLE_PLACES_API_KEY")
                    ?? Environment.GetEnvironmentVariable("GOOGLE_MAPS_API_KEY"))));
        services.AddScoped<OpenStreetMapLocationContextProvider>(provider => new OpenStreetMapLocationContextProvider(
            provider.GetRequiredService<IHttpClientFactory>(),
            provider.GetRequiredService<ILocationContextCache>(),
            provider.GetRequiredService<TimeProvider>(),
            ProviderOptions(configuration, "OpenStreetMap", locationOptions.HistoricalCacheMinutes)));
        services.AddScoped<WeatherLocationContextProvider>(provider => new WeatherLocationContextProvider(
            provider.GetRequiredService<IHttpClientFactory>(),
            provider.GetRequiredService<ILocationContextCache>(),
            provider.GetRequiredService<TimeProvider>(),
            ProviderOptions(configuration, "Weather", locationOptions.WeatherCacheMinutes, Environment.GetEnvironmentVariable("OPENWEATHER_API_KEY"))));
        services.AddScoped<ILocationContextProvider>(provider => provider.GetRequiredService<MapboxLocationContextProvider>());
        services.AddScoped<ICandidateObservationSearchProvider>(provider => provider.GetRequiredService<MapboxLocationContextProvider>());
        services.AddScoped<ICandidateObservationSearchProvider>(provider => provider.GetRequiredService<GooglePlacesLocationContextProvider>());
        services.AddScoped<ILocationContextProvider>(provider => provider.GetRequiredService<WikipediaLocationContextProvider>());
        services.AddScoped<ILocationContextProvider>(provider => provider.GetRequiredService<WikidataLocationContextProvider>());
        services.AddScoped<ILocationContextProvider>(provider => provider.GetRequiredService<ParksCanadaHeritageLocationContextProvider>());
        services.AddScoped<ILocationContextProvider>(provider => provider.GetRequiredService<GooglePlacesLocationContextProvider>());
        services.AddScoped<ILocationContextProvider>(provider => provider.GetRequiredService<OpenStreetMapLocationContextProvider>());
        services.AddScoped<ILocationContextProvider>(provider => provider.GetRequiredService<WeatherLocationContextProvider>());
        services.AddScoped<ILocationStorySynthesizer>(provider => locationOptions.OpenAISynthesisEnabled
            ? provider.GetRequiredService<OpenAILocationStorySynthesizer>()
            : provider.GetRequiredService<SafeFallbackLocationStorySynthesizer>());
        services.AddSingleton<IWalkSessionRepository, InMemoryWalkSessionRepository>();
        services.AddSingleton<InMemoryProfileRepository>();
        services.AddSingleton<PostgreSqlProfileRepository>();
        services.AddSingleton<IProfileRepository>(provider =>
        {
            var modeText = Environment.GetEnvironmentVariable("ROVER_STORAGE_MODE") ?? configuration["Rover:Storage:Mode"] ?? "InMemory";
            if (!Enum.TryParse(modeText, ignoreCase: true, out StorageMode mode))
            {
                throw new InvalidOperationException($"Unknown Rover storage mode '{modeText}'. Use InMemory or PostgreSql.");
            }

            return mode == StorageMode.PostgreSql
                ? provider.GetRequiredService<PostgreSqlProfileRepository>()
                : provider.GetRequiredService<InMemoryProfileRepository>();
        });
        services.AddSingleton<IWalkAdaptationRepository, InMemoryWalkAdaptationRepository>();
        services.AddSingleton<MockNearbyDiscoveryProvider>();
        services.AddScoped<MapboxNearbyDiscoveryProvider>();
        services.AddScoped<LocalNearbyDiscoveryProvider>();
        services.AddScoped<INearbyDiscoveryProvider>(provider =>
        {
            var modeText = Environment.GetEnvironmentVariable("ROVER_DISCOVERY_MODE") ?? configuration["Rover:Discovery:Mode"] ?? "Mock";
            var localDiscoveryModeText = Environment.GetEnvironmentVariable("ROVER_LOCAL_DISCOVERY_MODE") ?? configuration["Rover:LocalDiscovery:Mode"] ?? "None";
            if (IsLiveDiscoveryMode(localDiscoveryModeText))
            {
                return provider.GetRequiredService<LocalNearbyDiscoveryProvider>();
            }

            if (!Enum.TryParse(modeText, ignoreCase: true, out NearbyDiscoveryMode mode))
            {
                throw new InvalidOperationException($"Unknown Rover discovery mode '{modeText}'. Use Mock, Mapbox, or GooglePlaces.");
            }

            return mode is NearbyDiscoveryMode.Mapbox or NearbyDiscoveryMode.GooglePlaces
                ? provider.GetRequiredService<LocalNearbyDiscoveryProvider>()
                : provider.GetRequiredService<MockNearbyDiscoveryProvider>();
        });
        services.AddSingleton<IConversationMemory, InMemoryConversationMemory>();
        services.AddSingleton<IAccountRepository, InMemoryAccountRepository>();
        services.AddSingleton<QueuedWalkPrefetchService>();
        services.AddSingleton<IRoverWalkPrefetchService>(provider => provider.GetRequiredService<QueuedWalkPrefetchService>());
        services.AddHostedService(provider => provider.GetRequiredService<QueuedWalkPrefetchService>());
        services.AddSingleton<QueuedRouteStoryEvidencePrefetcher>();
        services.AddSingleton<IRouteStoryEvidencePrefetcher>(provider => provider.GetRequiredService<QueuedRouteStoryEvidencePrefetcher>());
        services.AddHostedService(provider => provider.GetRequiredService<QueuedRouteStoryEvidencePrefetcher>());
        services.AddSingleton<IBetaConfigurationService, BetaConfigurationService>();
        services.AddSingleton<IBetaDiagnosticsService, InMemoryBetaDiagnosticsService>();
        services.AddSingleton<IProblemReportService, InMemoryProblemReportService>();
        services.AddSingleton<IPostWalkFeedbackService, InMemoryPostWalkFeedbackService>();
        services.AddSingleton<ICrashReportingService, NoOpCrashReportingService>();
        services.AddSingleton<FileGeneratedAudioCache>();
        services.AddSingleton<IGeneratedAudioCache>(provider => provider.GetRequiredService<FileGeneratedAudioCache>());
        services.AddSingleton<ISpeechUsageService, InMemorySpeechUsageService>();
        services.AddScoped<ElevenLabsTextToSpeechProvider>();
        services.AddScoped<ITextToSpeechProvider>(provider =>
        {
            var options = provider.GetRequiredService<ElevenLabsSpeechOptions>();
            return options.Enabled
                ? provider.GetRequiredService<ElevenLabsTextToSpeechProvider>()
                : provider.GetRequiredService<DevelopmentFakeSpeechProvider>();
        });
        services.AddScoped<IWalkRouteProvider>(provider =>
        {
            var modeText = Environment.GetEnvironmentVariable("ROVER_ROUTING_MODE") ?? configuration["Rover:Routing:Mode"] ?? "Mock";
            if (!Enum.TryParse(modeText, ignoreCase: true, out RoutingMode mode))
            {
                mode = RoutingMode.Mock;
            }

            return mode switch
            {
                RoutingMode.Google => provider.GetRequiredService<GoogleRoutesWalkRouteProvider>(),
                _ => provider.GetRequiredService<MockWalkRouteProvider>()
            };
        });
        services.AddScoped<MockWalkRouteProvider>();
        services.AddScoped<GoogleRoutesWalkRouteProvider>();
        services.AddScoped<NoOpLocalDiscoveryProvider>();
        services.AddScoped<MapboxLocalDiscoveryProvider>();
        services.AddScoped<GooglePlacesLocalDiscoveryProvider>();
        services.AddScoped<ILocalDiscoveryProvider>(provider =>
        {
            var modeText = Environment.GetEnvironmentVariable("ROVER_LOCAL_DISCOVERY_MODE") ?? configuration["Rover:LocalDiscovery:Mode"] ?? "None";
            if (modeText.Equals("Mapbox", StringComparison.OrdinalIgnoreCase))
            {
                return provider.GetRequiredService<MapboxLocalDiscoveryProvider>();
            }

            if (modeText.Equals("GooglePlaces", StringComparison.OrdinalIgnoreCase))
            {
                return provider.GetRequiredService<GooglePlacesLocalDiscoveryProvider>();
            }

            return provider.GetRequiredService<NoOpLocalDiscoveryProvider>();
        });
        services.AddSingleton(new StoryLedPlanningOptions
        {
            Enabled = EnvironmentFlag("ROVER_STORY_LED_PLANNING_ENABLED", false)
                && string.Equals(Environment.GetEnvironmentVariable("ROVER_ROUTING_MODE") ?? configuration["Rover:Routing:Mode"], "Google", StringComparison.OrdinalIgnoreCase)
                && string.Equals(Environment.GetEnvironmentVariable("ROVER_LOCAL_DISCOVERY_MODE") ?? configuration["Rover:LocalDiscovery:Mode"], "GooglePlaces", StringComparison.OrdinalIgnoreCase),
            ApiKey = Environment.GetEnvironmentVariable("OPENAI_API_KEY"),
            Model = Environment.GetEnvironmentVariable("ROVER_STORY_LED_PLANNING_MODEL")
                ?? Environment.GetEnvironmentVariable("OPENAI_MODEL") ?? configuration["Rover:Conversation:OpenAI:Model"],
            TimeoutSeconds = configuration.GetValue("Rover:StoryLedPlanning:TimeoutSeconds", 12)
        });
        services.AddHttpClient<IStoryLedStopSelector, OpenAIStoryLedStopSelector>();
        services.AddScoped<IWalkPlanner, MockWalkPlanner>();
        services.AddScoped<MockRoverConversationProvider>();
        services.AddScoped<IRoverConversationProvider>(provider =>
        {
            var modeText = Environment.GetEnvironmentVariable("ROVER_CONVERSATION_MODE") ?? configuration["Rover:Conversation:Mode"] ?? "Mock";
            if (!Enum.TryParse(modeText, ignoreCase: true, out ConversationProviderMode mode))
            {
                mode = ConversationProviderMode.Mock;
            }

            return mode == ConversationProviderMode.OpenAI
                ? provider.GetRequiredService<OpenAIRoverConversationProvider>()
                : provider.GetRequiredService<MockRoverConversationProvider>();
        });

        return services;
    }

    private static LocationProviderOptions ProviderOptions(
        IConfiguration configuration,
        string providerName,
        int defaultCacheMinutes,
        string? environmentToken = null)
    {
        var section = configuration.GetSection($"Rover:LocationIntelligence:Providers:{providerName}");
        var enabledEnvironment = Environment.GetEnvironmentVariable($"ROVER_LOCATION_PROVIDER_{providerName.ToUpperInvariant()}_ENABLED");
        var configuredMode = Environment.GetEnvironmentVariable("ROVER_LOCAL_DISCOVERY_MODE")
            ?? configuration["Rover:LocalDiscovery:Mode"];
        var selectedForDiscovery = providerName.Equals("GooglePlaces", StringComparison.OrdinalIgnoreCase)
            && configuredMode?.Equals("GooglePlaces", StringComparison.OrdinalIgnoreCase) == true;
        return new LocationProviderOptions
        {
            Enabled = bool.TryParse(enabledEnvironment, out var enabled)
                ? enabled
                : section.GetValue("Enabled", false) || selectedForDiscovery,
            Endpoint = section["Endpoint"],
            AccessToken = environmentToken ?? section["AccessToken"],
            TimeoutSeconds = section.GetValue("TimeoutSeconds", configuration.GetValue("Rover:LocationIntelligence:ProviderTimeoutSeconds", 8)),
            CacheMinutes = section.GetValue("CacheMinutes", defaultCacheMinutes),
            MaximumResults = section.GetValue("MaximumResults", configuration.GetValue("Rover:LocationIntelligence:MaximumReturnedPlaces", 12))
        };
    }

    private static bool IsLiveDiscoveryMode(string? mode)
        => mode?.Equals("Mapbox", StringComparison.OrdinalIgnoreCase) == true
            || mode?.Equals("GooglePlaces", StringComparison.OrdinalIgnoreCase) == true;

    private static bool EnvironmentFlag(string name, bool fallback) =>
        bool.TryParse(Environment.GetEnvironmentVariable(name), out var enabled)
            ? enabled
            : fallback;
}
