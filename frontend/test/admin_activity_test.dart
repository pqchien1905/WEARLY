import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/features/admin/remote/admin_activity.dart';
import 'package:nep_storefront/features/admin/remote/admin_providers.dart';

AdminPage history(int page, {bool empty = false}) => AdminPage({
  'page': page,
  'limit': 20,
  'total': empty ? 0 : 21,
  'items': empty
      ? []
      : [
          {
            'id': 'event-$page',
            'actorId': 'd5af7f7a-141d-4ac3-82eb-97bbc3fd3351',
            'targetId': 'c8cebc19-d7b3-487a-8e84-d71b60a6f45a',
            'action': page == 1 ? 'PRODUCT_UPDATED' : 'INVENTORY_ADJUSTED',
            'createdAt': '2026-10-20T10:30:00.000Z',
          },
        ],
});

void main() {
  Future<void> mount(
    WidgetTester tester,
    Future<AdminPage> Function(AdminListKey) load,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (retryCount, error) => null,
        overrides: [adminListProvider.overrideWith((ref, key) => load(key))],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: AdminActivityPanel()),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('activity pages wrap identifiers on a narrow screen and reload', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final reads = <int>[];
    await mount(tester, (key) async {
      expect(key.kind, 'audit');
      reads.add(key.page);
      return history(key.page);
    });
    await tester.pumpAndSettle();
    expect(find.text('Cập nhật sản phẩm'), findsOneWidget);
    expect(find.textContaining('d5af7f7a-141d'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Trang sau'));
    await tester.pumpAndSettle();
    expect(find.text('Điều chỉnh tồn kho'), findsOneWidget);
    expect(find.text('Cập nhật sản phẩm'), findsNothing);
    await tester.tap(find.text('Tải lại lịch sử'));
    await tester.pumpAndSettle();
    expect(reads, [1, 2, 2]);
    await tester.tap(find.text('Trang trước'));
    await tester.pumpAndSettle();
    expect(find.text('Cập nhật sản phẩm'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('activity shows loading, retryable errors and empty history', (
    tester,
  ) async {
    final pending = Completer<AdminPage>();
    var attempts = 0;
    await mount(tester, (key) {
      attempts++;
      return attempts == 1
          ? pending.future
          : Future.value(history(1, empty: true));
    });
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(Exception('Network unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Chưa tải được dữ liệu'), findsOneWidget);
    await tester.tap(find.text('Thử tải lại'));
    await tester.pumpAndSettle();
    expect(
      find.text('Chưa có thao tác quản trị được ghi nhận.'),
      findsOneWidget,
    );
    expect(find.text('Trang sau'), findsNothing);
  });
}
