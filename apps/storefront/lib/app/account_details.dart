import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/account_details.dart';
import '../data/mock_account_details.dart';
import 'account_state.dart';
export '../domain/account_details.dart';

// A fresh, ephemeral repository per signed-in identity. Sign-out/reset discards
// all addresses/preferences; no personal data is written to browser storage.
final accountDetailsRepositoryProvider = Provider<AccountDetailsRepository>((
  ref,
) {
  ref.watch(accountProvider.select((user) => user?.email));
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
      throw StateError('Mở phiên tài khoản demo trước khi lưu.');
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
