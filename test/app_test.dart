import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctorium_stats/stats.dart';
import 'package:noctorium_stats/store.dart';

import 'support.dart';

Finder field(String label) => find.widgetWithText(TextField, label);

void main() {
  group('Signing in', () {
    testWidgets('starts on the sign-in screen when there is no token', (tester) async {
      phone(tester);
      await launch(tester, testDeps(FakeServer()));
      expect(find.text('Noctorium Stats'), findsOneWidget);
      expect(find.text('Your listening, in numbers.'), findsOneWidget);
      expect(field('Email address'), findsOneWidget);
      expect(field('Password'), findsOneWidget);
    });

    testWidgets('says what is missing before asking the service', (tester) async {
      phone(tester);
      final server = FakeServer();
      await launch(tester, testDeps(server));
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();
      expect(find.text('Enter the email address of your Noctorium account.'), findsOneWidget);
      await tester.enterText(field('Email address'), 'not an address');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();
      expect(find.text('That does not look like an email address.'), findsOneWidget);
      expect(server.requests.where((r) => r.url.path.startsWith('/api/auth')), isEmpty);
    });

    testWidgets('signs in, keeps the token, and shows the statistics', (tester) async {
      phone(tester);
      final server = FakeServer();
      final tokens = MemoryTokenStore();
      await launch(tester, testDeps(server, tokens: tokens));
      await tester.enterText(field('Email address'), goodEmail);
      await tester.enterText(field('Password'), goodPassword);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await settle(tester);

      expect(tokens.token, goodToken);
      expect(find.text('Robin Vale'), findsOneWidget);
      expect(find.text('Songs streamed'), findsOneWidget);
      // Thirty days to begin with, until something else is chosen.
      expect(server.statsRequests.last.url.queryParameters, {'range': '30d', 'tz': '180', 'limit': '10'});
      expect(find.text('118'), findsOneWidget);
    });

    testWidgets('a wrong password is said in the service\'s words', (tester) async {
      phone(tester);
      final tokens = MemoryTokenStore();
      await launch(tester, testDeps(FakeServer(), tokens: tokens));
      await tester.enterText(field('Email address'), goodEmail);
      await tester.enterText(field('Password'), 'not the password');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await settle(tester);
      expect(find.text('That email address and password do not match an account.'), findsOneWidget);
      expect(tokens.token, isNull);
    });

    testWidgets('creating an account asks for a name and a long enough password', (tester) async {
      phone(tester);
      final server = FakeServer();
      await launch(tester, testDeps(server));
      await tester.tap(find.text('Create account').first);
      await tester.pumpAndSettle();
      expect(field('Your name (optional)'), findsOneWidget);
      expect(find.text('At least 10 characters.'), findsOneWidget);

      await tester.enterText(field('Email address'), 'kit@example.test');
      await tester.enterText(field('Password'), 'short');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pump();
      expect(find.text('Use at least 10 characters for the password.'), findsOneWidget);

      // An address that already has an account is the service's to say.
      await tester.enterText(field('Email address'), goodEmail);
      await tester.enterText(field('Password'), 'long enough password');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await settle(tester);
      expect(find.text('That email address already has an account.'), findsOneWidget);
    });

    testWidgets('the website is a tap away', (tester) async {
      phone(tester);
      final server = FakeServer();
      await launch(tester, testDeps(server));
      await tester.tap(find.text('Open the website'));
      await tester.pump();
      expect(server.opened.single.toString(), 'http://localhost:3000/');
    });
  });

  group('The dashboard', () {
    testWidgets('opens on the range chosen last time, with every part of it', (tester) async {
      phone(tester);
      final server = FakeServer();
      await launch(tester, testDeps(server, tokens: MemoryTokenStore(goodToken), range: StatsRange.week));
      expect(server.statsRequests.single.url.queryParameters['range'], '7d');
      expect(find.text('Robin Vale'), findsOneWidget);
      expect(find.text('1 – 7 October 2026 · Last played today at 12:00'), findsOneWidget);
      for (final figure in ['32', '19', '11', '1.7']) {
        expect(find.text(figure), findsOneWidget);
      }
      expect(find.text('12 days in a row'), findsOneWidget);

      final list = find.byType(Scrollable).first;
      for (final title in ['Day by day', 'By service', 'Top songs', 'Top artists', 'Hours of the day',
          'Days of the week', 'Recently played']) {
        await tester.scrollUntilVisible(find.text(title), 300, scrollable: list);
        expect(find.text(title), findsOneWidget);
      }
      expect(find.text('Today, 12:00'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Noctorium Stats 0.12.2'), 300, scrollable: list);
    });

    testWidgets('choosing a range asks for it and remembers it', (tester) async {
      phone(tester);
      final server = FakeServer();
      final deps = testDeps(server, tokens: MemoryTokenStore(goodToken), range: StatsRange.week);
      await launch(tester, deps);
      await tester.tap(find.text('All time'));
      await settle(tester);
      expect(server.statsRequests.last.url.queryParameters['range'], 'all');
      expect(await deps.preferences.lastRange(), StatsRange.all);
      expect(find.text('1,553'), findsOneWidget);
      expect(find.text('Month by month'), findsOneWidget);
      expect(find.text('Since 14 Aug 2025 · Last played today at 12:00'), findsOneWidget);

      // Going back shows what was loaded at once, and asks again behind it.
      await tester.tap(find.text('7 days'));
      await tester.pump();
      expect(find.text('32'), findsOneWidget);
      await settle(tester);
      expect(server.statsRequests.map((r) => r.url.queryParameters['range']), ['7d', 'all', '7d']);
    });

    testWidgets('a token the service no longer takes means signing in again', (tester) async {
      phone(tester);
      final server = FakeServer();
      final tokens = MemoryTokenStore('a-token-from-long-ago');
      await launch(tester, testDeps(server, tokens: tokens));
      expect(tokens.token, isNull);
      expect(find.text('You have been signed out. Sign in again to see your statistics.'), findsOneWidget);
      expect(field('Email address'), findsOneWidget);
    });

    testWidgets('offline is said plainly, and trying again works once it is back', (tester) async {
      phone(tester);
      final server = FakeServer()..failWith = const SocketException('Failed host lookup');
      final tokens = MemoryTokenStore(goodToken);
      await launch(tester, testDeps(server, tokens: tokens));
      expect(find.text('You are offline'), findsOneWidget);
      expect(find.text('Cannot reach the Noctorium service. Check this phone is online, then try again.'),
          findsOneWidget);
      // Being offline is not being signed out.
      expect(tokens.token, goodToken);

      server.failWith = null;
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.text('You are offline'), findsNothing);
      expect(find.text('118'), findsOneWidget);
    });

    testWidgets('a refresh that fails keeps what is on screen and says so', (tester) async {
      phone(tester);
      final server = FakeServer();
      await launch(tester, testDeps(server, tokens: MemoryTokenStore(goodToken)));
      expect(find.text('118'), findsOneWidget);

      server.statsStatus = 503;
      await tester.fling(find.byType(Scrollable).first, const Offset(0, 500), 1500);
      await settle(tester);
      expect(find.text('118'), findsOneWidget);
      expect(find.textContaining('Not up to date. The Noctorium service is having trouble (503).'), findsOneWidget);

      server.statsStatus = null;
      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(find.textContaining('Not up to date.'), findsNothing);
    });

    testWidgets('an account with nothing played says what to do', (tester) async {
      phone(tester);
      final server = FakeServer(listener: 'empty');
      await launch(tester, testDeps(server, tokens: MemoryTokenStore(goodToken), range: StatsRange.all));
      expect(find.text('Nothing played yet'), findsOneWidget);
      expect(
        find.text('Play something in Noctorium while you are signed in to this account, and it will be counted here.'),
        findsOneWidget,
      );
      expect(find.text('Songs streamed'), findsNothing);
    });

    testWidgets('signing out from the menu forgets the token', (tester) async {
      phone(tester);
      final tokens = MemoryTokenStore(goodToken);
      await launch(tester, testDeps(FakeServer(), tokens: tokens));
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await settle(tester);
      expect(tokens.token, isNull);
      expect(field('Email address'), findsOneWidget);
    });

    testWidgets('the menu opens the website and says which version this is', (tester) async {
      phone(tester);
      final server = FakeServer();
      await launch(tester, testDeps(server, tokens: MemoryTokenStore(goodToken)));
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open the website'));
      await tester.pumpAndSettle();
      expect(server.opened.single.toString(), 'http://localhost:3000/');

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('About Noctorium Stats'));
      await tester.pumpAndSettle();
      expect(find.text('Version 0.12.2'), findsOneWidget);
    });

    testWidgets('a newer release is mentioned, and taken to its page', (tester) async {
      phone(tester);
      final server = FakeServer(latestTag: 'v0.13.0');
      await launch(tester, testDeps(server, tokens: MemoryTokenStore(goodToken)));
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('Noctorium Stats 0.13.0 is out.'), 400, scrollable: list);
      await tester.tap(find.text('Get it'));
      await tester.pump();
      expect(server.opened.single.toString(), 'https://github.com/Noctorium/Noctorium-Installer/releases/tag/v0.13.0');
    });

    testWidgets('the same release is not', (tester) async {
      phone(tester);
      final server = FakeServer(latestTag: 'v0.12.2');
      await launch(tester, testDeps(server, tokens: MemoryTokenStore(goodToken)));
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('Noctorium Stats 0.12.2'), 400, scrollable: list);
      expect(find.textContaining('is out.'), findsNothing);
    });

    testWidgets('a 12-hour phone gets 12-hour times', (tester) async {
      phone(tester);
      await launch(tester, testDeps(FakeServer(), tokens: MemoryTokenStore(goodToken), range: StatsRange.week),
          use24: false);
      expect(find.text('1 – 7 October 2026 · Last played today at 12:00 pm'), findsOneWidget);
    });
  });

  group('At the largest text size', () {
    // Twice the size, as Android's largest setting is: nothing may overflow, and everything must still be
    // there to find.
    Future<void> everywhere(WidgetTester tester, StatsRange range, {String account = 'listener'}) async {
      phone(tester, textScale: 2);
      await launch(tester, testDeps(FakeServer(listener: account), tokens: MemoryTokenStore(goodToken), range: range));
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.textContaining('Noctorium Stats 0.12.2'), 500, scrollable: list);
      expect(tester.takeException(), isNull);
    }

    for (final range in StatsRange.values) {
      testWidgets('the dashboard for ${range.label}', (tester) => everywhere(tester, range));
    }

    testWidgets('the empty dashboard', (tester) => everywhere(tester, StatsRange.all, account: 'empty'));

    testWidgets('signing in and making an account', (tester) async {
      phone(tester, textScale: 2);
      await launch(tester, testDeps(FakeServer()));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Create account').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('offline', (tester) async {
      phone(tester, textScale: 2);
      final server = FakeServer()..failWith = const SocketException('Failed host lookup');
      await launch(tester, testDeps(server, tokens: MemoryTokenStore(goodToken)));
      expect(find.text('Try again'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a narrow phone at a large size still fits the ranges', (tester) async {
    phone(tester, textScale: 1.3, size: const Size(320, 640));
    await launch(tester, testDeps(FakeServer(), tokens: MemoryTokenStore(goodToken)));
    for (final range in StatsRange.values) {
      expect(find.text(range.label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
