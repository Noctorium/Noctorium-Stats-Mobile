/// What the app keeps between launches: the sign-in token, somewhere safe, and the range last looked at,
/// somewhere ordinary.
///
/// Both behind small interfaces, so the tests can hand the app a memory instead of Android's keystore.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'stats.dart';

abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

/// The token in Android's keystore-backed storage. It is the whole of a sign-in -- anybody holding it can
/// read this listener's history for 90 days -- so it never goes anywhere a backup or another app can see.
class SecureTokenStore implements TokenStore {
  const SecureTokenStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;
  static const _key = 'noctorium.token';

  @override
  Future<String?> read() async {
    try {
      final token = await _storage.read(key: _key);
      return token == null || token.isEmpty ? null : token;
    } catch (_) {
      // A keystore that cannot be read -- after a restore onto another phone, say -- is a sign-in that has
      // to happen again, not a crash.
      return null;
    }
  }

  @override
  Future<void> write(String token) async {
    try {
      await _storage.write(key: _key, value: token);
    } catch (_) {
      // Signed in all the same, for as long as the app is open; the next launch asks again. Better than
      // refusing a sign-in that worked because the keystore would not hold it.
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // Nothing there to delete is the state being asked for.
    }
  }
}

class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this.token]);

  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String token) async => this.token = token;

  @override
  Future<void> clear() async => token = null;
}

abstract class Preferences {
  Future<StatsRange?> lastRange();
  Future<void> rememberRange(StatsRange range);
}

class SharedPreferencesStore implements Preferences {
  static const _range = 'range';

  @override
  Future<StatsRange?> lastRange() async {
    try {
      return StatsRange.fromQuery((await SharedPreferences.getInstance()).getString(_range));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> rememberRange(StatsRange range) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_range, range.query);
    } catch (_) {
      // Forgetting which chip was chosen is not worth telling anybody about.
    }
  }
}

class MemoryPreferences implements Preferences {
  MemoryPreferences([this.range]);

  StatsRange? range;

  @override
  Future<StatsRange?> lastRange() async => range;

  @override
  Future<void> rememberRange(StatsRange range) async => this.range = range;
}
