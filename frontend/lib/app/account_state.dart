import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/account.dart';
import '../data/mock_account.dart';
import '../data/remote_account.dart';
import '../core/network/session_tokens.dart';
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

final adminAccountRepositoryProvider = Provider<AccountRepository>((ref) {
  final repository = RemoteAccountRepository(
    ref.watch(adminApiClientProvider),
    admin: true,
  );
  ref.onDispose(repository.dispose);
  return repository;
});
final adminAccountProvider = NotifierProvider<AccountController, UserProfile?>(
  () => AccountController(admin: true),
);

final browserSessionBootstrapProvider = FutureProvider<void>((ref) async {
  // Defer notifier changes until the provider/widget construction has finished.
  await Future<void>.delayed(Duration.zero);
  if (!ref.mounted) return;
  await Future.wait([
    ref.read(accountProvider.notifier).restore(),
    ref.read(adminAccountProvider.notifier).restore(),
  ]);
});

class AccountController extends Notifier<UserProfile?> {
  AccountController({this.admin = false});
  final bool admin;
  Provider<AccountRepository> get _repository =>
      admin ? adminAccountRepositoryProvider : accountRepositoryProvider;
  Provider<SessionTokens> get _tokens =>
      admin ? adminSessionTokensProvider : sessionTokensProvider;
  int _generation = 0;
  @override
  UserProfile? build() {
    // Riverpod may retain this notifier across invalidation. A reset must
    // invalidate requests started by the previous account state too.
    _generation++;
    if (ref.watch(remoteApiProvider)) {
      final tokens = ref.watch(_tokens);
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
    if (ref.read(remoteApiProvider)) ref.read(_tokens).clear();
    final token = ++_generation;
    final profile = await ref
        .read(_repository)
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
    final saved = await ref.read(_repository).save(profile);
    if (ref.mounted && token == _generation) state = saved;
  }

  Future<void> restore() async {
    final repository = ref.read(_repository);
    if (repository is! RemoteAccountRepository ||
        repository.api.browserScope == null) {
      return;
    }
    final generation = ++_generation;
    final profile = await repository.restore();
    if (ref.mounted && generation == _generation) state = profile;
  }

  Future<void> requestPasswordReset(String email) =>
      ref.read(_repository).requestPasswordReset(email);
  Future<void> signOut() async {
    final generation = ++_generation;
    final repository = ref.read(_repository);
    final browser =
        repository is RemoteAccountRepository &&
        repository.api.browserScope != null;
    if (!browser) state = null;
    await repository.signOut();
    if (ref.mounted && generation == _generation) state = null;
  }
}
