import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../active_roam/active_roam_controller.dart';
import '../active_roam/active_roam_session.dart';
import '../ui/placeholder_screens.dart';
import '../ui/walk_about_theme.dart';

class RoverShell extends StatelessWidget {
  const RoverShell({required this.navigationShell, super.key});
  final StatefulNavigationShell navigationShell;

  static const destinations = [
    RoverDestination(label: 'Walk', icon: Icons.map_outlined),
    RoverDestination(label: 'Plan', icon: Icons.format_list_numbered),
    RoverDestination(label: 'Stories', icon: Icons.headphones_outlined),
    RoverDestination(label: 'Routes', icon: Icons.route_outlined),
    RoverDestination(label: 'Profile', icon: Icons.person_outline),
  ];

  @override
  Widget build(BuildContext context) {
    final active = ActiveRoamScope.of(context);
    final session = active.session;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        automaticallyImplyLeading: false,
        title: const WalkaboutBrand(),
        actions: [
          IconButton(
            tooltip: 'Memories',
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: () => context.push('/memories'),
          ),
          IconButton(
            tooltip: 'Friends',
            icon: const Icon(Icons.people_outline),
            onPressed: () => context.push('/friends'),
          ),
          PopupMenuButton<String>(
            tooltip: 'Walk menu',
            icon: const Icon(Icons.more_horiz),
            enabled: !active.isBusy,
            onSelected: (value) async {
              if (value == 'create') {
                context.go('/home/create');
              } else if (value == 'pause') {
                final journey = WalkaboutJourneyScope.of(context);
                await journey.stories.pauseCurrent(session, journey.voice);
                await journey.voice.pauseNarration();
                await active.pause();
              } else if (value == 'resume') {
                await active.resume();
              } else if (value == 'end') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('End this walk?'),
                    content: const Text('Navigation and narration will stop.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Keep walking'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('End walk'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true || !context.mounted) return;
                await active.cancelApiWalk();
                if (!context.mounted) return;
                if (active.session.status == RoamSessionStatus.ended) {
                  await WalkaboutJourneyScope.of(context).voice.stopAll();
                  if (context.mounted) context.go('/home');
                }
              } else if (value == 'complete') {
                await active.completeApiWalk();
              } else if (value == 'just') {
                context.push('/just-walking');
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'create',
                child: Text('Create a walk'),
              ),
              if (session.status == RoamSessionStatus.active)
                const PopupMenuItem(value: 'pause', child: Text('Pause walk')),
              if (session.status == RoamSessionStatus.paused)
                const PopupMenuItem(
                  value: 'resume',
                  child: Text('Resume walk'),
                ),
              if (session.status == RoamSessionStatus.active ||
                  session.status == RoamSessionStatus.paused)
                const PopupMenuItem(value: 'end', child: Text('End walk')),
              if (session.status == RoamSessionStatus.active &&
                  session.completedStopIds.length >= session.roam.stops.length)
                const PopupMenuItem(
                  value: 'complete',
                  child: Text('Complete walk'),
                ),
              const PopupMenuItem(value: 'just', child: Text('Just walking')),
            ],
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: navigationShell,
      bottomNavigationBar: Material(
        color: Colors.white,
        child: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
              final width = math.max(
                constraints.maxWidth / destinations.length,
                64 * scale,
              );
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < destinations.length; i++)
                      Semantics(
                        selected: i == navigationShell.currentIndex,
                        button: true,
                        child: SizedBox(
                          width: width,
                          child: InkWell(
                            onTap: () => navigationShell.goBranch(i),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 4,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 48,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: i == navigationShell.currentIndex
                                          ? const Color(0xFFE8F2FF)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(
                                      destinations[i].icon,
                                      size: 24,
                                      color: i == navigationShell.currentIndex
                                          ? WalkaboutColors.blue
                                          : WalkaboutColors.navy,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    destinations[i].label,
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: i == navigationShell.currentIndex
                                          ? WalkaboutColors.blue
                                          : WalkaboutColors.navy,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class RoverDestination {
  const RoverDestination({required this.label, required this.icon});
  final String label;
  final IconData icon;
}
