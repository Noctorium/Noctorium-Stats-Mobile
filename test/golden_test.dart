/// Pictures of every screen, to look at: `flutter test --update-goldens --tags golden` draws them into
/// `test/goldens/`, and a plain `flutter test` checks nothing has changed since.
///
/// Each is a phone the width of the one this was made on, with the whole page laid out top to bottom
/// rather than cut off at the bottom of the screen, at the ordinary text size and at twice it -- the
/// largest Android offers. Text is drawn in Roboto, loaded by flutter_test_config.dart.
///
/// Tagged, because the same picture drawn on Linux and on Windows differs in the last pixel of every
/// letter: CI leaves these out, and they are checked on the machine that drew them.
@Tags(['golden'])
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noctorium_stats/stats.dart';
import 'package:noctorium_stats/store.dart';

import 'support.dart';

const _width = 393.0;
const _ratio = 2.0;

/// Grows the window until the page's whole length fits in it, and no further.
///
/// A list of slivers only guesses at the length of what it has not laid out yet, so the length is read
/// again after every growth until it stops changing; a page shorter than a phone stays a phone's height.
Future<void> wholePage(WidgetTester tester) async {
  var height = 852.0;
  for (var i = 0; i < 12; i++) {
    final needed = math.max(852.0, _contentLength(tester).ceilToDouble());
    if ((needed - height).abs() < 1) break;
    height = needed;
    tester.view.physicalSize = Size(_width * _ratio, height * _ratio);
    await tester.pumpAndSettle();
  }
}

double _contentLength(WidgetTester tester) {
  final viewports = find.byType(Viewport);
  if (viewports.evaluate().isNotEmpty) {
    final viewport = tester.renderObject<RenderViewport>(viewports.first);
    var length = 0.0;
    for (var sliver = viewport.firstChild; sliver != null; sliver = viewport.childAfter(sliver)) {
      length += sliver.geometry!.scrollExtent;
    }
    return length;
  }
  final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
  return position.viewportDimension + position.maxScrollExtent;
}

Future<void> shoot(WidgetTester tester, String name) async {
  await decodeImages(tester);
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
}

void main() {
  for (final (scale, suffix) in [(1.0, ''), (2.0, '_large')]) {
    group('At ${scale}x text', () {
      testWidgets('sign in', (tester) async {
        phone(tester, textScale: scale);
        await launch(tester, testDeps(FakeServer()));
        await wholePage(tester);
        await shoot(tester, 'sign_in$suffix');
      });

      testWidgets('signed out by the app', (tester) async {
        if (scale != 1.0) return;
        phone(tester, textScale: scale);
        final server = FakeServer()..statsStatus = 401;
        await launch(tester, testDeps(server, tokens: MemoryTokenStore('stale-token')));
        await shoot(tester, 'sign_in_signed_out');
      });

      for (final range in [StatsRange.week, StatsRange.month, StatsRange.all]) {
        if (scale != 1.0 && range == StatsRange.month) continue;
        testWidgets('the listener, ${range.label}', (tester) async {
          phone(tester, textScale: scale);
          // All time also shows the line a newer release puts at the foot of the page.
          final server = FakeServer(latestTag: range == StatsRange.all ? 'v0.13.0' : 'v0.12.2');
          await launch(tester, testDeps(server, tokens: MemoryTokenStore(goodToken), range: range));
          await wholePage(tester);
          await shoot(tester, 'dashboard_${range.query}$suffix');
        });
      }

      testWidgets('the first screenful', (tester) async {
        phone(tester, textScale: scale);
        await launch(tester, testDeps(FakeServer(), tokens: MemoryTokenStore(goodToken), range: StatsRange.month));
        await shoot(tester, 'dashboard_first_screen$suffix');
      });

      testWidgets('an account with nothing played', (tester) async {
        phone(tester, textScale: scale);
        final server = FakeServer(listener: 'empty');
        await launch(tester, testDeps(server, tokens: MemoryTokenStore(goodToken), range: StatsRange.all));
        await wholePage(tester);
        await shoot(tester, 'empty$suffix');
      });

      testWidgets('offline', (tester) async {
        phone(tester, textScale: scale);
        final server = FakeServer()..failWith = const SocketException('Failed host lookup');
        await launch(tester, testDeps(server, tokens: MemoryTokenStore(goodToken), range: StatsRange.month));
        await wholePage(tester);
        await shoot(tester, 'offline$suffix');
      });

      testWidgets('the service having trouble', (tester) async {
        if (scale != 1.0) return;
        phone(tester, textScale: scale);
        final server = FakeServer()..statsStatus = 503;
        await launch(tester, testDeps(server, tokens: MemoryTokenStore(goodToken), range: StatsRange.month));
        await shoot(tester, 'error_server');
      });
    });
  }
}
