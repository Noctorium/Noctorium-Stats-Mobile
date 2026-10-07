/// What the widget tests share: a pretend service answering from the fixtures, the app's dependencies wired
/// to it, and a phone-sized window to draw in.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:noctorium_stats/app.dart';
import 'package:noctorium_stats/service.dart';
import 'package:noctorium_stats/stats.dart';
import 'package:noctorium_stats/store.dart';
import 'package:noctorium_stats/update.dart';

import 'fixtures.dart';

export 'fixtures.dart';

/// A made-up account for the pretend service; nothing here is anybody's.
const String goodEmail = 'robin@example.test';
const String goodPassword = 'a-made-up-password';
const String goodToken = 'token-for-tests';

/// The Noctorium service, and GitHub's release API, as far as the app can tell.
class FakeServer {
  FakeServer({String listener = 'listener', this.latestTag = 'v0.12.2'}) : _file = listener;

  /// Which fixtures `/api/stats` answers from: `listener` or `empty`.
  String _file;
  set account(String file) => _file = file;

  /// The tag GitHub reports as the latest release.
  String latestTag;

  /// When set, every request to the service fails this way instead of being answered.
  Object? failWith;

  /// When set, `/api/stats` answers with this status and an `{ error }` body.
  int? statsStatus;

  final requests = <http.Request>[];
  final opened = <Uri>[];

  Iterable<http.Request> get statsRequests => requests.where((r) => r.url.path == '/api/stats');

  late final http.Client client = MockClient((request) async {
    requests.add(request);
    if (request.url.host == 'api.github.com') {
      return _json({
        'tag_name': latestTag,
        'html_url': 'https://github.com/Noctorium/Noctorium-Installer/releases/tag/$latestTag',
      });
    }
    if (failWith case final failure?) throw failure;
    final authorised = request.headers['Authorization'] == 'Bearer $goodToken';
    switch ((request.method, request.url.path)) {
      case ('POST', '/api/auth/login'):
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['email'] == goodEmail && body['password'] == goodPassword) return _signedIn(200);
        return _json({'error': 'That email address and password do not match an account.'}, 401);
      case ('POST', '/api/auth/signup'):
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['email'] == goodEmail) return _json({'error': 'That email address already has an account.'}, 409);
        return _signedIn(201);
      case ('GET', '/api/auth/me'):
        if (!authorised) return _json({'error': 'Not signed in.'}, 401);
        return _json({'user': _user});
      case ('GET', '/api/stats'):
        if (!authorised) return _json({'error': 'Not signed in.'}, 401);
        if (statsStatus case final status?) return _json({'error': 'Something went wrong.'}, status);
        final range = request.url.queryParameters['range'] ?? 'all';
        final name = 'stats-$_file-$range.json';
        final file = File('test/fixtures/$name');
        return http.Response.bytes(
          (file.existsSync() ? file : File('test/fixtures/stats-$_file-all.json')).readAsBytesSync(),
          200,
          headers: {'content-type': 'application/json'},
        );
    }
    return _json({'error': 'Not found.'}, 404);
  });

  static const _user = {'id': 7, 'email': goodEmail, 'displayName': 'Robin Vale'};

  http.Response _signedIn(int status) => _json({'token': goodToken, 'user': _user}, status);

  static http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json'},
      );
}

Dependencies testDeps(
  FakeServer server, {
  TokenStore? tokens,
  StatsRange? range,
  String version = '0.12.2',
}) =>
    Dependencies(
      service: NoctoriumService(baseUrl: 'http://localhost:3000', client: server.client),
      tokens: tokens ?? MemoryTokenStore(),
      preferences: MemoryPreferences(range),
      version: version,
      updates: UpdateChecker(server.client),
      openLink: (link) async {
        server.opened.add(link);
        return true;
      },
      now: () => fixtureNow,
      offset: () => fixtureOffset,
    );

/// A phone-sized window -- the width of the Xiaomi this was tried on -- with a status bar and a gesture bar,
/// at [textScale].
void phone(WidgetTester tester, {double textScale = 1, Size size = const Size(393, 852), double ratio = 2}) {
  tester.view.devicePixelRatio = ratio;
  tester.view.physicalSize = size * ratio;
  tester.view.padding = FakeViewPadding(top: 32 * ratio, bottom: 20 * ratio);
  tester.view.viewPadding = FakeViewPadding(top: 32 * ratio, bottom: 20 * ratio);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
}

/// Pumps the app and lets every request it makes on the way in be answered.
///
/// On a 24-hour clock, as most phones outside America are. Set on the MediaQuery the app inherits rather
/// than on the test dispatcher, which the app's MediaQuery does not reliably read until the window
/// changes size.
Future<void> launch(WidgetTester tester, Dependencies deps, {bool use24 = true}) async {
  await tester.pumpWidget(Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: use24),
      child: StatsApp(deps: deps),
    ),
  ));
  await settle(tester);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

/// Decodes the mark, which a widget test otherwise never gets round to: image decoding happens outside the
/// fake clock the test runs on.
Future<void> decodeImages(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      final image = element.widget as Image;
      await precacheImage(image.image, element);
    }
  });
  await tester.pumpAndSettle();
}
