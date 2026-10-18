class UserProfile {
  const UserProfile({
    required this.name,
    required this.email,
    this.phone = '',
    this.address = '',
    this.id = '',
    this.role = 'CUSTOMER',
  });
  final String name, email, phone, address, id, role;
}

abstract interface class AccountRepository {
  Future<UserProfile> signIn({
    required String name,
    required String email,
    required String password,
    bool register = false,
  });
  Future<UserProfile> save(UserProfile profile);
  Future<void> requestPasswordReset(String email);
  Future<void> signOut();
}
