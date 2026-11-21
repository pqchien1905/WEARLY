import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/app/providers.dart';
import 'package:nep_storefront/app/collection_providers.dart';
import 'package:nep_storefront/app/commerce_state.dart';
import 'package:nep_storefront/data/mock_catalog.dart';
import 'package:nep_storefront/domain/catalog.dart';
import 'collections_test.dart' show collectionJson;
import 'remote_catalog_test.dart' show productJson;

void main() {
  testWidgets(
    'mobile admin exposes product price and edit without horizontal scrolling',
    (tester) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = createRouter(initialLocation: '/admin/products');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productRepositoryProvider.overrideWithValue(
              MockProductRepository(latency: Duration.zero),
            ),
          ],
          child: NepApp(router: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DataTable), findsNothing);
      expect(find.text('Từ 490.000 ₫'), findsOneWidget);
      final edit = find.byTooltip('Sửa Áo cotton không tay Essential');
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/admin/products/p1/edit',
      );
    },
  );
  testWidgets('product warns when selected color has no matching photograph', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productRepositoryProvider.overrideWithValue(
            MockProductRepository(latency: Duration.zero),
          ),
        ],
        child: NepApp(router: createRouter(initialLocation: '/products/nep-1')),
      ),
    );
    await tester.pumpAndSettle();
    final black = find.byTooltip('Đen').first;
    await tester.ensureVisible(black);
    await tester.tap(black);
    await tester.pumpAndSettle();
    expect(find.textContaining('Chưa có ảnh màu Đen'), findsOneWidget);
  });
  testWidgets('contact validates and confirms a local demo request', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: NepApp(router: createRouter(initialLocation: '/contact')),
      ),
    );
    await tester.pumpAndSettle();
    final send = find.text('Gửi yêu cầu demo');
    expect(send, findsOneWidget);
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(
      find.text('Nhập email hợp lệ, ví dụ ban@example.com.'),
      findsOneWidget,
    );
    for (final entry in {
      'Tên của bạn': 'Khách demo',
      'Email liên hệ': 'hello@example.com',
      'Nội dung cần hỗ trợ': 'Tôi cần xem bảng số đo.',
    }.entries) {
      final f = find.widgetWithText(TextFormField, entry.key);
      await tester.ensureVisible(f);
      await tester.enterText(f, entry.value);
    }
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(find.text('Đã hoàn tất yêu cầu mô phỏng'), findsOneWidget);
  });

  testWidgets(
    'collection detail links to curated products and handles unknown slug',
    (tester) async {
      final router = createRouter(initialLocation: '/collections/everyday');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectionDetailProvider.overrideWith(
              (ref, location) async => location.endsWith('/missing')
                  ? null
                  : CollectionDetail.fromJson({
                      'collection': {
                        ...collectionJson(slug: 'everyday'),
                        'title': 'Everyday, theo cách bạn.',
                      },
                      'items': [
                        {
                          ...productJson(),
                          'name': 'Áo cotton không tay Essential',
                        },
                      ],
                      'total': 1,
                      'page': 1,
                      'limit': 12,
                    }),
            ),
            productRepositoryProvider.overrideWithValue(
              MockProductRepository(latency: Duration.zero),
            ),
          ],
          child: NepApp(router: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Everyday, theo cách bạn.'), findsOneWidget);
      expect(find.text('Áo cotton không tay Essential'), findsOneWidget);
      expect(find.text('Áo cotton không tay Daily'), findsNothing);
      router.go('/collections/missing');
      await tester.pumpAndSettle();
      expect(find.text('Chưa tìm thấy bộ sưu tập'), findsOneWidget);
    },
  );

  testWidgets('expired try-on link explains how to start again', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productRepositoryProvider.overrideWithValue(
            MockProductRepository(latency: Duration.zero),
          ),
        ],
        child: NepApp(
          router: createRouter(initialLocation: '/virtual-try-on/expired'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Phiên thử đồ không còn ở đây'), findsOneWidget);
    await tester.tap(find.text('Bắt đầu thử đồ'));
    await tester.pumpAndSettle();
    expect(find.text('Phòng thử của bạn.'), findsOneWidget);
  });
  testWidgets('quick add selects a SKU and adds without leaving catalog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = MockProductRepository(latency: Duration.zero);
    final router = createRouter(initialLocation: '/shop');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [productRepositoryProvider.overrideWithValue(repo)],
        child: NepApp(router: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byTooltip('Chọn size ${repo.products.first.name}'),
    );
    await tester.tap(find.byTooltip('Chọn size ${repo.products.first.name}'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/shop');
    expect(find.text('Chọn nhanh'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Đen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('M').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thêm vào giỏ'));
    await tester.pumpAndSettle();
    final scope = ProviderScope.containerOf(
      tester.element(find.byType(NepApp)),
    );
    expect(scope.read(commerceProvider).items.single.color, 'Đen');
    expect(scope.read(commerceProvider).items.single.size, 'M');
    expect(find.text('Giỏ hàng của bạn'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('unfiltered catalog includes products above three million', () async {
    final repo = MockProductRepository(latency: Duration.zero);
    final p = repo.products.first;
    await repo.save(
      p.copyWith(
        variants: p.variants.map((v) => v.copyWith(price: 4500000)).toList(),
      ),
    );
    expect(
      (await repo.list(ProductQuery.fromParams({}))).items.map((p) => p.id),
      contains(p.id),
    );
    expect(
      (await repo.list(
        const ProductQuery(maxPrice: 3000000, limit: 100),
      )).items.map((p) => p.id),
      isNot(contains(p.id)),
    );
    expect(
      (await repo.list(
        ProductQuery.fromParams({'max': '5000000'}),
      )).items.map((p) => p.id),
      contains(p.id),
    );
  });

  testWidgets('mobile filters use catalog colors and apply a draft together', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = MockProductRepository(latency: Duration.zero);
    final router = createRouter(initialLocation: '/shop?sort=price-desc');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [productRepositoryProvider.overrideWithValue(repo)],
        child: NepApp(router: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bộ lọc'));
    await tester.pumpAndSettle();
    final purple = find.widgetWithText(FilterChip, 'Tím');
    expect(purple, findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(FilterChip, 'M'));
    await tester.tap(find.widgetWithText(FilterChip, 'M'));
    await tester.pumpAndSettle();
    expect(find.text('Bộ lọc sản phẩm'), findsOneWidget);
    expect(
      router.routeInformationProvider.value.uri.queryParameters['size'],
      isNull,
    );
    await tester.ensureVisible(purple);
    await tester.tap(purple);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xem kết quả'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.queryParameters, {
      'sort': 'price-desc',
      'size': 'M',
      'color': 'Tím',
    });
    await tester.tap(find.text('Bộ lọc'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilterChip, 'L'));
    await tester.tap(find.widgetWithText(FilterChip, 'L'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Đóng bộ lọc'));
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.queryParameters['size'],
      'M',
    );
    expect(tester.takeException(), isNull);
  });
}
