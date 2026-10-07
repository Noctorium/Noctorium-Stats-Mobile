/// Talking to the Noctorium service: signing in, creating an account, and asking for statistics.
///
/// Every failure comes out as a [ServiceException] with words a person can read, because every one of them
/// ends up on the screen. The service's own `{ error }` messages are already written that way and are
/// passed through; what it cannot say -- that the phone is offline, that something between here and there
/// answered with a web page -- is said here.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'stats.dart';

/// Where the service is. A release talks to the live one; a debug build can be pointed at a copy running on
/// the computer with `--dart-define=NOCTORIUM_SERVICE_URL=http://localhost:3000` and
/// `adb reverse tcp:3000 tcp:3000`.
const String serviceUrl = String.fromEnvironment(
  'NOCTORIUM_SERVICE_URL',
  defaultValue: 'https://noctorium-service.vercel.app',
);

class Account {
  const Account({required this.id, required this.email, required this.displayName});

  final int id;
  final String email;
  final String displayName;

  static Account? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id'];
    final email = json['email'];
    if (id is! num || email is! String) return null;
    final name = json['displayName'];
    return Account(
      id: id.toInt(),
      email: email,
      displayName: name is String && name.trim().isNotEmpty ? name.trim() : email.split('@').first,
    );
  }
}

/// A token and whose it is: what signing in and creating an account both answer with.
class Session {
  const Session({required this.token, required this.account});

  final String token;
  final Account account;
}

/// What went wrong, as far as the screens need to tell the difference.
enum Failure {
  /// The email address and password did not match, or an account could not be made with them.
  refused,

  /// The saved token is no longer good: signed out elsewhere, or older than 90 days.
  signedOut,

  /// Too many attempts; the service says how long to wait.
  throttled,

  /// Nothing answered: no connection, or the service could not be reached.
  offline,

  /// Something answered, but not with what the service sends.
  unreadable,

  /// The service is up and having trouble.
  server,

  /// This build may not talk to that address: plain http anywhere but a debug build's own loopback.
  insecure,
}

class ServiceException implements Exception {
  const ServiceException(this.failure, this.message, {this.status});

  final Failure failure;

  /// For a person, as it will be shown.
  final String message;

  /// The HTTP status, when there was one.
  final int? status;

  @override
  String toString() => 'ServiceException($failure, $status): $message';
}

/// What signing in or a request is doing, so the same status can be read the right way: a 401 to a
/// password means the password, and a 401 to a token means the token.
enum Asking { signIn, signUp, withToken }

/// Turns a reply that is not a success into a [ServiceException].
ServiceException failureFor(int status, String body, Asking asking) {
  final said = _errorIn(body);
  switch (status) {
    case 401 when asking == Asking.withToken:
      return ServiceException(
        Failure.signedOut,
        'You have been signed out. Sign in again to see your statistics.',
        status: status,
      );
    case 401:
      return ServiceException(
        Failure.refused,
        said ?? 'That email address and password do not match an account.',
        status: status,
      );
    case 400 || 409 when asking != Asking.withToken:
      return ServiceException(Failure.refused, said ?? 'The service would not accept that.', status: status);
    case 429:
      return ServiceException(
        Failure.throttled,
        said ?? 'Too many attempts. Try again in a few minutes.',
        status: status,
      );
    case >= 500:
      return ServiceException(
        Failure.server,
        'The Noctorium service is having trouble ($status). Try again in a minute.',
        status: status,
      );
    default:
      return ServiceException(
        Failure.unreadable,
        said ?? 'The Noctorium service answered in a way this app does not understand ($status).',
        status: status,
      );
  }
}

/// Turns an exception from the network into a [ServiceException]; anything else is left alone.
ServiceException? failureFromError(Object error) {
  if (error is ServiceException) return error;
  if (error is TimeoutException) {
    return const ServiceException(
      Failure.offline,
      'The Noctorium service took too long to answer. Check this phone is online, then try again.',
    );
  }
  if (error is SocketException || error is http.ClientException || error is HttpException) {
    return const ServiceException(
      Failure.offline,
      'Cannot reach the Noctorium service. Check this phone is online, then try again.',
    );
  }
  if (error is HandshakeException || error is TlsException) {
    return const ServiceException(
      Failure.offline,
      'Could not make a secure connection to the Noctorium service. If this network signs you in through a '
      'web page, do that first.',
    );
  }
  if (error is FormatException) {
    return const ServiceException(
      Failure.unreadable,
      'Something between this phone and the Noctorium service answered instead of it. Try again in a minute.',
    );
  }
  return null;
}

String? _errorIn(String body) {
  try {
    final json = jsonDecode(body);
    if (json is Map<String, dynamic> && json['error'] is String && (json['error'] as String).trim().isNotEmpty) {
      return (json['error'] as String).trim();
    }
  } on FormatException {
    // Not JSON: an error page from something in between, which has nothing useful to say to a person.
  }
  return null;
}

class NoctoriumService {
  NoctoriumService({
    required String baseUrl,
    required this.client,
    this.userAgent = 'NoctoriumStats',
    this.timeout = const Duration(seconds: 20),
    this.loopbackHttp = false,
  }) : base = Uri.parse(baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl);

  final Uri base;

  /// Whether plain http to this phone's own loopback address is allowed, which only a debug build is
  /// given: see [secure].
  final bool loopbackHttp;
  final String userAgent;
  final Duration timeout;
  final http.Client client;

  /// Whether [base] may be talked to at all: over https, or over plain http to localhost when
  /// [loopbackHttp] allows it.
  ///
  /// The same rule as the debug build's network_security_config.xml, kept here as well because Dart's own
  /// HTTP client never reads that file: without this, a release built with an http address would send a
  /// password and a token in the clear without anything stopping it.
  bool get secure =>
      base.scheme == 'https' ||
      (loopbackHttp && base.scheme == 'http' && (base.host == 'localhost' || base.host == '127.0.0.1'));

  /// The website, for creating an account there or looking at the same figures in a browser.
  Uri get website => base.replace(path: '/');

  Uri endpoint(String path) => base.replace(path: '${base.path}$path');

  /// The statistics request for [range], counted on a clock [offset] from UTC.
  Uri statsUri(StatsRange range, {required Duration offset, int limit = 10}) =>
      endpoint('/api/stats').replace(queryParameters: {
        'range': range.query,
        // Whole minutes east of UTC, which is what the service reads, clamped as it clamps.
        'tz': offset.inMinutes.clamp(-840, 840).toString(),
        'limit': limit.clamp(1, 50).toString(),
      });

  Map<String, String> headers({String? token, bool json = false}) => {
        'Accept': 'application/json',
        'User-Agent': userAgent,
        if (json) 'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Session> signIn(String email, String password) =>
      _session('/api/auth/login', {'email': email.trim(), 'password': password}, Asking.signIn);

  Future<Session> createAccount(String email, String password, {String? displayName}) => _session(
        '/api/auth/signup',
        {
          'email': email.trim(),
          'password': password,
          if (displayName != null && displayName.trim().isNotEmpty) 'displayName': displayName.trim(),
        },
        Asking.signUp,
      );

  /// Who [token] belongs to; a [Failure.signedOut] when it no longer belongs to anybody.
  Future<Account> me(String token) async {
    final response = await _send(() => client.get(endpoint('/api/auth/me'), headers: headers(token: token)));
    if (response.statusCode != 200) throw failureFor(response.statusCode, response.body, Asking.withToken);
    final account = _decode(response.body, (json) => Account.fromJson(json['user']));
    if (account == null) throw failureFromError(const FormatException())!;
    return account;
  }

  Future<Stats> stats(String token, StatsRange range, {required Duration offset, int limit = 10}) async {
    final response = await _send(
      () => client.get(statsUri(range, offset: offset, limit: limit), headers: headers(token: token)),
    );
    if (response.statusCode != 200) throw failureFor(response.statusCode, response.body, Asking.withToken);
    try {
      return Stats.parse(response.body);
    } on FormatException catch (error) {
      throw failureFromError(error)!;
    }
  }

  Future<Session> _session(String path, Map<String, String> body, Asking asking) async {
    final response = await _send(
      () => client.post(endpoint(path), headers: headers(json: true), body: jsonEncode(body)),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw failureFor(response.statusCode, response.body, asking);
    }
    final session = _decode(response.body, (json) {
      final token = json['token'];
      final account = Account.fromJson(json['user']);
      return token is String && token.isNotEmpty && account != null ? Session(token: token, account: account) : null;
    });
    if (session == null) throw failureFromError(const FormatException())!;
    return session;
  }

  /// The service's reply as UTF-8 whatever its headers say, so a song title in Cyrillic arrives intact.
  Future<_Reply> _send(Future<http.Response> Function() request) async {
    if (!secure) {
      throw ServiceException(
        Failure.insecure,
        'This build only talks to the Noctorium service over https, and $base is not.',
      );
    }
    try {
      final response = await request().timeout(timeout);
      return _Reply(response.statusCode, utf8.decode(response.bodyBytes, allowMalformed: true));
    } catch (error) {
      throw failureFromError(error) ?? error;
    }
  }

  T? _decode<T>(String body, T? Function(Map<String, dynamic> json) read) {
    try {
      final json = jsonDecode(body);
      return json is Map<String, dynamic> ? read(json) : null;
    } on FormatException {
      return null;
    }
  }
}

class _Reply {
  const _Reply(this.statusCode, this.body);

  final int statusCode;
  final String body;
}
