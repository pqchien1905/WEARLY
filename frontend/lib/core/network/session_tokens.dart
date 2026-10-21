import 'package:flutter/foundation.dart';

/// Access tokens stay in memory. Browser refresh credentials are HttpOnly cookies.
/// Persistent native sign-in requires an OS keychain adapter before enabling it.
class SessionTokens extends ChangeNotifier {
  String? _accessToken, _refreshToken, _userId;
  int _generation = 0;
  int get generation => _generation;
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  String? get userId => _userId;
  void set({
    required String accessToken,
    String? refreshToken,
    String? userId,
  }) {
    _generation++;
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _userId = userId;
    notifyListeners();
  }

  bool rotate({
    required int generation,
    required String accessToken,
    String? refreshToken,
  }) {
    if (generation != _generation) return false;
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    return true;
  }

  void clear() {
    _generation++;
    _accessToken = null;
    _refreshToken = null;
    _userId = null;
    notifyListeners();
  }
}
