import 'package:latlong2/latlong.dart';

import 'prepared_walk_screen.dart';

// Street-level rehearsal points follow King Street from Spadina to Yonge.
const kingStreetTrail = PreparedWalk(
  'King Street: stage and screen',
  [
    LatLng(43.6454811, -79.3949138),
    LatLng(43.64649, -79.39035),
    LatLng(43.64675, -79.38923),
    LatLng(43.64707, -79.38755),
    LatLng(43.6491917, -79.3779089),
  ],
  [
    PreparedStop(
      'TIFF Lightbox',
      LatLng(43.64649, -79.39035),
      WalkAnswer(
        'Imagine choosing the first film an audience will see in a new cinema. Here at TIFF Lightbox, that film was Trigger. In September 2010, Bruce McDonald’s film brought two former rock bandmates back together on screen. Molly Parker and Tracy Wright played the musicians facing each other again after their band broke up.',
        {
          'TIFF festival programme':
              'https://www.tiff08.ca/filmsandschedules/tiff/2010/trigger/',
          'CityNews interview': 'https://toronto.citynews.ca/2010/09/30/trigger-rocks-the-lightbox/',
        },
      ),
    ),
    PreparedStop(
      'Princess of Wales Theatre',
      LatLng(43.64675, -79.38923),
      WalkAnswer(
        'What do you build when the show needs a stage of its own? Here at 300 King Street West, Ed and David Mirvish built a two-thousand-seat theatre. Its opening night, May 26, 1993, was the Canadian premiere of Miss Saigon. Look at the entrance and imagine those first ticket holders arriving for a show that would stay here for two years.',
        {
          'Mirvish theatre timeline': 'https://www.mirvish.com/learn/timelines/princess-of-wales-theatre-timeline',
          'Mirvish venue history': 'https://www.mirvish.com/visit/theatres/princess-of-wales-theatre',
        },
      ),
    ),
    PreparedStop(
      'Royal Alexandra Theatre',
      LatLng(43.64707, -79.38755),
      WalkAnswer(
        'Here is an older answer to the question of how to fill a stage. When the Royal Alexandra opened in 1907, touring companies brought their sets and performers here, played a short engagement, and packed up for the next city. Decades later, the Mirvish family built the Princess of Wales nearby as a sister theatre. Two stages a block apart tell you how much the business of putting on a show could change.',
        {
          'Mirvish cultural history': 'https://www.mirvish.com/the-canadian-cultural-heritage-of-the-royal-alexandra-theatre-and-mirvish-productions',
          'Mirvish theatre timeline': 'https://www.mirvish.com/learn/timelines/princess-of-wales-theatre-timeline',
        },
      ),
    ),
  ],
  theme: 'how audiences came to King Street for film and live theatre',
);
