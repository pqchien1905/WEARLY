import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nep_storefront/data/mock_account_details.dart';
import 'package:nep_storefront/app/account_details.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/data/mock_account.dart';

DeliveryAddress address(String label, {String? id}) => DeliveryAddress(
  id: id ?? '',
  label: label,
  recipient: 'Khách demo',
  phone: '0901234567',
  address: '12 Nguyễn Huệ, TP.HCM',
);

void main() {
  test('address CRUD keeps a valid default and immutable snapshots', () async {
    final repo = MockAccountDetailsRepository(latency: Duration.zero);
    final first = await repo.saveAddress(address('Nhà'));
    final firstId = first.addresses.single.id;
    expect(first.defaultAddressId, firstId);
    final second = await repo.saveAddress(address('Văn phòng'));
    expect(first.addresses.length, 1);
    expect(second.defaultAddressId, firstId);
    final secondId = second.addresses.last.id;
    await repo.setDefault(secondId);
    await repo.saveAddress(address('Nơi làm việc', id: secondId));
    final updated = await repo.read();
    expect(updated.defaultAddress!.label, 'Nơi làm việc');
    final deleted = await repo.deleteAddress(secondId);
    expect(deleted.defaultAddressId, firstId);
    final empty = await repo.deleteAddress(firstId);
    expect(empty.addresses, isEmpty);
    expect(empty.defaultAddress, isNull);
  });

  test('invalid, missing and sixth address cannot mutate data', () async {
    final repo = MockAccountDetailsRepository(latency: Duration.zero);
    await expectLater(
      repo.saveAddress(
        const DeliveryAddress(
          id: '',
          label: '',
          recipient: '',
          phone: '12',
          address: 'x',
        ),
      ),
      throwsArgumentError,
    );
    for (var i = 0; i < 5; i++) {
      await repo.saveAddress(address('Địa chỉ $i'));
    }
    await expectLater(repo.saveAddress(address('Thứ sáu')), throwsStateError);
    await expectLater(repo.setDefault('missing'), throwsStateError);
    await expectLater(
      repo.saveAddress(address('Missing', id: 'missing')),
      throwsStateError,
    );
    expect((await repo.read()).addresses.length, 5);
  });

  test('failed update leaves saved data intact and retry works', () async {
    final repo = MockAccountDetailsRepository(latency: Duration.zero);
    await repo.saveAddress(address('Nhà'));
    repo.offline = true;
    await expectLater(
      repo.saveStyle(const StylePreferences(size: 'L', style: 'Tối giản')),
      throwsStateError,
    );
    repo.offline = false;
    expect((await repo.read()).style.size, 'M');
    await repo.saveStyle(const StylePreferences(size: 'L', style: 'Tối giản'));
    expect((await repo.read()).style.size, 'L');
  });

  test('account change cannot receive a late address save', () async {
    final container = ProviderContainer(
      overrides: [
        accountRepositoryProvider.overrideWithValue(
          MockAccountRepository(latency: Duration.zero),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(accountProvider.notifier)
        .signIn('An', 'an@example.com', 'demo1234');
    await container.read(accountDetailsProvider.future);
    final save = container
        .read(accountDetailsProvider.notifier)
        .saveAddress(address('Nhà'));
    await container.read(accountProvider.notifier).signOut();
    await expectLater(save, throwsStateError);
    expect(
      (await container.read(accountDetailsProvider.future)).addresses,
      isEmpty,
    );
    await container
        .read(accountProvider.notifier)
        .signIn('Bình', 'binh@example.com', 'demo1234');
    expect(
      (await container.read(accountDetailsProvider.future)).addresses,
      isEmpty,
    );
  });
}
