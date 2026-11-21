import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/core/widgets/primitives.dart';
import 'package:nep_storefront/data/remote_reviews.dart';
import 'customer_reviews_test.dart'
    show mountHistory, ownedJson, historyJson, tapVisible;
import 'remote_session_test.dart' show jsonResponse;

void main() {
  test('review images are optional for existing API responses', () {
    expect(OwnedReview.fromJson(ownedJson()).product!.image, isNull);
    final json = ownedJson();
    (json['product'] as Map)['image'] = 'assets/images/01.jpg';
    expect(OwnedReview.fromJson(json).product!.image, 'assets/images/01.jpg');
    expect(OwnedReview.fromJson(ownedJson(hidden: true)).product, isNull);
  });

  for (final width in [375.0, 768.0, 1440.0, 2560.0]) {
    testWidgets('review columns and actions fit the available width at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final json = ownedJson();
      json['createdAt'] = '2026-10-23T18:00:00.000Z';
      final product = json['product'] as Map;
      product['name'] =
          'Áo cotton không tay Essential với thiết kế thanh lịch và chất vải thoáng mát';
      // A real bundled image avoids a network dependency in the layout test.
      product['image'] = 'assets/images/shirt.jpg';
      json['comment'] = List.filled(
        12,
        'Chất vải mềm, đường may đẹp và dễ phối đồ.',
      ).join(' ');
      await mountHistory(
        tester,
        (_) async =>
            jsonResponse(historyJson([json, ownedJson(id: '2', hidden: true)])),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Ngày 24/10/2026'), findsWidgets);
      expect(find.byType(FashionImage), findsOneWidget);
      final table = find.byKey(const ValueKey('reviews-table'));
      if (width >= 1440) {
        expect(table, findsOneWidget);
        final bounds = tester.getRect(table);
        expect(bounds.left, closeTo(344, 1));
        expect(bounds.right, closeTo(width - 56, 1));
        final name = tester.getRect(find.text(product['name']));
        final comment = tester.getRect(find.text(json['comment']));
        final action = tester.getRect(find.text('Sửa đánh giá'));
        expect(name.right, lessThan(comment.left));
        expect(comment.right, lessThan(action.left));
      } else {
        expect(table, findsNothing);
      }
      await tapVisible(tester, find.text('Sửa đánh giá'));
      expect(find.text('Sửa đánh giá của bạn'), findsOneWidget);
      await tapVisible(tester, find.text('Đóng'));
      await tapVisible(tester, find.text('Xem sản phẩm'));
      expect(find.text('Product: shirt-1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('narrow screen and larger text keep review actions reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await mountHistory(
      tester,
      (_) async => jsonResponse(historyJson([ownedJson()])),
    );
    expect(find.byKey(const ValueKey('reviews-table')), findsNothing);
    await tapVisible(tester, find.text('Sửa đánh giá'));
    expect(find.text('Sửa đánh giá của bạn'), findsOneWidget);
    await tapVisible(tester, find.text('Đóng'));
    await tapVisible(tester, find.text('Xóa đánh giá'));
    expect(find.text('Xóa đánh giá?'), findsOneWidget);
    await tapVisible(tester, find.text('Đóng'));
    expect(tester.takeException(), isNull);
  });
}
