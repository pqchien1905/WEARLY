import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/app/api_providers.dart';
import 'package:nep_storefront/app/payment_providers.dart';
import 'package:nep_storefront/core/network/api_client.dart';
import 'package:nep_storefront/data/commerce_json.dart';
import 'package:nep_storefront/data/remote_payments.dart';
import 'package:nep_storefront/features/checkout/payment_panel.dart';
import 'remote_commerce_test.dart' show orderJson;
import 'remote_session_test.dart' show jsonResponse;

Map<String, Object?> state({
  String status = 'PENDING',
  String? url =
      'https://sandbox.vnpayment.vn/paymentv2/vpcpay.html?vnp_TxnRef=test',
}) => {
  'orderId': 'order-1',
  'paymentStatus': status,
  'sandbox': true,
  'reviewRequired': false,
  'attempt': {
    'reference': 'test',
    'status': status,
    'expiresAt': '2026-10-21T12:00:00Z',
    'reviewRequired': false,
  },
  'checkoutUrl': url,
};
void main() {
  test(
    'payment repository refuses unexpected gateways, statuses and real-money mode',
    () async {
      for (final patch in [
        {'checkoutUrl': 'https://evil.example/payment'},
        {'checkoutUrl': 'http://sandbox.vnpayment.vn/paymentv2/vpcpay.html'},
        {
          'checkoutUrl':
              'https://sandbox.vnpayment.vn:8443/paymentv2/vpcpay.html',
        },
        {'sandbox': false},
        {'paymentStatus': 'unknown'},
      ]) {
        final api = ApiClient(
          baseUrl: 'http://localhost/api/v1',
          client: MockClient((_) async => jsonResponse({...state(), ...patch})),
        );
        addTearDown(api.close);
        await expectLater(
          RemotePaymentRepository(api).start('order-1'),
          throwsA(isA<ApiException>()),
        );
      }
    },
  );
  testWidgets(
    'payment panel opens verified sandbox link and refreshes canonical order after query',
    (tester) async {
      var refreshes = 0;
      Uri? opened;
      final paths = <String>[];
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((r) async {
          paths.add(r.url.path);
          return jsonResponse(
            r.url.path.endsWith('/reconcile')
                ? state(status: 'PAID', url: null)
                : state(),
          );
        }),
      );
      addTearDown(api.close);
      final order = commerceOrder(
        orderJson()..['payment'] = {'provider': 'vnpay', 'status': 'PENDING'},
        email: '',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(api),
            paymentLauncherProvider.overrideWithValue((uri) => opened = uri),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PaymentPanel(
                  order: order,
                  autoCheck: false,
                  onRefresh: () async {
                    refreshes++;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Chờ thanh toán'), findsOneWidget);
      // One action starts the payment and leaves for the gateway.
      await tester.tap(find.text('Thanh toán ngay'));
      await tester.pumpAndSettle();
      expect(opened?.host, 'sandbox.vnpayment.vn');
      await tester.tap(find.text('Kiểm tra kết quả'));
      await tester.pumpAndSettle();
      expect(paths.last, endsWith('/reconcile'));
      expect(refreshes, 1);
      expect(find.text('Đã thanh toán'), findsOneWidget);
      expect(find.text('Thanh toán ngay'), findsNothing);
    },
  );
  test(
    'wallet payment links must belong to the order provider sandbox',
    () async {
      Future<PaymentState> start(Map<String, Object?> body) {
        final api = ApiClient(
          baseUrl: 'http://localhost/api/v1',
          client: MockClient((_) async => jsonResponse(body)),
        );
        addTearDown(api.close);
        return RemotePaymentRepository(api).start('order-1');
      }

      final momo = await start({
        ...state(url: 'https://test-payment.momo.vn/v2/gateway/pay?t=abc'),
        'provider': 'momo',
      });
      expect(momo.provider, 'momo');
      expect(momo.checkoutUrl?.host, 'test-payment.momo.vn');
      final zalo = await start({
        ...state(url: 'https://qcgateway.zalopay.vn/openinapp?order=1'),
        'provider': 'zalopay',
      });
      expect(zalo.checkoutUrl?.host, 'qcgateway.zalopay.vn');
      for (final body in [
        // A VNPay page is not a MoMo page, and look-alike hosts are refused.
        {...state(), 'provider': 'momo'},
        {
          ...state(url: 'https://zalopay.vn.evil.example/x'),
          'provider': 'zalopay',
        },
        {...state(url: 'https://test-payment.momo.vn/x'), 'provider': 'cash'},
      ]) {
        await expectLater(start(body), throwsA(isA<ApiException>()));
      }
    },
  );
  test('payment methods report each enabled gateway', () async {
    Future<PaymentMethods> methods(Map<String, Object?> body) {
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient((_) async => jsonResponse(body)),
      );
      addTearDown(api.close);
      return RemotePaymentRepository(api).available();
    }

    final all = await methods({
      'cod': true,
      'vnpay': false,
      'momo': true,
      'zalopay': true,
      'sandbox': true,
    });
    expect(
      [
        all.enabled('cod'),
        all.enabled('vnpay'),
        all.enabled('momo'),
        all.enabled('zalopay'),
      ],
      [true, false, true, true],
    );
    // An older server without wallet flags offers no wallet.
    final legacy = await methods({'cod': true, 'vnpay': true, 'sandbox': true});
    expect(legacy.enabled('momo'), isFalse);
    expect(legacy.enabled('vnpay'), isTrue);
  });
  testWidgets('payment panel names and opens the MoMo sandbox page', (
    tester,
  ) async {
    Uri? opened;
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient(
        (_) async => jsonResponse({
          ...state(url: 'https://test-payment.momo.vn/v2/gateway/pay?t=abc'),
          'provider': 'momo',
        }),
      ),
    );
    addTearDown(api.close);
    final order = commerceOrder(
      orderJson()..['payment'] = {'provider': 'momo', 'status': 'PENDING'},
      email: '',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          paymentLauncherProvider.overrideWithValue((uri) => opened = uri),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PaymentPanel(order: order, onRefresh: () async {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Thanh toán qua MoMo'), findsOneWidget);
    await tester.tap(find.text('Thanh toán ngay'));
    await tester.pumpAndSettle();
    expect(opened?.host, 'test-payment.momo.vn');
  });
  testWidgets(
    'verification errors preserve unpaid state and callback page makes no paid claim',
    (tester) async {
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        client: MockClient(
          (_) async => jsonResponse({
            'error': {
              'code': 'PAYMENT_VERIFICATION_UNAVAILABLE',
              'message': 'Không thể kiểm tra lúc này',
            },
          }, 503),
        ),
      );
      addTearDown(api.close);
      final order = commerceOrder(
        orderJson()..['payment'] = {'provider': 'vnpay', 'status': 'PENDING'},
        email: '',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(api)],
          child: MaterialApp(
            home: Scaffold(
              body: PaymentPanel(order: order, onRefresh: () async {}),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Kiểm tra kết quả'));
      await tester.pumpAndSettle();
      expect(find.text('Chờ thanh toán'), findsOneWidget);
      expect(find.text('Đã thanh toán'), findsNothing);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PaymentReturnPage())),
      );
      expect(find.textContaining('Kiểm tra kết quả'), findsOneWidget);
      expect(find.text('Đã thanh toán'), findsNothing);
    },
  );
  testWidgets('after opening the gateway tab the order watches for payment', (
    tester,
  ) async {
    Uri? opened;
    var paid = false;
    final expires = DateTime.now()
        .add(const Duration(minutes: 15))
        .toUtc()
        .toIso8601String();
    Map<String, Object?> open(String status) => state(status: status, url: null)
      ..['provider'] = 'zalopay'
      ..['attempt'] = {
        'reference': 'test',
        'status': status,
        'expiresAt': expires,
        'reviewRequired': false,
      }
      ..['checkoutUrl'] = status == 'PAID'
          ? null
          : 'https://qcgateway.zalopay.vn/openinapp?order=test';
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/start')) return jsonResponse(open('PENDING'));
        return jsonResponse(open(paid ? 'PAID' : 'PENDING'));
      }),
    );
    addTearDown(api.close);
    final order = commerceOrder(
      orderJson()..['payment'] = {'provider': 'zalopay', 'status': 'PENDING'},
      email: '',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          paymentLauncherProvider.overrideWithValue((uri) => opened = uri),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PaymentPanel(
                order: order,
                autoCheck: false,
                onRefresh: () async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Thanh toán ngay'));
    await tester.pumpAndSettle();
    expect(opened?.host, 'qcgateway.zalopay.vn');
    expect(find.text('Mở lại trang thanh toán'), findsOneWidget);
    expect(find.textContaining('tự cập nhật'), findsOneWidget);
    // The shopper pays in the other tab; the next periodic check sees it.
    paid = true;
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.text('Đã thanh toán'), findsOneWidget);
    expect(find.text('Mở lại trang thanh toán'), findsNothing);
  });
  testWidgets('opening an unpaid wallet order verifies it once without a tap', (
    tester,
  ) async {
    final paths = <String>[];
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient((r) async {
        paths.add(r.url.path);
        return jsonResponse(state(status: 'PAID', url: null));
      }),
    );
    addTearDown(api.close);
    final order = commerceOrder(
      orderJson()..['payment'] = {'provider': 'vnpay', 'status': 'PENDING'},
      email: '',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PaymentPanel(order: order, onRefresh: () async {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(paths, [endsWith('/reconcile')]);
    expect(find.text('Đã thanh toán'), findsOneWidget);
    expect(find.text('Thanh toán ngay'), findsNothing);
  });
  const returnedOrder = '9245c6f3-db91-40bd-a1e3-de5489859803';
  Future<List<String>> pumpReturn(
    WidgetTester tester,
    Map<String, Object?> reply,
  ) async {
    final calls = <String>[];
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      client: MockClient((r) async {
        calls.add('${r.method} ${r.url.path}');
        return jsonResponse(reply);
      }),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          accountProvider.overrideWith(_SignedIn.new),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PaymentReturnPage(orderId: returnedOrder),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return calls;
  }

  testWidgets('return page asks the provider and shows a confirmed payment', (
    tester,
  ) async {
    final calls = await pumpReturn(
      tester,
      state(status: 'PAID', url: null)
        ..['orderId'] = returnedOrder
        ..['provider'] = 'zalopay',
    );
    expect(
      calls,
      contains('POST /api/v1/payments/orders/$returnedOrder/reconcile'),
    );
    expect(find.text('Thanh toán thành công'), findsOneWidget);
    expect(find.text('Xem đơn hàng'), findsOneWidget);
  });

  testWidgets('return page reports a failed payment without a paid claim', (
    tester,
  ) async {
    await pumpReturn(
      tester,
      state(status: 'FAILED', url: null)
        ..['orderId'] = returnedOrder
        ..['provider'] = 'momo',
    );
    expect(find.text('Thanh toán chưa hoàn tất'), findsOneWidget);
    expect(find.text('Thanh toán thành công'), findsNothing);
  });
}

class _SignedIn extends AccountController {
  @override
  UserProfile? build() =>
      const UserProfile(name: 'Khách', email: 'khach@example.com', id: 'u1');
}
