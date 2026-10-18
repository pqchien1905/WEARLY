import '../core/network/api_client.dart';
import '../domain/account.dart';

UserProfile userFromJson(Object? value) {
  final user = value as Map<String, dynamic>;
  return UserProfile(
    id: user['id'] as String,
    name: user['name'] as String,
    email: user['email'] as String,
    phone: user['phone'] as String? ?? '',
    role: user['role'] as String,
  );
}

class RemoteAccountRepository implements AccountRepository {
  RemoteAccountRepository(this.api);
  final ApiClient api;
  int _operation = 0;
  void dispose() {
    _operation++;
  }

  @override
  Future<UserProfile> signIn({
    required String name,
    required String email,
    required String password,
    bool register = false,
  }) async {
    final operation = ++_operation;
    final generation = api.tokens.generation;
    final value =
        await api.request(
              'POST',
              register ? 'auth/register' : 'auth/login',
              authenticated: false,
              body: {
                if (register) 'name': name.trim(),
                'email': email.trim(),
                'password': password,
              },
            )
            as Map<String, dynamic>;
    final profile = userFromJson(value['user']);
    if (operation != _operation || api.tokens.generation != generation)
      throw sessionChanged;
    api.tokens.set(
      accessToken: value['accessToken'] as String,
      refreshToken: value['refreshToken'] as String,
    );
    return profile;
  }

  @override
  Future<UserProfile> save(UserProfile profile) async => userFromJson(
    await api.request(
      'PATCH',
      'users/me',
      body: {'name': profile.name.trim(), 'phone': profile.phone.trim()},
    ),
  );

  @override
  Future<void> requestPasswordReset(String email) async {
    throw const ApiException(
      'NOT_AVAILABLE',
      'Khôi phục mật khẩu chưa được kết nối. Vui lòng liên hệ cửa hàng.',
    );
  }

  @override
  Future<void> signOut() async {
    _operation++;
    final access = api.tokens.accessToken;
    api.tokens.clear();
    if (access != null) {
      await api.request(
        'POST',
        'auth/logout',
        authenticated: false,
        headers: {'Authorization': 'Bearer $access'},
      );
    }
  }
}
