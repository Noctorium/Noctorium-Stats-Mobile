/// Noctorium Stats: signs in to a listener's Noctorium account and shows what they have been listening to.
///
/// The statistics are the service's -- counted from the plays the Noctorium player records while signed in
/// -- and this is a window onto them, the phone's half of a pair with the desktop's Noctorium Stats.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'app.dart';
import 'service.dart';
import 'store.dart';
import 'update.dart';

/// This build's version: `--build-name` when the release passed one, pubspec.yaml's otherwise.
const String version = appBuildName ?? '0.0.0';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Drawn under the status bar and the navigation bar, as Android 15 insists on and earlier versions
  // allow; every screen pads itself by the insets.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final client = http.Client();
  runApp(StatsApp(
    deps: Dependencies(
      service: NoctoriumService(
        baseUrl: serviceUrl,
        client: client,
        userAgent: 'NoctoriumStats/${appBuildName ?? 'dev'} (Android)',
        // A copy of the service on the computer, through adb reverse, for a debug build and nothing else.
        loopbackHttp: kDebugMode,
      ),
      tokens: const SecureTokenStore(),
      preferences: SharedPreferencesStore(),
      version: version,
      debugBuild: kDebugMode,
      updates: UpdateChecker(client),
      openLink: (link) async {
        try {
          return await launchUrl(link, mode: LaunchMode.externalApplication);
        } catch (_) {
          return false;
        }
      },
    ),
  ));
}
