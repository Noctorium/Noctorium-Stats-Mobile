/// Whether a newer Noctorium Stats is out.
///
/// Noctorium Stats ships in every Noctorium release, so the newest release of Noctorium-Installer is the
/// newest Noctorium Stats. Asked once at launch and said quietly, in a line: nothing is downloaded, and a
/// check that fails for any reason -- offline, GitHub's rate limit -- says nothing at all.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

const String latestReleaseApi = 'https://api.github.com/repos/Noctorium/Noctorium-Installer/releases/latest';

/// A version as the release tags write it: `v0.12.2`, `0.13.0`, `v1.0.0-beta.1`.
class Version implements Comparable<Version> {
  const Version(this.major, this.minor, this.patch, {this.preRelease = ''});

  final int major;
  final int minor;
  final int patch;

  /// What follows a hyphen, which sorts before the same version without one.
  final String preRelease;

  static Version? parse(String? text) {
    if (text == null) return null;
    final match = RegExp(r'^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:-([0-9A-Za-z.-]+))?(?:\+.*)?$').firstMatch(text.trim());
    if (match == null) return null;
    return Version(
      int.parse(match.group(1)!),
      int.parse(match.group(2) ?? '0'),
      int.parse(match.group(3) ?? '0'),
      preRelease: match.group(4) ?? '',
    );
  }

  /// Android's versionCode for this version, packed as Noctorium's is: 1.2.3 is 10203.
  int get versionCode => major * 10000 + minor * 100 + patch;

  @override
  int compareTo(Version other) {
    for (final (a, b) in [(major, other.major), (minor, other.minor), (patch, other.patch)]) {
      if (a != b) return a.compareTo(b);
    }
    if (preRelease == other.preRelease) return 0;
    if (preRelease.isEmpty) return 1;
    if (other.preRelease.isEmpty) return -1;
    return preRelease.compareTo(other.preRelease);
  }

  bool operator >(Version other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) => other is Version && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease);

  @override
  String toString() => '$major.$minor.$patch${preRelease.isEmpty ? '' : '-$preRelease'}';
}

class Release {
  const Release({required this.version, required this.page});

  final Version version;

  /// The release's page on GitHub, which is where somebody goes to get it.
  final Uri page;

  /// Reads GitHub's answer for a release; null for anything that is not one.
  static Release? fromJson(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) return null;
      final version = Version.parse(json['tag_name'] as String?);
      final page = Uri.tryParse(json['html_url'] as String? ?? '');
      if (version == null || page == null || !page.hasScheme) return null;
      return Release(version: version, page: page);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}

class UpdateChecker {
  UpdateChecker(this._client, {this.url = latestReleaseApi});

  final http.Client _client;
  final String url;

  /// The latest release when it is newer than [current]; null when it is not, or when nobody could say.
  Future<Release?> newerThan(String current) async {
    final installed = Version.parse(current);
    if (installed == null) return null;
    try {
      final response = await _client
          .get(Uri.parse(url), headers: const {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final release = Release.fromJson(response.body);
      return release != null && release.version > installed ? release : null;
    } catch (_) {
      return null;
    }
  }
}
