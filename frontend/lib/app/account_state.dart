import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/account.dart';
import '../data/mock_account.dart';
import '../data/remote_account.dart';
import 'api_providers.dart';
export '../domain/account.dart';

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  if (!ref.watch(remoteApiProvider)) return MockAccountRepository();
  final repository = RemoteAccountRepository(ref.watch(apiClientProvider));
  ref.onDispose(repository.dispose);
  return repository;
});

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
    if (ref.watch(remoteApiProvider)) {
      final tokens = ref.watch(sessionTokensProvider);
      tokens.clear();
      void changed() {
        if (ref.mounted && tokens.accessToken == null) {
          _generation++;
          state = null;
        }
      }

      tokens.addListener(changed);
      ref.onDispose(() => tokens.removeListener(changed));
    }
    return null;
  }

  Future<void> signIn(
    String name,
    String email,
    String password, {
    bool register = false,
  }) async {
    if (ref.read(remoteApiProvider)) ref.read(sessionTokensProvider).clear();
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
