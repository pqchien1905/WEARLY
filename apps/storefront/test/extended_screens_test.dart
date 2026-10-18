import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/app/providers.dart';
import 'package:nep_storefront/data/mock_catalog.dart';
import 'package:nep_storefront/features/virtual_tryon/image_validation.dart';
import 'package:nep_storefront/features/virtual_tryon/tryon_page.dart';
import 'package:nep_storefront/domain/ai.dart';

void main() {
  for (final width in [320.0, 375.0, 768.0, 1024.0, 1440.0, 1920.0]) {
    for (final path in [
      '/ai-stylist',
      '/virtual-try-on',
      '/account',
      '/login',
      '/admin',
      '/admin/products',
      '/admin/products/p1/edit',
      '/admin/orders',
      '/admin/promotions',
      '/admin/content',
      '/admin/ai-monitoring',
      '/admin/settings',
    ]) {
      testWidgets('$path at $width has no overflow', (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              productRepositoryProvider.overrideWithValue(
                MockProductRepository(latency: Duration.zero),
              ),
            ],
            child: NepApp(router: createRouter(initialLocation: path)),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
  test('file validation rejects renamed nonimage and excessive size', () {
    expect(validateImage(Uint8List.fromList([1, 2, 3])), isNotNull);
    expect(validateImage(Uint8List(8 * 1024 * 1024 + 1)), contains('8 MB'));
  });
  testWidgets('try-on error has an actionable retry', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TryOnStatusPanel(
            job: const TryOnJob(
              'demo',
              TryOnStatus.failed,
              error: 'Demo error',
            ),
            onCancel: () {},
            onRetry: () => retried = true,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Thử lại'));
    expect(retried, isTrue);
  });
  testWidgets('admin edits are visible when navigating to the storefront', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = createRouter(initialLocation: '/admin/products/p1/edit');
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
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Tên sản phẩm'),
      'Áo đã chỉnh sửa trong demo',
    );
    await tester.ensureVisible(find.text('Lưu sản phẩm demo'));
    await tester.tap(find.text('Lưu sản phẩm demo'));
    await tester.pumpAndSettle();
    router.go('/products/nep-1');
    await tester.pumpAndSettle();
    expect(find.text('Áo đã chỉnh sửa trong demo'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
