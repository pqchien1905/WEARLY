import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/account_details.dart';
import '../data/mock_account_details.dart';
import '../data/remote_account_details.dart';
import 'api_providers.dart';
import 'account_state.dart';
export '../domain/account_details.dart';

// Recreate the local cache for each identity. Remote data remains on the server.
final accountDetailsRepositoryProvider = Provider<AccountDetailsRepository>((
  ref,
) {
  ref.watch(accountProvider.select((user) => user?.email));
  if (ref.watch(remoteApiProvider)) {
    return RemoteAccountDetailsRepository(ref.watch(apiClientProvider));
  }
  return MockAccountDetailsRepository();
});

final accountDetailsProvider =
    AsyncNotifierProvider<AccountDetailsController, AccountDetails>(
      AccountDetailsController.new,
    );

class AccountDetailsController extends AsyncNotifier<AccountDetails> {
  int _generation = 0;
  @override
  Future<AccountDetails> build() async {
    _generation++;
    final email = ref.watch(accountProvider.select((user) => user?.email));
    final repo = ref.watch(accountDetailsRepositoryProvider);
    return email == null ? AccountDetails() : repo.read();
  }

  Future<void> _write(
    Future<AccountDetails> Function(AccountDetailsRepository) action,
  ) async {
    final identity = ref.read(accountProvider)?.email;
    if (identity == null) {
      throw StateError('Đăng nhập trước khi lưu thay đổi.');
    }
    final generation = _generation;
    final repo = ref.read(accountDetailsRepositoryProvider);
    final result = await action(repo);
    if (ref.mounted &&
        generation == _generation &&
        ref.read(accountProvider)?.email == identity &&
        identical(repo, ref.read(accountDetailsRepositoryProvider))) {
      state = AsyncData(result);
    } else {
      throw StateError('Phiên tài khoản đã thay đổi. Vui lòng mở lại hồ sơ.');
    }
  }

  Future<void> saveAddress(DeliveryAddress address) =>
      _write((r) => r.saveAddress(address));
  Future<void> deleteAddress(String id) => _write((r) => r.deleteAddress(id));
  Future<void> setDefault(String id) => _write((r) => r.setDefault(id));
  Future<void> saveStyle(StylePreferences preferences) =>
      _write((r) => r.saveStyle(preferences));
}
