import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/account.dart';
import '../data/mock_account.dart';
export '../domain/account.dart';

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => MockAccountRepository(),
);

final accountProvider = NotifierProvider<AccountController, UserProfile?>(
  AccountController.new,
);

class AccountController extends Notifier<UserProfile?> {
  int _generation = 0;
  @override
  UserProfile? build() {
    // Riverpod may retain this notifier across invalidation. A reset must
    // invalidate requests started by the previous account state too.
    _generation++;
    return null;
  }

  Future<void> signIn(
    String name,
    String email,
    String password, {
    bool register = false,
  }) async {
    final token = ++_generation;
    final profile = await ref
        .read(accountRepositoryProvider)
        .signIn(
          name: name,
          email: email,
          password: password,
          register: register,
        );
    if (ref.mounted && token == _generation) state = profile;
  }

  Future<void> save(UserProfile profile) async {
    final token = ++_generation;
    final saved = await ref.read(accountRepositoryProvider).save(profile);
    if (ref.mounted && token == _generation) state = saved;
  }

  Future<void> requestPasswordReset(String email) =>
      ref.read(accountRepositoryProvider).requestPasswordReset(email);
  Future<void> signOut() async {
    ++_generation;
    state = null;
    await ref.read(accountRepositoryProvider).signOut();
  }
}
