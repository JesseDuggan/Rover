import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rover/src/api/adaptive_route_story_models.dart';
import 'package:rover/src/api/problem_details.dart';
import 'package:rover/src/api/rover_api_client.dart';
import 'package:rover/src/api/story_question_models.dart';
import 'package:rover/src/location/rover_location.dart';
import 'package:rover/src/story_questions/story_question_controller.dart';
import 'package:rover/src/story_questions/story_question_sheet.dart';

void main() {
  test('question payload uses current GPS and never needs a saved walk', () async {
    final client = _Client((_) async => _response('ready'));
    final controller = StoryQuestionController(
      currentContext: _context, createClient: () => client,
    );
    await controller.ask('What was here before?', scope: 'Neighbourhood', format: 'ThenAndNow');
    final json = client.request!.toJson();
    expect(json['latitude'], 51.5);
    expect(json['longitude'], -0.12);
    expect(json['format'], 'ThenAndNow');
    expect(json.containsKey('routeGeometry'), isFalse);
    expect(json.containsKey('walkSessionId'), isFalse);
    expect(json.containsKey('publicPlaceNames'), isFalse);
    expect(controller.response!.answers, hasLength(1));
    expect(client.closed, isTrue);
    controller.dispose();
  });

  test('cancelled and replaced requests cannot publish stale answers', () async {
    final pending = Completer<StoryQuestionResponse>();
    final first = _Client((_) => pending.future);
    final second = _Client((_) async => _response('empty'));
    var creates = 0;
    final controller = StoryQuestionController(
      currentContext: _context, createClient: () => creates++ == 0 ? first : second,
    );
    final operation = controller.ask('First question');
    await controller.ask('Duplicate tap');
    expect(creates, 1);
    controller.cancel();
    expect(first.closed, isTrue);
    await controller.ask('Second question');
    pending.complete(_response('ready'));
    await operation;
    expect(controller.response!.status, 'empty');
    expect(controller.busy, isFalse);
    controller.dispose();
  });

  test('stale GPS and route revisions prevent research or stale publication', () async {
    var context = _context();
    final pending = Completer<StoryQuestionResponse>();
    final client = _Client((_) => pending.future);
    final controller = StoryQuestionController(currentContext: () => context, createClient: () => client);
    final operation = controller.ask('Tell me the history');
    context = StoryQuestionContext(reading: context.reading, walkId: 'new-walk', routeRevision: 2);
    pending.complete(_response('ready'));
    await operation;
    expect(controller.response, isNull);
    expect(controller.message, contains('changed'));
    context = StoryQuestionContext(reading: RoverLocationReading(
      location: context.reading.location, recordedAtUtc: DateTime.utc(2000), accuracyMeters: 5,
    ));
    await controller.ask('Try old GPS');
    expect(controller.message, contains('accurate current location'));
    controller.dispose();
  });

  test('HTTP errors remain recoverable and are not shown as empty evidence', () async {
    for (final status in [404, 429, 401, 500]) {
      final controller = StoryQuestionController(currentContext: _context,
        createClient: () => _Client((_) async => throw RoverApiException('internal', statusCode: status)));
      await controller.ask('Tell me something');
      expect(controller.busy, isFalse);
      expect(controller.response, isNull);
      expect(controller.message, isNot(contains('internal')));
      expect(controller.message, isNot(contains('verified evidence')));
      controller.dispose();
    }
  });

  test('dispose closes in-flight research and ignores its completion', () async {
    final pending = Completer<StoryQuestionResponse>();
    final client = _Client((_) => pending.future);
    final controller = StoryQuestionController(currentContext: _context, createClient: () => client);
    final operation = controller.ask('Question');
    controller.dispose();
    expect(client.closed, isTrue);
    pending.complete(_response('ready'));
    await operation;
    expect(controller.response, isNull);
  });

  test('route geometry stays ordered and bounded with endpoints retained', () {
    final geometry = List.generate(400, (i) => RoverLatLng(latitude: 51.5 + i / 100000, longitude: -0.12));
    final context = StoryQuestionContext(reading: _context().reading, routeGeometry: geometry);
    final bounded = context.boundedGeometry;
    expect(bounded, hasLength(120));
    expect(bounded.first, same(geometry.first));
    expect(bounded.last, same(geometry.last));
    expect(bounded.map((p) => p.latitude), orderedEquals(
      bounded.map((p) => p.latitude).toList()..sort()));
  });

  for (final width in [320.0, 390.0]) {
    testWidgets('question sheet fits phone width $width and keeps playback explicit', (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pending = Completer<StoryQuestionResponse>();
      final client = _Client((_) => pending.future);
      final controller = StoryQuestionController(currentContext: _context, createClient: () => client);
      var played = 0;
      var stopped = 0;
      final playback = Completer<bool>();
      final boundary = GlobalKey();
      const capture = bool.fromEnvironment('CAPTURE_STORY_QUESTIONS');
      if (capture) {
        await tester.runAsync(() async {
          for (final entry in {
            'Roboto': 'C:/src/flutter/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
            'MaterialIcons': 'C:/src/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
          }.entries) {
            final loader = FontLoader(entry.key);
            loader.addFont(File(entry.value).readAsBytes().then(ByteData.sublistView));
            await loader.load();
          }
        });
      }
      await tester.pumpWidget(RepaintBoundary(key: boundary, child: MaterialApp(home: Scaffold(body:
        StoryQuestionSheet(title: 'Ask about this area', controller: controller,
          play: (_) { played++; return playback.future; },
          stop: () async { stopped++; },
        ),
      ))));
      await tester.enterText(find.byType(TextField), 'How has this neighbourhood changed?');
      await tester.ensureVisible(find.text('Ask'));
      await tester.tap(find.text('Ask'));
      await tester.pump();
      expect(find.text('Researching your question...'), findsOneWidget);
      expect(find.text('Cancel research'), findsOneWidget);
      pending.complete(_response('partial'));
      await tester.pumpAndSettle();
      expect(played, 0);
      expect(find.text('Some requested history could not be verified.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Play answer'));
      await tester.pumpAndSettle();
      if (capture) {
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('build/story_question_screenshots/answer-${width.toInt()}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.text('Play answer'));
      await tester.pump();
      expect(played, 1);
      expect(find.text('Stop answer'), findsOneWidget);
      await tester.tap(find.text('Stop answer'));
      await tester.pump();
      playback.complete(false);
      await tester.pumpAndSettle();
      expect(find.text('Playback stopped.'), findsOneWidget);
      expect(stopped, 1);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }
}

StoryQuestionContext _context() => StoryQuestionContext(reading: RoverLocationReading(
  location: const RoverLatLng(latitude: 51.5, longitude: -0.12),
  recordedAtUtc: DateTime.now().toUtc(), accuracyMeters: 5,
));

StoryQuestionResponse _response(String status) => StoryQuestionResponse.fromJson({
  'status': status, 'scope': 'Neighbourhood', 'format': 'Single',
  'message': status == 'partial' ? 'Some requested history could not be verified.' : null,
  'answers': status == 'empty' ? [] : [{
    'story': {
      'storyId': 'question-fixture', 'title': 'The neighbourhood workshop',
      'anchor': {'latitude': 51.5, 'longitude': -0.12},
      'expiresUtc': DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String(),
      'audienceSuitability': 'sensitive',
      'sensitivityNotice': 'Content note: loss and recovery.',
      'claims': [{'claimId': 'c1', 'text': 'Archive test text.', 'sourceIds': ['s1'], 'confidence': 0.9}],
      'sources': [{'sourceId': 's1', 'title': 'Test archive', 'url': 'https://example.org/history',
        'providerName': 'Archive', 'attribution': 'Test archive', 'confidence': 0.9}],
      'variants': [],
    },
    'variant': {'length': 'Standard', 'estimatedDurationSeconds': 40,
      'narration': 'The archive records how a small workshop changed as the surrounding neighbourhood grew. '
          'The surviving records connect the people who worked here with changes visible in the streets today.',
      'claimIds': ['c1']},
    'reason': 'Explicit answer',
  }],
});

class _Client extends RoverApiClient {
  _Client(this.respond);
  final Future<StoryQuestionResponse> Function(StoryQuestionRequest) respond;
  StoryQuestionRequest? request;
  bool closed = false;
  @override
  Future<StoryQuestionResponse> researchStoryQuestion(StoryQuestionRequest value) {
    request = value;
    return respond(value);
  }
  @override
  void close({bool force = false}) {
    closed = true;
    super.close(force: force);
  }
}
