import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/data/remote_admin.dart';
import 'package:nep_storefront/features/admin/remote/admin_pagination.dart';

void main() {
  Future<void> mount(
    WidgetTester t, {
    int total = 25,
    int page = 1,
    int count = 10,
    double width = 1200,
    double scale = 1,
    bool loading = false,
    ValueChanged<int>? onPage,
    ValueChanged<int>? onSize,
  }) async {
    t.view.physicalSize = Size(width, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: AdminPagination(
              page: AdminPage({
                'items': List.generate(count, (_) => <String, dynamic>{}),
                'total': total,
                'page': page,
                'limit': 10,
              }),
              onPage: onPage ?? (_) {},
              onPageSize: onSize ?? (_) {},
              loading: loading,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'range, page navigation and page-size selection describe server data',
    (t) async {
      int? selected, size;
      await mount(
        t,
        page: 2,
        onPage: (n) => selected = n,
        onSize: (n) => size = n,
      );
      expect(find.text('Trang 2/3 · 11–20 / 25 mục'), findsOneWidget);
      await t.tap(find.text('3'));
      expect(selected, 3);
      await t.tap(find.text('10 mục'));
      await t.pumpAndSettle();
      await t.tap(find.text('20 mục').last);
      await t.pumpAndSettle();
      expect(size, 20);
    },
  );
  testWidgets('empty results disable navigation and display zero records', (
    t,
  ) async {
    var calls = 0;
    await mount(t, total: 0, count: 0, onPage: (_) => calls++);
    expect(find.text('Trang 1/1 · 0–0 / 0 mục'), findsOneWidget);
    await t.tap(find.text('Trang trước'));
    await t.tap(find.text('Trang sau'));
    expect(calls, 0);
  });
  testWidgets('last page and pending requests cannot advance', (t) async {
    var calls = 0;
    await mount(t, page: 3, count: 5, loading: true, onPage: (_) => calls++);
    expect(find.text('Trang 3/3 · 21–25 / 25 mục'), findsOneWidget);
    await t.tap(find.text('Trang trước'));
    await t.tap(find.text('Trang sau'));
    expect(calls, 0);
  });
  for (final width in [320.0, 375.0, 768.0, 900.0, 2560.0]) {
    testWidgets('pagination fits $width with enlarged text', (t) async {
      await mount(t, width: width, scale: 2);
      expect(t.takeException(), isNull);
    });
  }
}
