import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/app/account_state.dart';
import 'package:nep_storefront/app/account_details.dart';
import 'package:nep_storefront/app/commerce_state.dart';
import 'package:nep_storefront/app/providers.dart';
import 'package:nep_storefront/data/mock_account.dart';
import 'package:nep_storefront/data/mock_account_details.dart';
import 'package:nep_storefront/data/mock_catalog.dart';
import 'package:nep_storefront/features/virtual_tryon/tryon_results.dart';

Future<ProviderContainer> signedIn(WidgetTester tester) async =>
    (await tester.runAsync(() async {
      final c = ProviderContainer(
        overrides: [
          accountRepositoryProvider.overrideWithValue(
            MockAccountRepository(latency: Duration.zero),
          ),
          accountDetailsRepositoryProvider.overrideWithValue(
            MockAccountDetailsRepository(latency: Duration.zero),
          ),
          productRepositoryProvider.overrideWithValue(
            MockProductRepository(latency: Duration.zero),
          ),
        ],
      );
      await c
          .read(accountProvider.notifier)
          .signIn('An', 'an@example.com', 'demo1234');
      await c.read(accountDetailsProvider.future);
      return c;
    }))!;
const delivery = DeliveryAddress(
  id: '',
  label: 'Nhà',
  recipient: 'Nguyễn An',
  phone: '0901234567',
  address: '12 Nguyễn Huệ, TP.HCM',
);

void main() {
  testWidgets('address editor validates and saves a default address', (
    t,
  ) async {
    final c = await signedIn(t);
    addTearDown(c.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: NepApp(
          router: createRouter(initialLocation: '/account/addresses'),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Thêm địa chỉ'));
    await t.tap(find.text('Thêm địa chỉ'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Lưu địa chỉ demo'));
    await t.tap(find.text('Lưu địa chỉ demo'));
    await t.pumpAndSettle();
    expect(find.text('Nhập số điện thoại 10 chữ số.'), findsOneWidget);
    for (final input in [
      ('Tên gợi nhớ', 'Nhà'),
      ('Người nhận', 'Nguyễn An'),
      ('Điện thoại nhận hàng', '0901234567'),
      ('Địa chỉ nhận hàng', '12 Nguyễn Huệ, TP.HCM'),
    ]) {
      await t.enterText(find.widgetWithText(TextFormField, input.$1), input.$2);
    }
    await t.ensureVisible(find.text('Lưu địa chỉ demo'));
    await t.tap(find.text('Lưu địa chỉ demo'));
    await t.pumpAndSettle();
    expect(
      c.read(accountDetailsProvider).asData?.value.defaultAddress?.recipient,
      'Nguyễn An',
    );
    expect(find.text('Mặc định'), findsOneWidget);
  });

  testWidgets('checkout applies saved address only when explicitly selected', (
    t,
  ) async {
    final c = await signedIn(t);
    addTearDown(c.dispose);
    await t.runAsync(() async {
      await c.read(accountDetailsProvider.notifier).saveAddress(delivery);
      final product = await c.read(productRepositoryProvider).bySlug('nep-1');
      await c
          .read(commerceProvider)
          .add(
            product!.slug,
            product.variants.firstWhere((v) => v.size == 'M').sku,
            1,
          );
    });
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: NepApp(router: createRouter(initialLocation: '/checkout')),
      ),
    );
    await t.pumpAndSettle();
    final name = find.widgetWithText(TextFormField, 'Họ và tên');
    expect(t.widget<TextFormField>(name).controller!.text, isEmpty);
    final saved = find.textContaining('Nguyễn An ·');
    await t.ensureVisible(saved);
    await t.tap(saved);
    await t.pumpAndSettle();
    expect(t.widget<TextFormField>(name).controller!.text, 'Nguyễn An');
    await t.enterText(name, 'Người nhận khác');
    await t.runAsync(
      () => c
          .read(accountDetailsProvider.notifier)
          .saveStyle(const StylePreferences(size: 'L')),
    );
    await t.pumpAndSettle();
    expect(t.widget<TextFormField>(name).controller!.text, 'Người nhận khác');
  });

  testWidgets('Stylist applies saved preferences into the actual controls', (
    t,
  ) async {
    final c = await signedIn(t);
    addTearDown(c.dispose);
    await t.runAsync(
      () => c
          .read(accountDetailsProvider.notifier)
          .saveStyle(
            const StylePreferences(
              size: 'L',
              budget: 2500000,
              style: 'Thanh lịch',
              color: 'Đen',
            ),
          ),
    );
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: NepApp(router: createRouter(initialLocation: '/ai-stylist')),
      ),
    );
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Dùng hồ sơ phong cách'));
    await t.tap(find.text('Dùng hồ sơ phong cách'));
    await t.pumpAndSettle();
    expect(find.text('L'), findsOneWidget);
    expect(find.text('Đen'), findsOneWidget);
    expect(find.text('Thanh lịch'), findsOneWidget);
  });

  testWidgets('Try-On history opens a result and deletion removes its link', (
    t,
  ) async {
    final c = await signedIn(t);
    addTearDown(c.dispose);
    c
        .read(tryOnResultsProvider.notifier)
        .save(
          const TryOnResult(id: 'test-1', slug: 'nep-1', sku: 'WRL-1-MAIN-M'),
        );
    final router = createRouter(initialLocation: '/account/try-ons');
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: NepApp(router: router),
      ),
    );
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Xem kết quả'));
    await t.tap(find.text('Xem kết quả'));
    await t.pumpAndSettle();
    expect(find.text('Biến thể: WRL-1-MAIN-M'), findsOneWidget);
    await t.ensureVisible(find.text('Xóa kết quả demo'));
    await t.tap(find.text('Xóa kết quả demo'));
    await t.pumpAndSettle();
    router.go('/account/try-ons');
    await t.pumpAndSettle();
    expect(find.text('Chưa có lần thử đồ nào'), findsOneWidget);
  });

  for (final route in [
    '/account/addresses',
    '/account/style',
    '/account/try-ons',
    '/account/orders',
  ]) {
    for (final width in [320.0, 768.0, 1440.0]) {
      testWidgets('$route responsive at $width with enlarged text', (t) async {
        t.view.physicalSize = Size(width, 1000);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final c = await signedIn(t);
        addTearDown(c.dispose);
        await t.runAsync(
          () => c.read(accountDetailsProvider.notifier).saveAddress(delivery),
        );
        c
            .read(tryOnResultsProvider.notifier)
            .save(
              const TryOnResult(id: 'demo', slug: 'nep-1', sku: 'WRL-1-MAIN-M'),
            );
        await t.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: NepApp(router: createRouter(initialLocation: route)),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  }
}
