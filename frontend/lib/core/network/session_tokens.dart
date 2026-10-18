/// Session-only token storage on every platform. Browser storage is never used.
/// Persistent native sign-in requires an OS keychain adapter before enabling it.
class SessionTokens {
  String? _accessToken, _refreshToken;
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  void set({required String accessToken, required String refreshToken}) {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
  }

  void clear() {
    _accessToken = null;
    _refreshToken = null;
  }
}
