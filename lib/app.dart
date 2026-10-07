/// The application: signed in or not, and what that decides.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/dashboard.dart';
import 'screens/sign_in.dart';
import 'service.dart';
import 'store.dart';
import 'theme.dart';
import 'update.dart';
import 'widgets/mark.dart';

/// Everything the screens reach outside themselves for, handed in so a test can hand in something else: a
/// service answering from fixtures, a token store in memory, a clock that always says the same time.
class Dependencies {
  Dependencies({
    required this.service,
    required this.tokens,
    required this.preferences,
    required this.version,
    required this.openLink,
    this.debugBuild = false,
    this.updates,
    DateTime Function()? now,
    Duration Function()? offset,
  })  : now = now ?? DateTime.now,
        offset = offset ?? (() => DateTime.now().timeZoneOffset);

  final NoctoriumService service;
  final TokenStore tokens;
  final Preferences preferences;

  /// This build's version, as the About line shows it.
  final String version;

  /// Said beside the version, so a build from a computer is never mistaken for a release.
  final bool debugBuild;

  String get versionLabel => debugBuild ? '$version, a debug build' : version;

  /// Opens a page in the browser; false when nothing could.
  final Future<bool> Function(Uri) openLink;

  /// Asks whether a newer release is out; null to never ask.
  final UpdateChecker? updates;

  final DateTime Function() now;

  /// How far the phone's clock is from UTC: the service counts days and hours on it, and every time on
  /// screen is shown on it.
  final Duration Function() offset;
}

class StatsApp extends StatelessWidget {
  const StatsApp({super.key, required this.deps});

  final Dependencies deps;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Noctorium Stats',
      debugShowCheckedModeBanner: false,
      theme: nightTheme(),
      darkTheme: nightTheme(),
      themeMode: ThemeMode.dark,
      home: AnnotatedRegion<SystemUiOverlayStyle>(
        // Edge to edge: the page runs under both system bars, which are see-through with light icons.
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
          systemNavigationBarContrastEnforced: false,
        ),
        child: Root(deps: deps),
      ),
    );
  }
}

class Root extends StatefulWidget {
  const Root({super.key, required this.deps});

  final Dependencies deps;

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  bool _reading = true;
  String? _token;
  Account? _account;

  /// Said on the sign-in screen when the app is the one that signed somebody out.
  String? _notice;

  /// Asked once a launch, whoever signs in and out in the meantime.
  late final Future<Release?> _update =
      widget.deps.updates?.newerThan(widget.deps.version) ?? Future<Release?>.value(null);

  @override
  void initState() {
    super.initState();
    _readToken();
  }

  Future<void> _readToken() async {
    final token = await widget.deps.tokens.read();
    if (!mounted) return;
    setState(() {
      _token = token;
      _reading = false;
    });
  }

  Future<void> _signedIn(Session session) async {
    await widget.deps.tokens.write(session.token);
    if (!mounted) return;
    setState(() {
      _token = session.token;
      _account = session.account;
      _notice = null;
    });
  }

  Future<void> _signedOut({String? notice}) async {
    await widget.deps.tokens.clear();
    if (!mounted) return;
    setState(() {
      _token = null;
      _account = null;
      _notice = notice;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget page;
    if (_reading) {
      // A moment at most: the keystore is local. The mark, so it is not a blank flash.
      page = const Scaffold(key: ValueKey('reading'), body: Center(child: Mark(size: 72)));
    } else if (_token case final token?) {
      page = Dashboard(
        key: ValueKey('dashboard-$token'),
        deps: widget.deps,
        token: token,
        account: _account,
        update: _update,
        onSignedOut: _signedOut,
      );
    } else {
      page = SignInScreen(key: const ValueKey('sign-in'), deps: widget.deps, notice: _notice, onSignedIn: _signedIn);
    }
    return AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: page);
  }
}
