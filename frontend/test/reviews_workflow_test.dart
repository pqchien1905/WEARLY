import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nep_storefront/core/widgets/primitives.dart';
import 'customer_reviews_test.dart'
    show mountHistory, ownedJson, historyJson, tapVisible;
import 'remote_session_test.dart' show jsonResponse;

Finder action(String label) => find.widgetWithText(AppButton, label);
Finder searchField() => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == 'Tìm đánh giá',
);
Finder dialogAction(String label) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(label));

void main() {
  testWidgets('changing responsive layout preserves search, rating and page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final queries = <Map<String, String>>[];
    await mountHistory(tester, (r) async {
      queries.add(r.url.queryParameters);
      return jsonResponse(
        historyJson(
          [ownedJson()],
          total: 6,
          page: int.parse(r.url.queryParameters['page']!),
        ),
      );
    });
    await tester.enterText(searchField(), 'cotton');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('5 sao'));
    await tapVisible(tester, find.text('Trang sau'));
    final reads = queries.length;
    tester.view.physicalSize = const Size(375, 900);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(searchField()).controller!.text, 'cotton');
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '5 sao'))
          .selected,
      isTrue,
    );
    expect(find.text('Trang 2 / 2'), findsOneWidget);
    expect(queries.length, reads);
    tester.view.physicalSize = const Size(1440, 1000);
    await tester.pumpAndSettle();
    expect(find.text('Trang 2 / 2'), findsOneWidget);
    expect(queries.length, reads);
  });
  testWidgets('search is debounced and rating/search apply to server pages', (
    tester,
  ) async {
    final queries = <Map<String, String>>[];
    await mountHistory(tester, (r) async {
      queries.add(r.url.queryParameters);
      final q = r.url.queryParameters;
      return jsonResponse(
        historyJson(
          q['q'] == 'missing' ? [] : [ownedJson(id: q['rating'] ?? '1')],
          total: q['q'] == 'missing'
              ? 0
              : q['rating'] == null
              ? 6
              : 1,
          page: int.parse(q['page']!),
        ),
      );
    });
    await tapVisible(tester, find.text('Trang sau'));
    await tester.enterText(searchField(), 'mis');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(searchField(), '  missing  ');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(queries.where((q) => q.containsKey('q')).length, 1);
    expect(queries.last, {'page': '1', 'limit': '5', 'q': 'missing'});
    expect(find.text('Không có đánh giá phù hợp'), findsOneWidget);
    expect(find.text('Bạn chưa viết đánh giá nào'), findsNothing);
    await tapVisible(tester, find.text('Bỏ bộ lọc'));
    await tapVisible(tester, find.text('3 sao'));
    expect(queries.last['rating'], '3');
    expect(find.text('Nội dung của tôi 3'), findsOneWidget);
    await tester.enterText(searchField(), 'cotton');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(queries.last['q'], 'cotton');
    await tapVisible(tester, find.byTooltip('Xóa từ khóa'));
    expect(queries.last['rating'], '3');
    expect(queries.last.containsKey('q'), isFalse);
    await tapVisible(tester, find.text('Đặt lại'));
    expect(queries.last.containsKey('rating'), isFalse);
  });

  testWidgets(
    'closing, discarding drafts and saving preserve the current page',
    (tester) async {
      var comment = 'Nội dung của tôi 6', writes = 0;
      final pages = <String>[];
      await mountHistory(tester, (r) async {
        if (r.method == 'PATCH') {
          writes++;
          comment = jsonDecode(r.body)['comment'];
          return jsonResponse({...ownedJson(id: '6'), 'comment': comment});
        }
        pages.add(r.url.queryParameters['page']!);
        return jsonResponse(
          historyJson(
            pages.last == '1'
                ? [for (var i = 1; i <= 5; i++) ownedJson(id: '$i')]
                : [
                    {...ownedJson(id: '6'), 'comment': comment},
                  ],
            page: int.parse(pages.last),
            total: 6,
          ),
        );
      });
      await tapVisible(tester, find.text('Trang sau'));
      await tapVisible(tester, find.text('Sửa đánh giá'));
      expect(
        tester.widget<AppButton>(action('Lưu đánh giá')).onPressed,
        isNull,
      );
      await tapVisible(tester, find.text('Đóng'));
      expect(find.text('Trang 2 / 2'), findsOneWidget);
      expect(pages, ['1', '2']);
      await tapVisible(tester, find.text('Sửa đánh giá'));
      await tester.enterText(find.byType(TextFormField), 'Bản nháp');
      await tapVisible(tester, find.text('Đóng'));
      expect(find.text('Bỏ thay đổi chưa lưu?'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'Bản nháp',
      );
      await tapVisible(tester, find.text('Đóng'));
      await tapVisible(tester, find.text('Bỏ thay đổi'));
      expect(find.text('Trang 2 / 2'), findsOneWidget);
      expect(writes, 0);
      await tapVisible(tester, find.text('Sửa đánh giá'));
      await tester.enterText(find.byType(TextFormField), 'Đã sửa');
      await tapVisible(tester, find.text('Lưu đánh giá'));
      expect(writes, 1);
      expect(pages.last, '2');
      expect(find.text('Đã lưu thay đổi đánh giá.'), findsOneWidget);
      expect(find.text('Đã sửa'), findsOneWidget);
      expect(find.text('Trang 2 / 2'), findsOneWidget);
    },
  );

  testWidgets(
    'refresh retains rows, locks stale actions and retries the same page',
    (tester) async {
      var reads = 0;
      final pending = Completer<http.Response>();
      final pages = <String>[];
      await mountHistory(tester, (r) async {
        pages.add(r.url.queryParameters['page']!);
        if (++reads == 3) return pending.future;
        return jsonResponse(
          historyJson(
            [ownedJson(id: pages.last)],
            page: int.parse(pages.last),
            total: 6,
          ),
        );
      });
      await tapVisible(tester, find.text('Trang sau'));
      await tester.ensureVisible(find.text('Tải lại'));
      await tester.tap(find.text('Tải lại'));
      await tester.pump();
      expect(find.text('Nội dung của tôi 2'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Sửa đánh giá'),
            )
            .onPressed,
        isNull,
      );
      pending.complete(jsonResponse({}, 503));
      await tester.pumpAndSettle();
      expect(find.text('Chưa cập nhật được danh sách'), findsOneWidget);
      expect(find.text('Nội dung của tôi 2'), findsOneWidget);
      expect(find.text('Bạn chưa viết đánh giá nào'), findsNothing);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Xóa đánh giá'))
            .onPressed,
        isNull,
      );
      await tapVisible(tester, find.text('Thử lại'));
      expect(pages, ['1', '2', '2', '2']);
      expect(find.text('Chưa cập nhật được danh sách'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Sửa đánh giá'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'new page failure retries that page and late searches cannot replace results',
    (tester) async {
      var failed = false;
      final pending = Completer<http.Response>();
      await mountHistory(tester, (r) async {
        final p = r.url.queryParameters;
        if (p['q'] == 'old') return pending.future;
        if (p['page'] == '2' && !failed) {
          failed = true;
          return jsonResponse({}, 500);
        }
        return jsonResponse(
          historyJson(
            [ownedJson(id: p['q'] ?? p['page']!)],
            page: int.parse(p['page']!),
            total: 6,
          ),
        );
      });
      await tapVisible(tester, find.text('Trang sau'));
      expect(find.text('Chưa tải được đánh giá'), findsOneWidget);
      await tapVisible(tester, find.text('Tải lại'));
      expect(find.text('Nội dung của tôi 2'), findsOneWidget);
      await tester.enterText(searchField(), 'old');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.enterText(searchField(), 'new');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      pending.complete(jsonResponse(historyJson([ownedJson(id: 'old')])));
      await tester.pumpAndSettle();
      expect(find.text('Nội dung của tôi new'), findsOneWidget);
      expect(find.text('Nội dung của tôi old'), findsNothing);
    },
  );

  testWidgets(
    'pending save is single submission and validation failure preserves draft',
    (tester) async {
      var writes = 0;
      final pending = Completer<http.Response>();
      await mountHistory(tester, (r) async {
        if (r.method == 'GET') return jsonResponse(historyJson([ownedJson()]));
        writes++;
        if (writes == 1) return pending.future;
        return jsonResponse({
          ...ownedJson(),
          'comment': jsonDecode(r.body)['comment'],
        });
      });
      await tapVisible(tester, find.text('Sửa đánh giá'));
      await tester.enterText(find.byType(TextFormField), 'Giữ bản nháp');
      await tester.pump();
      final submit = tester
          .widget<AppButton>(action('Lưu đánh giá'))
          .onPressed!;
      submit();
      submit();
      await tester.pump();
      expect(writes, 1);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Đóng'))
            .onPressed,
        isNull,
      );
      pending.complete(
        jsonResponse({
          'code': 'VALIDATION_ERROR',
          'message': 'Kiểm tra nội dung',
        }, 400),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        'Giữ bản nháp',
      );
      await tapVisible(tester, find.text('Lưu đánh giá'));
      expect(writes, 2);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
}
