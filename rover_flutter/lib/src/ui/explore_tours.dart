import 'package:flutter/material.dart';

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/rover_api_client.dart';
import '../memories/memories_screen.dart';
import '../memories/memory_store.dart';
import '../preferences/preferences_controller.dart';
import 'fremont_tour.dart';
import 'prepared_walk_screen.dart';
import 'tour_question.dart';
import 'tour_route_preview.dart';
import 'prepare_tour_stories.dart';
import 'tour_details.dart';

class CityTour {
  const CityTour(
    this.asset,
    this.name,
    this.description,
    this.estimate, {
    this.minimumAge = 0,
    this.savedNarration = false,
    this.cover,
  });
  final int minimumAge;
  final bool savedNarration;
  final String? cover;
  final String asset, name, description;
  final String estimate;
}

const vegasTours = [
  CityTour(
    'fremont',
    'Fremont Past to Present',
    'Follow the neon from the Plaza or El Cortez, with a detour to the Mob Museum.',
    '1.6–1.7 km · About 40–45 min',
  ),
  CityTour(
    'LV-02',
    'The Original Las Vegas Walking Tour',
    'Walk the old casino corridor from the railroad site to Container Park.',
    '0.9 km · About 25–30 min',
  ),
  CityTour(
    'LV-03',
    'Arts District & Brewery Row',
    'Explore a warehouse of artists, vintage storefronts and neighbourhood breweries.',
    '1.3 km · About 25–30 min',
  ),
  CityTour(
    'LV-04',
    'Best Bites on the Las Vegas Strip',
    'Walk from New York-New York to Bellagio, with chocolate, an Italian market and a chandelier along the way.',
    '1.5 km · About 30–35 min',
  ),
];

const afterDarkTour = CityTour(
  'LV-05',
  'Sin City Secrets: Las Vegas After Dark',
  'Draft preview · Eight historical chapters at four outdoor stops. Gambling, vanished brothels and the people behind the spectacle. 21+ only.',
  'Distance and time calculated in route preview',
  minimumAge: 21,
  savedNarration: true,
  cover: 'fremont',
);

class ExploreToursScreen extends StatefulWidget {
  const ExploreToursScreen({super.key});
  @override
  State<ExploreToursScreen> createState() => _ExploreToursState();
}

class _ExploreToursState extends State<ExploreToursScreen> {
  final api = RoverApiClient();
  bool opening = false;
  bool preparing = false;
  bool adultOptIn = false;
  @override
  void dispose() {
    api.close();
    super.dispose();
  }

  Future<void> open(CityTour tour) async {
    if (opening) return;
    if (tour.minimumAge > 0 && !adultOptIn) return;
    setState(() => opening = true);
    try {
      final prefs = PreferencesScope.of(context).preferences;
      var tourInterests = prefs.interests;
      final navigator = Navigator.of(context);
      final start = tour.asset == 'fremont'
          ? await showDialog<String>(
              context: context,
              builder: (dialog) => SimpleDialog(
                title: const Text('Where would you like to start?'),
                children: [
                  for (final name in ['Plaza', 'El Cortez'])
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(dialog, name),
                      child: Text(name),
                    ),
                ],
              ),
            )
          : 'Default';
      if (start == null || !mounted) return;
      final walk = await loadCityTour(
        asset: tour.asset,
        start: start,
        interests: prefs.interests,
        depth: prefs.contentDepth,
      );
      if (!mounted) return;
      if (tour.savedNarration) {
        final data = jsonDecode(
          await rootBundle.loadString('assets/tours/${tour.asset}.json'),
        ) as Map<String, dynamic>;
        if (!mounted) return;
        final proceed = await navigator.push<bool>(
          MaterialPageRoute(builder: (_) => TourDetailsScreen(data: data)),
        );
        if (proceed != true || !mounted) return;
      }
      Future<void> play(PreparedWalk walk) async {
        if (preparing) return;
        preparing = true;
        final progress = ValueNotifier<String>(
          'Preparing stories for your interests…',
        );
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          useRootNavigator: false,
          builder: (_) => PopScope(
            canPop: false,
            child: AlertDialog(
              title: const Text('Preparing your tour'),
              content: ValueListenableBuilder<String>(
                valueListenable: progress,
                builder: (_, text, child) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const LinearProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(text),
                  ],
                ),
              ),
            ),
          ),
        );
        try {
          if (!tour.savedNarration)
            walk = await prepareTourStories(
              api,
              walk,
              interests: tourInterests,
              depth: prefs.contentDepth,
              onProgress: (done, total) => progress.value =
                  'Checked $done of $total stops. Reviewed stories remain available if research cannot finish.',
            );
        } finally {
          if (navigator.mounted) navigator.pop();
          progress.dispose();
          preparing = false;
        }
        if (!mounted) return;
        final outing = tourMemoryJourney(tour, walk);
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => PreparedWalkScreen(
              walk: walk,
              research: (stop) =>
                  askTourQuestion(api, stop, 'What occupies this site today?'),
              followUp: (stop, question) =>
                  askTourQuestion(api, stop, question),
              onCapture: () => navigator.push(
                MaterialPageRoute<void>(
                  builder: (_) => MemoryCaptureScreen(
                    store: MemoryStore(),
                    journey: outing,
                  ),
                ),
              ),
              onMemories: () => navigator.push(
                MaterialPageRoute<void>(
                  builder: (_) => MemoriesScreen(journey: outing),
                ),
              ),
            ),
          ),
        );
      }

      if (tour.asset == 'fremont' || tour.savedNarration) {
        await navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => TourRoutePreview(
              initialWalk: walk,
              rehearsalStart: tour.savedNarration
                  ? walk.stops.first.point
                  : fremontRehearsalStart,
              researchApproach: !tour.savedNarration,
              api: api,
              pace: prefs.walkingPace,
              onUse: play,
              profileInterests: prefs.interests,
              loadWalk: (interests) {
                tourInterests = interests;
                return loadCityTour(
                  asset: tour.asset,
                  start: start,
                  interests: interests,
                  depth: prefs.contentDepth,
                );
              },
            ),
          ),
        );
      } else {
        await play(walk);
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open this tour. Tap it to try again.'),
          ),
        );
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  Future<void> showPhotoCredits() async {
    final credits = jsonDecode(
      await rootBundle.loadString('assets/tours/photo_credits.json'),
    ) as List;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tour photographs'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final photo in credits)
                ListTile(
                  title: Text(photo['title']),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(photo['author']),
                      TextButton(
                        onPressed: () => launchUrl(Uri.parse(photo['source'])),
                        child: const Text('Original photograph'),
                      ),
                      TextButton(
                        onPressed: () => launchUrl(Uri.parse(photo['licurl'])),
                        child: Text(photo['license']),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Explore Tours')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Text(
              'Las Vegas',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 18),
              child: Text('4 walking tours · Preview from anywhere'),
            ),
            for (final tour in [...vegasTours, if (adultOptIn) afterDarkTour])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: opening ? null : () => open(tour),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AspectRatio(
                          aspectRatio: 2.9,
                          child: Image.asset(
                            'assets/tours/${tour.cover ?? tour.asset}.jpg',
                            fit: BoxFit.cover,
                            excludeFromSemantics: true,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tour.name,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 5),
                              Text(
                                tour.estimate,
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 6),
                              Text(tour.description),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            SwitchListTile(
              title: const Text('Show adults-only tours (21+)'),
              subtitle: const Text(
                'Off by default. Keep off for family walks.',
              ),
              value: adultOptIn,
              onChanged: (value) async {
                if (!value) {
                  setState(() => adultOptIn = false);
                  return;
                }
                final accepted = await showDialog<bool>(
                  context: context,
                  builder: (dialog) => AlertDialog(
                    title: const Text('Adults-only history'),
                    content: const Text(
                      'These tours discuss gambling, prostitution and organized crime without explicit detail. Confirm that you and everyone listening are 21 or older. Optional indoor visits have separate admission rules. This is a draft for testing.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialog, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialog, true),
                        child: const Text('Everyone is 21+'),
                      ),
                    ],
                  ),
                );
                if (mounted && accepted == true)
                  setState(() => adultOptIn = true);
              },
            ),
            const Text(
              'Times include brief stops. Allow extra time for meals or indoor visits.',
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: showPhotoCredits,
                child: const Text('Photo credits'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

MemoryJourney tourMemoryJourney(CityTour tour, PreparedWalk walk) {
  return MemoryJourney(
    id: 'tour-${tour.asset}-${DateTime.now().microsecondsSinceEpoch}',
    route: preparedRoute(walk, summary: tour.description, id: tour.asset),
  );
}
