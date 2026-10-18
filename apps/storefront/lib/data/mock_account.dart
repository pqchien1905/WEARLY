import '../domain/account.dart';

class MockAccountRepository implements AccountRepository {
  MockAccountRepository({this.latency = const Duration(milliseconds: 450)});
  final Duration latency;
  bool offline = false;
  Future<void> _wait() async {
    await Future<void>.delayed(latency);
    if (offline) {
      throw StateError(
        'Không kết nối được tài khoản demo. Tắt mô phỏng lỗi rồi thử lại.',
      );
    }
  }

  bool _emailValid(String value) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim());
  @override
  Future<UserProfile> signIn({
    required String name,
    required String email,
    required String password,
    bool register = false,
  }) async {
    if (name.trim().isEmpty || !_emailValid(email) || password.length < 8) {
      throw ArgumentError(
        'Kiểm tra tên, email và mật khẩu demo ít nhất 8 ký tự.',
      );
    }
    await _wait();
    // Credentials are neither persisted nor authenticated in demo mode.
    return UserProfile(name: name.trim(), email: email.trim());
  }

  @override
  Future<UserProfile> save(UserProfile profile) async {
    if (profile.name.trim().isEmpty || !_emailValid(profile.email)) {
      throw ArgumentError('Tên và email chưa hợp lệ.');
    }
    await _wait();
    return profile;
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    if (!_emailValid(email)) throw ArgumentError('Email chưa hợp lệ.');
    await _wait();
  }

  @override
  Future<void> signOut() async {}
}
