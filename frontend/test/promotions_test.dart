import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/features/admin/remote/promotions_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/data/commerce_json.dart';
import 'package:nep_storefront/data/remote_commerce.dart';
import 'package:nep_storefront/data/remote_promotions.dart';
import 'package:nep_storefront/domain/commerce.dart';
import 'remote_commerce_test.dart' show orderJson, cartJson, draft;
import 'remote_session_test.dart' show jsonResponse;
import 'remote_account_test.dart' show sessionJson;

void main() {
  testWidgets(
    'checkout applies a server quote and clears it when shipping changes',
    (tester) async {
      var previews = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          final path = r.url.path;
          if (path.endsWith('/auth/login')) return jsonResponse(sessionJson());
          if (path.endsWith('/cart')) return jsonResponse(cartJson());
          if (path.endsWith('/orders')) {
            return jsonResponse({
              'items': [],
              'total': 0,
              'page': 1,
              'limit': 100,
            });
          }
          if (path.endsWith('/addresses')) return jsonResponse([]);
          if (path.endsWith('/methods')) {
            return jsonResponse({'cod': true, 'vnpay': false, 'sandbox': true});
          }
          if (path.endsWith('/preview')) {
            previews++;
            return jsonResponse({
              'code': 'SAVE50',
              'subtotal': '490000',
              'shipping': '30000',
              'discount': '50000',
              'total': '470000',
              'cartVersion': 1,
            });
          }
          return jsonResponse({}, 404);
        }),
      );
      final container = ProviderContainer(
        overrides: [
          remoteApiProvider.overrideWithValue(true),
          apiClientProvider.overrideWithValue(api),
          sessionTokensProvider.overrideWithValue(api.tokens),
        ],
      );
      addTearDown(() {
        container.dispose();
        api.close();
      });
      final router = createRouter(initialLocation: '/checkout');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: NepApp(router: router),
        ),
      );
      await tester.pumpAndSettle();
      await container
          .read(accountProvider.notifier)
          .signIn('', 'an@example.com', 'example-password');
      await tester.pumpAndSettle();
      final code = find.widgetWithText(TextFormField, 'Mã khuyến mãi');
      await tester.ensureVisible(code);
      await tester.enterText(code, 'SAVE50');
      await tester.pump();
      await tester.ensureVisible(find.text('Áp dụng'));
      await tester.tap(find.text('Áp dụng'));
      await tester.pumpAndSettle();
      expect(previews, 1);
      expect(find.text('Khuyến mãi SAVE50'), findsOneWidget);
      expect(find.text('470.000 ₫'), findsOneWidget);
      await tester.ensureVisible(find.text('Giao nhanh'));
      await tester.tap(find.text('Giao nhanh'));
      await tester.pumpAndSettle();
      expect(find.text('Khuyến mãi SAVE50'), findsNothing);
      expect(find.text('540.000 ₫'), findsOneWidget);
    },
  );
  testWidgets(
    'admin promotion editor validates limits and reloads a version conflict',
    (tester) async {
      var reads = 0, writes = 0;
      Map<String, dynamic>? body;
      final row = {
        'id': 'promo-1',
        'code': 'SAVE50',
        'kind': 'FIXED',
        'amount': '50000',
        'active': true,
        'minSubtotal': '0',
        'maxDiscount': null,
        'usageLimit': 5,
        'perUserLimit': 1,
        'startsAt': '2026-12-01T12:30:05.123Z',
        'expiresAt': '2026-12-01T12:30:45.987Z',
        'version': 3,
        '_count': {'redemptions': 1},
      };
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          if (r.url.path.endsWith('/login')) {
            final session = sessionJson();
            (session['user'] as Map)['role'] = 'ADMIN';
            return jsonResponse(session);
          }
          if (r.method == 'PATCH') {
            writes++;
            body = jsonDecode(r.body);
            return jsonResponse({
              'error': {
                'code': 'VERSION_CONFLICT',
                'message': 'Mã đã thay đổi',
              },
            }, 409);
          }
          reads++;
          return jsonResponse({
            'items': [row],
            'total': 1,
            'page': 1,
            'limit': 10,
          });
        }),
      );
      addTearDown(api.close);
      final container = ProviderContainer(
        overrides: [
          remoteApiProvider.overrideWithValue(true),
          adminApiClientProvider.overrideWithValue(api),
          adminSessionTokensProvider.overrideWithValue(api.tokens),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(adminAccountProvider.notifier)
          .signIn('', 'admin@example.com', 'example-password');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: RemotePromotionsPage()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Chỉnh sửa SAVE50'));
      await tester.tap(find.byTooltip('Chỉnh sửa SAVE50'));
      await tester.pumpAndSettle();
      final limit = find.widgetWithText(TextFormField, 'Lượt tối đa mỗi khách');
      await tester.ensureVisible(limit);
      await tester.enterText(limit, '0');
      await tester.tap(find.text('Lưu thay đổi'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      await tester.enterText(limit, '2');
      await tester.tap(find.text('Lưu thay đổi'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(body!['expectedVersion'], 3);
      expect(body!['perUserLimit'], 2);
      expect(body!['startsAt'], row['startsAt']);
      expect(body!['expiresAt'], row['expiresAt']);
      expect(
        find.text(
          'Dữ liệu đã thay đổi hoặc số lượng không còn hợp lệ. Tải lại trước khi thao tác tiếp.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Tải lại dữ liệu'));
      await tester.pumpAndSettle();
      expect(reads, greaterThan(1));
    },
  );
  test(
    'discount snapshots determine historical totals and zero-total order needs no payment',
    () {
      final json = orderJson()
        ..['discount'] = '50000'
        ..['couponCode'] = 'SAVE50'
        ..['total'] = '470000';
      final order = commerceOrder(json, email: '');
      expect(order.total, 470000);
      expect(order.discount, 50000);
      expect(order.couponCode, 'SAVE50');
      expect(order.withStatus('Đã hủy').total, 470000);
      json['discount'] = '490001';
      expect(
        () => commerceOrder(json, email: ''),
        throwsA(isA<ApiException>()),
      );
      json['discount'] = '490000';
      json['shipping'] = '0';
      json['total'] = '0';
      json['payment'] = {'provider': 'free', 'status': 'PAID', 'amount': '0'};
      expect(
        commerceOrder(json, email: '').draft.payment,
        'Không cần thanh toán',
      );
    },
  );
  test(
    'uncertain checkout retains the original coupon and exact discount',
    () async {
      final bodies = <String>[];
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          if (r.method == 'POST') {
            bodies.add(r.body);
            if (bodies.length == 1) throw http.ClientException('lost');
            return jsonResponse(
              orderJson()
                ..['discount'] = '50000'
                ..['couponCode'] = 'SAVE50'
                ..['total'] = '470000',
              201,
            );
          }
          return jsonResponse(cartJson());
        }),
      );
      addTearDown(api.close);
      final cart = RemoteCartRepository(api);
      final orders = RemoteOrderRepository(api, cart, autoRetries: 0);
      await cart.refresh();
      const coupon = CheckoutDraft(
        name: 'An',
        email: 'an@example.com',
        phone: '0901234567',
        address: 'Test address',
        addressId: 'address-1',
        couponCode: 'SAVE50',
        discount: 50000,
      );
      await expectLater(orders.checkout(coupon), throwsA(isA<ApiException>()));
      expect(orders.pendingCheckout!.draft.discount, 50000);
      await orders.checkout(draft);
      expect(bodies.first, bodies.last);
      expect(jsonDecode(bodies.first)['couponCode'], 'SAVE50');
      expect(jsonDecode(bodies.first)['expectedDiscount'], '50000');
    },
  );
  test('preview uses cart version and rejects inconsistent totals', () async {
    var invalid = false;
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient((r) async {
        expect(jsonDecode(r.body), {
          'code': 'SAVE50',
          'shippingMethod': 'standard',
          'cartVersion': 3,
        });
        return jsonResponse({
          'code': 'SAVE50',
          'subtotal': '490000',
          'shipping': '30000',
          'discount': '50000',
          'total': invalid ? '1' : '470000',
          'cartVersion': 3,
        });
      }),
    );
    addTearDown(api.close);
    final repo = RemotePromotionRepository(api);
    expect(
      (await repo.preview(' save50 ', express: false, cartVersion: 3)).total,
      470000,
    );
    invalid = true;
    await expectLater(
      repo.preview('SAVE50', express: false, cartVersion: 3),
      throwsA(isA<ApiException>()),
    );
  });
}
