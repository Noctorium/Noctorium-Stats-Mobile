import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:noctorium_stats/service.dart';
import 'package:noctorium_stats/stats.dart';

import 'fixtures.dart';

NoctoriumService answering(Future<http.Response> Function(http.Request request) handler,
        {String base = 'http://localhost:3000', Duration timeout = const Duration(seconds: 20)}) =>
    NoctoriumService(baseUrl: base, client: MockClient(handler), timeout: timeout, userAgent: 'NoctoriumStats/9.9.9');

http.Response json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

void main() {
  group('Requests', () {
    final service = answering((_) async => json({}));

    test('statistics are asked for by range, on the phone\'s clock', () {
      expect(
        service.statsUri(StatsRange.month, offset: const Duration(hours: 3)).toString(),
        'http://localhost:3000/api/stats?range=30d&tz=180&limit=10',
      );
      expect(
        service.statsUri(StatsRange.all, offset: const Duration(hours: -5)).queryParameters,
        {'range': 'all', 'tz': '-300', 'limit': '10'},
      );
      // Half-hour zones are whole minutes too, and nothing past what the service accepts is sent.
      expect(service.statsUri(StatsRange.week, offset: const Duration(hours: 5, minutes: 30)).queryParameters['tz'],
          '330');
      expect(service.statsUri(StatsRange.week, offset: const Duration(hours: 20)).queryParameters['tz'], '840');
      expect(service.statsUri(StatsRange.year, offset: Duration.zero, limit: 99).queryParameters['limit'], '50');
    });

    test('a trailing slash or a path in the address is kept straight', () {
      expect(answering((_) async => json({}), base: 'https://noctorium-service.vercel.app/').endpoint('/api/auth/me').toString(),
          'https://noctorium-service.vercel.app/api/auth/me');
      expect(answering((_) async => json({}), base: 'https://example.test/noctorium').endpoint('/api/stats').toString(),
          'https://example.test/noctorium/api/stats');
      expect(answering((_) async => json({}), base: 'https://noctorium-service.vercel.app').website.toString(),
          'https://noctorium-service.vercel.app/');
    });

    test('the token goes in a bearer header, and nowhere else', () async {
      late http.Request seen;
      final service = answering((request) async {
        seen = request;
        return http.Response(fixture('stats-listener-7d.json'), 200);
      });
      await service.stats('abc', StatsRange.week, offset: const Duration(hours: 3));
      expect(seen.method, 'GET');
      expect(seen.headers['Authorization'], 'Bearer abc');
      expect(seen.headers['Accept'], 'application/json');
      expect(seen.headers['User-Agent'], 'NoctoriumStats/9.9.9');
      expect(seen.url.toString(), isNot(contains('abc')));
    });

    test('signing in posts the address, trimmed, and the password as typed', () async {
      late http.Request seen;
      final service = answering((request) async {
        seen = request;
        return json({'token': 't', 'user': {'id': 3, 'email': 'robin@example.test', 'displayName': 'Robin Vale'}});
      });
      final session = await service.signIn('  robin@example.test ', ' spaces count ');
      expect(seen.method, 'POST');
      expect(seen.url.path, '/api/auth/login');
      expect(seen.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(seen.body), {'email': 'robin@example.test', 'password': ' spaces count '});
      expect(session.token, 't');
      expect(session.account.displayName, 'Robin Vale');
    });

    test('creating an account sends a name only when there is one', () async {
      final bodies = <Object?>[];
      final service = answering((request) async {
        bodies.add(jsonDecode(request.body));
        return json({'token': 't', 'user': {'id': 4, 'email': 'sam@example.test', 'displayName': 'sam'}}, 201);
      });
      await service.createAccount('sam@example.test', 'long enough pw', displayName: '  ');
      await service.createAccount('sam@example.test', 'long enough pw', displayName: ' Sam Quill ');
      expect(bodies, [
        {'email': 'sam@example.test', 'password': 'long enough pw'},
        {'email': 'sam@example.test', 'password': 'long enough pw', 'displayName': 'Sam Quill'},
      ]);
    });

    test('who a token belongs to, with a name to show even when the account has none', () async {
      final service = answering((_) async => json({'user': {'id': 9, 'email': 'kit@example.test', 'displayName': ''}}));
      final account = await service.me('t');
      expect(account.id, 9);
      expect(account.displayName, 'kit');
    });

    test('a song title in Cyrillic arrives intact whatever the headers say', () async {
      final service = answering((_) async => http.Response.bytes(
            utf8.encode('{"streams": 1, "topTracks": [{"title": "Северный ветер", "artist": "Odile Brandt", '
                '"provider": "VK", "streams": 1, "minutes": 3}]}'),
            200,
            headers: {'content-type': 'application/json'},
          ));
      final stats = await service.stats('t', StatsRange.all, offset: Duration.zero);
      expect(stats.topTracks.single.title, 'Северный ветер');
    });
  });

  group('Failures, in words', () {
    Future<ServiceException> failure(Future<Object?> Function() call) async {
      try {
        await call();
      } on ServiceException catch (error) {
        return error;
      }
      fail('expected a ServiceException');
    }

    test('a wrong password is the service\'s own words', () async {
      final service = answering(
          (_) async => json({'error': 'That email address and password do not match an account.'}, 401));
      final error = await failure(() => service.signIn('a@example.test', 'nope'));
      expect(error.failure, Failure.refused);
      expect(error.status, 401);
      expect(error.message, 'That email address and password do not match an account.');
    });

    test('a 401 to a token means signing in again', () async {
      final service = answering((_) async => json({'error': 'Not signed in.'}, 401));
      final error = await failure(() => service.stats('old', StatsRange.week, offset: Duration.zero));
      expect(error.failure, Failure.signedOut);
      expect(error.message, 'You have been signed out. Sign in again to see your statistics.');
      expect((await failure(() => service.me('old'))).failure, Failure.signedOut);
    });

    test('throttling says how long to wait', () async {
      final service = answering((_) async => json({'error': 'Too many attempts. Try again in 15 minutes.'}, 429));
      final error = await failure(() => service.signIn('a@example.test', 'pw'));
      expect(error.failure, Failure.throttled);
      expect(error.message, 'Too many attempts. Try again in 15 minutes.');
      // And says something useful even when the reply has no words of its own.
      expect(failureFor(429, '', Asking.withToken).message, 'Too many attempts. Try again in a few minutes.');
    });

    test('an address already taken, or one the service will not accept', () async {
      final taken = answering((_) async => json({'error': 'That email address already has an account.'}, 409));
      final error = await failure(() => taken.createAccount('a@example.test', 'long enough pw'));
      expect(error.failure, Failure.refused);
      expect(error.message, 'That email address already has an account.');
      final invalid = answering((_) async => json({'error': 'Use at least 10 characters.'}, 400));
      expect((await failure(() => invalid.createAccount('a@example.test', 'short'))).message,
          'Use at least 10 characters.');
    });

    test('the service having trouble, or something in between answering for it', () async {
      final down = answering((_) async => http.Response('<html>Bad gateway</html>', 502));
      final error = await failure(() => down.stats('t', StatsRange.week, offset: Duration.zero));
      expect(error.failure, Failure.server);
      expect(error.message, 'The Noctorium service is having trouble (502). Try again in a minute.');

      final portal = answering((_) async => http.Response('<html>Sign in to the café wifi</html>', 200));
      final caught = await failure(() => portal.stats('t', StatsRange.week, offset: Duration.zero));
      expect(caught.failure, Failure.unreadable);

      final odd = answering((_) async => http.Response('nope', 418));
      expect((await failure(() => odd.stats('t', StatsRange.week, offset: Duration.zero))).failure, Failure.unreadable);
    });

    test('no connection is offline', () async {
      final unreachable = answering((_) async => throw const SocketException('Failed host lookup'));
      final error = await failure(() => unreachable.stats('t', StatsRange.week, offset: Duration.zero));
      expect(error.failure, Failure.offline);
      expect(error.status, isNull);
      expect(error.message, 'Cannot reach the Noctorium service. Check this phone is online, then try again.');

      final dropped = answering((_) async => throw http.ClientException('Connection closed'));
      expect((await failure(() => dropped.signIn('a@example.test', 'pw'))).failure, Failure.offline);

      final insecure = answering((_) async => throw const HandshakeException('bad certificate'));
      expect((await failure(() => insecure.me('t'))).failure, Failure.offline);
    });

    test('a service that never answers is given up on', () async {
      final slow = answering(
        (_) => Completer<http.Response>().future,
        timeout: const Duration(milliseconds: 20),
      );
      final error = await failure(() => slow.stats('t', StatsRange.week, offset: Duration.zero));
      expect(error.failure, Failure.offline);
      expect(error.message, startsWith('The Noctorium service took too long to answer.'));
    });

    test('a reply that signs in nobody is not taken for a sign-in', () async {
      final service = answering((_) async => json({'ok': true}));
      expect((await failure(() => service.signIn('a@example.test', 'pw'))).failure, Failure.unreadable);
    });
  });
}
