import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../adaptive_stories/adaptive_route_story_diagnostics.dart';
import '../api/problem_details.dart';
import '../api/rover_api_client.dart';
import '../api/rover_api_config.dart';
import '../preferences/preferences_controller.dart';
import 'rover_ai_models.dart';
import 'rover_offline_intelligence.dart';
import 'rover_on_device_ai_scope.dart';

class RoverAiDiagnosticsScreen extends StatefulWidget {
  const RoverAiDiagnosticsScreen({super.key});

  @override
  State<RoverAiDiagnosticsScreen> createState() =>
      _RoverAiDiagnosticsScreenState();
}

class _RoverAiDiagnosticsScreenState extends State<RoverAiDiagnosticsScreen> {
  Future<_RoverAiDiagnosticsData>? _load;
  TextEditingController? _apiUrlController;
  bool _isRefreshing = false;
  bool _isTestingApi = false;
  String? _apiConnectionMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _apiUrlController ??= TextEditingController(
      text: RoverApiConfig.fromEnvironment().normalizedBaseUrl,
    );
    _load ??= _loadDiagnostics();
  }

  @override
  void dispose() {
    _apiUrlController?.dispose();
    super.dispose();
  }

  Future<_RoverAiDiagnosticsData> _loadDiagnostics() async {
    final coordinator = RoverOnDeviceAiScope.of(context);
    final bridgeVersion = await coordinator.getBridgeVersionForDiagnostics();
    final capabilities = await coordinator.getCapabilitiesForDiagnostics();
    final apiConfig = RoverApiConfig.fromEnvironment();
    final apiClient = RoverApiClient(
      config: RoverApiConfig(
        baseUrl: apiConfig.normalizedBaseUrl,
        developmentUser: apiConfig.developmentUser,
        connectionTimeout: const Duration(seconds: 3),
        responseTimeout: const Duration(seconds: 5),
      ),
    );
    var apiHealth = 'unavailable';
    try {
      final health = await apiClient.getHealth();
      apiHealth = health['status']?.toString() ?? 'healthy';
    } on RoverApiException catch (error) {
      apiHealth = error.message;
    } finally {
      apiClient.close();
    }
    return _RoverAiDiagnosticsData(
      bridgeVersion: bridgeVersion,
      capabilities: capabilities,
      apiBaseUrl: apiConfig.normalizedBaseUrl,
      apiHealth: apiHealth,
      refreshedAt: DateTime.now(),
    );
  }

  Future<void> _refresh() async {
    if (_isRefreshing) {
      return;
    }
    final load = _loadDiagnostics();
    setState(() {
      _isRefreshing = true;
      _load = load;
    });
    try {
      await load;
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  String? _candidateApiUrl() {
    try {
      return RoverApiConfig.normalizeBaseUrl(_apiUrlController!.text);
    } on ArgumentError {
      setState(() {
        _apiConnectionMessage =
            'Enter a complete URL such as http://192.168.1.25:5080.';
      });
      return null;
    }
  }

  Future<void> _testApi() async {
    if (_isTestingApi) {
      return;
    }
    final candidate = _candidateApiUrl();
    if (candidate == null || !mounted) {
      return;
    }

    setState(() {
      _isTestingApi = true;
      _apiConnectionMessage = 'Checking $candidate...';
    });
    final client = RoverApiClient(
      config: RoverApiConfig(
        baseUrl: candidate,
        connectionTimeout: const Duration(seconds: 4),
        responseTimeout: const Duration(seconds: 6),
        allowDevelopmentOverride: false,
      ),
    );
    try {
      final health = await client.getHealth();
      if (mounted) {
        setState(() {
          _apiConnectionMessage =
              '$candidate: ${health['status']?.toString() ?? 'Healthy'}';
        });
      }
    } on RoverApiException catch (error) {
      if (mounted) {
        setState(() => _apiConnectionMessage = error.message);
      }
    } finally {
      client.close();
      if (mounted) {
        setState(() => _isTestingApi = false);
      }
    }
  }

  Future<void> _saveApi() async {
    final candidate = _candidateApiUrl();
    if (candidate == null || !mounted) {
      return;
    }

    final preferences = PreferencesScope.of(context);
    await preferences.save(
      preferences.preferences.copyWith(developmentApiBaseUrl: candidate),
    );
    RoverApiConfig.setDevelopmentOverride(candidate);
    _apiUrlController!.text = candidate;
    if (!mounted) {
      return;
    }
    setState(() => _apiConnectionMessage = 'Saved $candidate');
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final coordinator = RoverOnDeviceAiScope.of(context);
    final offlineIntelligence = RoverOfflineIntelligence.instance;
    final routeStories = AdaptiveRouteStoryDiagnostics.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('On-device AI'),
        actions: [
          IconButton(
            onPressed: _isRefreshing ? null : _refresh,
            tooltip: 'Refresh capabilities',
            icon: _isRefreshing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          coordinator,
          offlineIntelligence,
          routeStories,
        ]),
        builder: (context, _) => FutureBuilder<_RoverAiDiagnosticsData>(
          future: _load,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _DiagnosticsError(onRetry: _refresh);
            }

            final data = snapshot.data!;
            final capabilities = data.capabilities;
            final situation = coordinator.lastSituationSnapshot;
            final curation = coordinator.lastCurationDecision;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                TextField(
                  controller: _apiUrlController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Development API URL',
                    prefixIcon: Icon(Icons.lan_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _isTestingApi ? null : _testApi,
                      icon: _isTestingApi
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.health_and_safety_outlined),
                      label: const Text('Test connection'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _saveApi,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save API URL'),
                    ),
                  ],
                ),
                if (_apiConnectionMessage case final message?) ...[
                  const SizedBox(height: 8),
                  Text(message),
                ],
                const SizedBox(height: 16),
                _Section(
                  title: 'Bridge',
                  rows: [
                    _Row('Version', data.bridgeVersion ?? 'not reported'),
                    _Row('Platform', capabilities.platform),
                    _Row(
                      'Device',
                      '${capabilities.manufacturer} ${capabilities.model}',
                    ),
                    _Row(
                      'Android API',
                      capabilities.apiLevel?.toString() ?? 'not reported',
                    ),
                    _Row(
                      'Checked',
                      capabilities.checkedAtUtc.toLocal().toString(),
                    ),
                    _Row('Screen refreshed', data.refreshedAt.toString()),
                  ],
                ),
                const SizedBox(height: 16),
                _Section(
                  title: 'ROVER API',
                  rows: [
                    _Row('Base URL', data.apiBaseUrl),
                    _Row('Health', data.apiHealth),
                  ],
                ),
                const SizedBox(height: 16),
                _Section(
                  title: 'Capabilities',
                  rows: [
                    _capabilityRow('Prompt', capabilities.prompt),
                    _capabilityRow(
                      'Image description',
                      capabilities.imageDescription,
                    ),
                    _capabilityRow('OCR', capabilities.ocr),
                    _capabilityRow(
                      'Object detection',
                      capabilities.objectDetection,
                    ),
                    _capabilityRow(
                      'On-device speech',
                      capabilities.speechRecognition,
                    ),
                    _capabilityRow(
                      'Native model curation',
                      capabilities.localCuration,
                    ),
                    _capabilityRow(
                      'Offline intelligence',
                      capabilities.offlineIntelligence,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _Section(
                  title: 'Device state',
                  rows: [
                    _Row(
                      'Foreground eligible',
                      _yesNo(capabilities.foregroundEligible),
                    ),
                    _Row(
                      'Battery saver',
                      _yesNo(capabilities.batterySaverEnabled),
                    ),
                    _Row('Thermal', capabilities.thermalState.name),
                    _Row(
                      'Memory pressure',
                      _yesNo(capabilities.memoryPressure),
                    ),
                    _Row('Quota limited', _yesNo(capabilities.quotaLimited)),
                    if (capabilities.unavailabilityReason case final reason?)
                      _Row('Unavailable reason', reason),
                  ],
                ),
                const SizedBox(height: 16),
                _Section(
                  title: 'Scout and Curator',
                  rows: [
                    _Row(
                      'Deterministic curation',
                      _yesNo(coordinator.deterministicCurationEnabled),
                    ),
                    _Row(
                      'Autonomous speech',
                      coordinator.autonomousCurationSpeechEnabled
                          ? 'enabled'
                          : 'disabled',
                    ),
                    if (situation != null) ...[
                      _Row('Travel mode', situation.travelMode.name),
                      _Row('Route', situation.routeState.name),
                      _Row('Geofence', situation.geofenceState.name),
                      _Row('Attention', situation.attentionOpportunity.name),
                      _Row(
                        'Verified nearby',
                        situation.nearbyVerifiedPoiIds.length.toString(),
                      ),
                      _Row('Connectivity', situation.connectivityState.name),
                      _Row('Offline cache', situation.offlineCacheState.name),
                    ] else
                      const _Row('Situation', 'waiting for active ROAM state'),
                    if (curation != null) ...[
                      _Row('Curator result', curation.diagnosticCode),
                      _Row(
                        'Eligible stories',
                        curation.rankedCandidates.length.toString(),
                      ),
                      if (curation.suppressionReason case final reason?)
                        _Row('Suppressed', reason),
                      if (curation.selected case final selected?)
                        _Row('Top reasons', selected.reasons.join(', ')),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                _Section(
                  title: 'Offline stories',
                  rows: [
                    _Row(
                      'Enabled',
                      _yesNo(offlineIntelligence.snapshot.enabled),
                    ),
                    _Row(
                      'Connectivity',
                      offlineIntelligence.connectivityState.name,
                    ),
                    _Row('Cache', offlineIntelligence.cacheState.name),
                    _Row(
                      'Story Packs',
                      offlineIntelligence.snapshot.entryCount.toString(),
                    ),
                    _Row(
                      'Storage',
                      _byteLabel(offlineIntelligence.snapshot.sizeBytes),
                    ),
                    _Row(
                      'Journey preload',
                      offlineIntelligence.snapshot.isPreloading
                          ? 'in progress'
                          : 'idle',
                    ),
                    if (offlineIntelligence.snapshot.lastUpdatedUtc
                        case final updated?)
                      _Row('Last cached', updated.toLocal().toString()),
                  ],
                ),
                const SizedBox(height: 16),
                _Section(
                  title: 'Adaptive route stories',
                  rows: [
                    _Row('Pack status', routeStories.status),
                    _Row('Stories', routeStories.storyCount.toString()),
                    _Row('Heard', routeStories.heardCount.toString()),
                    _Row('Saved', routeStories.savedCount.toString()),
                    _Row(
                      'Offline eligibility',
                      routeStories.offlineEligible
                          ? 'eligible for device cache'
                          : 'online sources or not eligible',
                    ),
                    _Row(
                      'Device cache',
                      routeStories.deviceCached ? 'available' : 'unavailable',
                    ),
                    _Row(
                      'Playback source',
                      routeStories.usingOfflinePack ? 'device cache' : 'API',
                    ),
                    _Row(
                      'Queued events',
                      routeStories.queuedEventCount.toString(),
                    ),
                    if (routeStories.updatedUtc case final updated?)
                      _Row('Last updated', updated.toLocal().toString()),
                    if (routeStories.error case final error?)
                      _Row('Last error', error),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: offlineIntelligence.snapshot.entryCount == 0
                        ? null
                        : () async {
                            await offlineIntelligence.clear();
                            if (mounted) {
                              setState(() {});
                            }
                          },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Clear offline stories'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

_Row _capabilityRow(String label, RoverAiFeatureCapability capability) {
  final details = <String>[
    capability.availability.name,
    ?capability.provider,
    ?capability.modelName,
    ?capability.modelVersion,
    ?capability.reason,
  ];
  return _Row(label, details.join(' - '));
}

String _yesNo(bool value) => value ? 'yes' : 'no';

String _byteLabel(int bytes) {
  if (bytes < 1024) {
    return '$bytes bytes';
  }
  return '${(bytes / 1024).toStringAsFixed(1)} KB';
}

class _RoverAiDiagnosticsData {
  const _RoverAiDiagnosticsData({
    required this.bridgeVersion,
    required this.capabilities,
    required this.apiBaseUrl,
    required this.apiHealth,
    required this.refreshedAt,
  });

  final String? bridgeVersion;
  final RoverAiCapabilitySnapshot capabilities;
  final String apiBaseUrl;
  final String apiHealth;
  final DateTime refreshedAt;
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});

  final String title;
  final List<_Row> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(children: rows),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _DiagnosticsError extends StatelessWidget {
  const _DiagnosticsError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            const Text('Capability snapshot unavailable.'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
