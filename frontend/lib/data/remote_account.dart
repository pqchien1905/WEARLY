import '../core/network/api_client.dart';
import '../domain/account.dart';
import '../domain/staff_permissions.dart';

UserProfile userFromJson(Object? value) {
  final user = value as Map<String, dynamic>;
  return UserProfile(
    id: user['id'] as String,
    name: user['name'] as String,
    email: user['email'] as String,
    username: user['username'] as String? ?? '',
    phone: user['phone'] as String? ?? '',
    role: user['role'] as String,
  );
}

class RemoteAccountRepository implements AccountRepository {
  RemoteAccountRepository(this.api, {this.admin = false});
  final ApiClient api;
  final bool admin;
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
    if (admin && register) {
      throw const ApiException(
        'FORBIDDEN',
        'Tài khoản quản trị cần được cấp quyền bởi cửa hàng.',
      );
    }
    final operation = ++_operation;
    final generation = api.tokens.generation;
    final body = {
      if (register) 'name': name.trim(),
      if (admin)
        'username': email.trim().toLowerCase()
      else
        'email': email.trim(),
      'password': password,
    };
    final value =
        (api.browserScope != null
                ? await api.browserAuth(
                    register ? 'register' : 'login',
                    body: body,
                    isCurrent: () =>
                        operation == _operation &&
                        api.tokens.generation == generation,
                  )
                : await api.request(
                    'POST',
                    admin
                        ? 'auth/admin/login'
                        : register
                        ? 'auth/register'
                        : 'auth/login',
                    authenticated: false,
                    body: body,
                  ))
            as Map<String, dynamic>;
    final profile = userFromJson(value['user']);
    if (operation != _operation || api.tokens.generation != generation) {
      throw sessionChanged;
    }
    if (admin && !isStaff(profile.role)) {
      throw const ApiException(
        'FORBIDDEN',
        'Tài khoản này chưa có quyền quản trị.',
      );
    }
    api.tokens.set(
      accessToken: value['accessToken'] as String,
      refreshToken: value['refreshToken'] as String?,
      userId: profile.id,
    );
    return profile;
  }

  Future<UserProfile?> restore() async {
    if (api.browserScope == null) return null;
    final operation = ++_operation, generation = api.tokens.generation;
    try {
      final data = await api.browserAuth('refresh') as Map<String, dynamic>;
      if (operation != _operation || api.tokens.generation != generation) {
        throw sessionChanged;
      }
      final profile = userFromJson(data['user']);
      if (admin && !isStaff(profile.role)) throw sessionChanged;
      api.tokens.set(
        accessToken: data['accessToken'] as String,
        userId: profile.id,
      );
      return profile;
    } on ApiException catch (error) {
      if (operation != _operation || api.tokens.generation != generation) {
        throw sessionChanged;
      }
      if (error.status == 401) {
        api.tokens.clear();
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<UserProfile> save(UserProfile profile) async => userFromJson(
    await api.request(
      'PATCH',
      'users/me',
      body: {'name': profile.name.trim(), 'phone': profile.phone.trim()},
    ),
  );

  Future<UserProfile> readProfile() async =>
      userFromJson(await api.get('users/me'));

  @override
  Future<void> requestPasswordReset(String email) async {
    await api.request(
      'POST',
      'auth/forgot-password',
      authenticated: false,
      body: {'email': email.trim()},
    );
  }

  /// Signed-in change; the server keeps this session and signs out others.
  Future<void> changePassword(String current, String next) async {
    await api.request(
      'POST',
      'auth/change-password',
      body: {'currentPassword': current, 'newPassword': next},
    );
  }

  @override
  Future<void> signOut() async {
    final operation = ++_operation;
    if (api.browserScope != null) {
      await api.browserAuth('logout');
      if (operation == _operation) api.tokens.clear();
      return;
    }
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
