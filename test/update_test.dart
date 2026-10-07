import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:noctorium_stats/update.dart';

void main() {
  test('versions are read the way the tags are written', () {
    expect(Version.parse('v0.12.2').toString(), '0.12.2');
    expect(Version.parse('0.13.0').toString(), '0.13.0');
    expect(Version.parse('v1.2.3-beta.1')!.preRelease, 'beta.1');
    expect(Version.parse('1.2')!.toString(), '1.2.0');
    expect(Version.parse('0.12.2+1202').toString(), '0.12.2');
    expect(Version.parse('latest'), isNull);
    expect(Version.parse(null), isNull);
  });

  test('versions compare as numbers, and a pre-release comes before its release', () {
    expect(Version.parse('0.13.0')! > Version.parse('0.12.9')!, isTrue);
    expect(Version.parse('0.10.0')! > Version.parse('0.9.0')!, isTrue);
    expect(Version.parse('0.12.2')! > Version.parse('0.12.2')!, isFalse);
    expect(Version.parse('1.0.0')! > Version.parse('1.0.0-beta.2')!, isTrue);
    expect(Version.parse('v0.12.2'), Version.parse('0.12.2'));
  });

  test('versionCode is packed as Noctorium\'s', () {
    expect(Version.parse('1.2.3')!.versionCode, 10203);
    expect(Version.parse('0.13.0')!.versionCode, 1300);
  });

  group('Asking GitHub', () {
    UpdateChecker answering(int status, Object body) => UpdateChecker(
          MockClient((request) async {
            expect(request.url.toString(), latestReleaseApi);
            return http.Response(jsonEncode(body), status);
          }),
        );

    final release = {
      'tag_name': 'v0.13.0',
      'html_url': 'https://github.com/Noctorium/Noctorium-Installer/releases/tag/v0.13.0',
    };

    test('a newer release is reported with its page', () async {
      final newer = await answering(200, release).newerThan('0.12.2');
      expect(newer!.version.toString(), '0.13.0');
      expect(newer.page.toString(), endsWith('/releases/tag/v0.13.0'));
    });

    test('the same or an older one is not', () async {
      expect(await answering(200, release).newerThan('0.13.0'), isNull);
      expect(await answering(200, release).newerThan('0.14.1'), isNull);
    });

    test('a check that fails says nothing', () async {
      expect(await answering(403, {'message': 'API rate limit exceeded'}).newerThan('0.12.2'), isNull);
      expect(await answering(200, {'message': 'Not Found'}).newerThan('0.12.2'), isNull);
      expect(await answering(200, release).newerThan('a local build'), isNull);
      final offline = UpdateChecker(MockClient((_) async => throw http.ClientException('offline')));
      expect(await offline.newerThan('0.12.2'), isNull);
    });
  });
}
