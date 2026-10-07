/// The statistics the tests read.
///
/// The files under `fixtures/` are real answers from a local copy of the Noctorium service filled with its
/// made-up seed data (scripts/seed-local.mjs there), asked with `tz=180`. Every artist, song and name in them
/// is invented.
library;

import 'dart:io';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// When the fixtures were captured, give or take: the evening of 7 October 2026, three hours east of UTC.
final DateTime fixtureNow = DateTime.utc(2026, 10, 7, 18, 47);
const Duration fixtureOffset = Duration(hours: 3);
