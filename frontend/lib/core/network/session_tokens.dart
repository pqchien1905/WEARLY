import 'package:flutter/foundation.dart';

/// Session-only token storage on every platform. Browser storage is never used.
/// Persistent native sign-in requires an OS keychain adapter before enabling it.
class SessionTokens extends ChangeNotifier {
  String? _accessToken, _refreshToken;
  int _generation = 0;
  int get generation => _generation;
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  void set({required String accessToken, required String refreshToken}) {
    _generation++;
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    notifyListeners();
  }

  bool rotate({
    required int generation,
    required String accessToken,
    required String refreshToken,
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
    notifyListeners();
  }
}
