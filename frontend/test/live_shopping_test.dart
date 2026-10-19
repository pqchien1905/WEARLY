import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/data/remote_account.dart';
import 'package:nep_storefront/data/remote_account_details.dart';
import 'package:nep_storefront/data/remote_commerce.dart';
import 'package:nep_storefront/domain/account.dart';
import 'package:nep_storefront/domain/account_details.dart';
import 'package:nep_storefront/domain/commerce.dart';

// Drop one response only AFTER the real API committed its address creation.
class LostAddressResponseClient extends http.BaseClient {
  final inner = http.Client();
  bool dropped = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await inner.send(request);
    if (!dropped &&
        request.method == 'POST' &&
        request.url.path.endsWith('/addresses') &&
        response.statusCode == 201) {
      dropped = true;
      await response.stream.drain<void>();
      throw http.ClientException('Simulated lost response after server commit');
    }
    return response;
  }

  @override
  void close() => inner.close();
}

void main() {
  const url = String.fromEnvironment('LIVE_SHOPPING_API_URL');
  const fixture = String.fromEnvironment('LIVE_SHOPPING_FIXTURE');
  test(
    'real PostgreSQL persists profile, addresses, cart and COD history across login',
    () async {
      expect(fixture, startsWith('flutter-test-'));
      final api = ApiClient(baseUrl: url, client: LostAddressResponseClient());
      addTearDown(api.close);
      final accounts = RemoteAccountRepository(api);
      final email = '$fixture@example.com';
      const password = 'Integration-only-Password-2026';
      final user = await accounts.signIn(
        name: 'Nguyễn Kiểm Thử',
        email: email,
        password: password,
        register: true,
      );
      final saved = await accounts.save(
        UserProfile(
          id: user.id,
          name: 'Nguyễn Đã Lưu',
          email: email,
          phone: '0901234567',
        ),
      );
      expect(saved.name, 'Nguyễn Đã Lưu');
      expect(saved.phone, '0901234567');
      final addresses = RemoteAccountDetailsRepository(api);
      const addressDraft = DeliveryAddress(
        id: '',
        label: 'Nhà',
        recipient: 'Nguyễn Đã Lưu',
        phone: '0901234567',
        address: '12 Nguyễn Huệ, TP.HCM',
      );
      final creationKey = newAddressCreationKey();
      await expectLater(
        addresses.saveAddress(addressDraft, creationKey: creationKey),
        throwsA(isA<ApiException>()),
      );
      var details = await addresses.saveAddress(
        addressDraft,
        creationKey: creationKey,
      );
      expect(details.addresses, hasLength(1));
      final addressId = details.defaultAddressId!;
      details = await addresses.saveAddress(
        DeliveryAddress(
          id: addressId,
          label: 'Nhà riêng',
          recipient: 'Nguyễn Đã Lưu',
          phone: '0901234567',
          address: '14 Nguyễn Huệ, TP.HCM',
        ),
      );
      expect(details.addresses.single.address, '14 Nguyễn Huệ, TP.HCM');
      final cart = RemoteCartRepository(api);
      await cart.add(fixture, fixture, 2);
      await cart.update(fixture, 1);
      expect(cart.subtotal, 490000);
      await accounts.signOut();
      final fresh = ApiClient(baseUrl: url);
      addTearDown(fresh.close);
      final freshAccounts = RemoteAccountRepository(fresh);
      final restored = await freshAccounts.signIn(
        name: '',
        email: email,
        password: password,
      );
      expect(restored.name, 'Nguyễn Đã Lưu');
      final restoredAddresses = await RemoteAccountDetailsRepository(
        fresh,
      ).read();
      expect(restoredAddresses.defaultAddressId, addressId);
      final freshCart = RemoteCartRepository(fresh);
      await freshCart.refresh();
      expect(freshCart.items.single.quantity, 1);
      final orders = RemoteOrderRepository(fresh, freshCart, email: email);
      final order = await orders.checkout(
        CheckoutDraft(
          name: restored.name,
          email: email,
          phone: restored.phone,
          address: restoredAddresses.addresses.single.address,
          addressId: addressId,
          payment: 'COD',
        ),
      );
      expect(order.total, 520000);
      expect(order.draft.payment, 'COD · Chưa thu tiền');
      expect(order.status, 'Chờ xác nhận');
      expect(freshCart.items, isEmpty);
      await orders.refresh();
      expect(orders.orders.single.id, order.id);
      await orders.loadOrder(order.id);
      expect(orders.orders.single.draft.address, '14 Nguyễn Huệ, TP.HCM');
      await orders.setStatus(order.id, 'Đã hủy');
      expect(orders.orders.single.status, 'Đã hủy');
      await orders.setStatus(order.id, 'Đã hủy');
      final detail = await fresh.get('products/$fixture') as Map;
      expect((detail['variants'] as List).single['available'], 10);
      await freshAccounts.signOut();
      await freshAccounts.signIn(name: '', email: email, password: password);
      final finalOrders = RemoteOrderRepository(
        fresh,
        RemoteCartRepository(fresh),
        email: email,
      );
      await finalOrders.refresh();
      expect(finalOrders.orders.single.status, 'Đã hủy');
      await RemoteAccountDetailsRepository(fresh).deleteAddress(addressId);
      expect(
        (await RemoteAccountDetailsRepository(fresh).read()).addresses,
        isEmpty,
      );
      await freshAccounts.signOut();
      expect(fresh.tokens.accessToken, isNull);
    },
    skip: url.isEmpty
        ? 'Run node tools/test-frontend-api.cjs with the dedicated test database.'
        : false,
  );
}
