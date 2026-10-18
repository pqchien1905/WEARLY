import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/app/providers.dart';
import 'package:nep_storefront/data/mock_catalog.dart';

void main() {
  for (final width in [320.0, 375.0, 768.0, 1024.0, 1440.0, 1920.0]) {
    for (final path in ['/', '/shop', '/products/nep-1']) {
      testWidgets('$path renders without overflow at $width', (tester) async {
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
  testWidgets(
    'size selection rejects missing size and disables sold out sizes',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
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
          child: NepApp(
            router: createRouter(initialLocation: '/products/nep-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Thêm vào giỏ'));
      await tester.tap(find.text('Thêm vào giỏ'));
      await tester.pump();
      expect(find.text('Chọn size trước khi thêm vào giỏ.'), findsOneWidget);
      await tester.ensureVisible(find.text('M').first);
      await tester.tap(find.text('M').first);
      await tester.pump();
      expect(find.text('Chọn size trước khi thêm vào giỏ.'), findsNothing);
      final xl = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('XL').first,
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(xl.onPressed, isNull);
    },
  );
}
