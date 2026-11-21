import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/app/account_details.dart';
import 'package:nep_storefront/features/account/account_components.dart';
import 'account_journeys_test.dart' show signedIn, delivery;
import 'customer_reviews_test.dart' show mountHistory, historyJson;
import 'remote_session_test.dart' show jsonResponse;

Finder card(String title) => find.byWidgetPredicate(
  (widget) => widget is AccountCard && widget.title == title,
);

void main() {
  for (final width in [1440.0, 1920.0, 2560.0]) {
    testWidgets(
      'account pages share full-width edges and equal columns at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final container = await signedIn(tester);
        addTearDown(container.dispose);
        await tester.runAsync(
          () => container
              .read(accountDetailsProvider.notifier)
              .saveAddress(delivery),
        );
        final address = container
            .read(accountDetailsProvider)
            .requireValue
            .addresses
            .single;
        final router = createRouter(initialLocation: '/account');
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: NepApp(router: router),
          ),
        );
        await tester.pumpAndSettle();
        final profile = tester.getRect(card('Thông tin cá nhân'));
        expect(profile.left, closeTo(344, 1));
        expect(profile.right, closeTo(width - 56, 1));
        final fields =
            ['Họ và tên', 'Điện thoại (không bắt buộc)', 'Email đăng nhập']
                .map(
                  (label) =>
                      tester.getRect(find.widgetWithText(TextFormField, label)),
                )
                .toList();
        for (final field in fields.skip(1)) {
          expect(field.width, closeTo(fields.first.width, 1));
          expect(field.top, closeTo(fields.first.top, 1));
        }
        router.go('/account/style');
        await tester.pumpAndSettle();
        final style = tester.getRect(card('Bắt đầu từ điều bạn thích'));
        expect(style.left, profile.left);
        expect(style.right, profile.right);
        final size = tester.getRect(
          find.byKey(const ValueKey('style-size-section')),
        );
        final preference = tester.getRect(
          find.byKey(const ValueKey('style-preference-section')),
        );
        expect(size.width, closeTo(preference.width, 1));
        expect(size.top, preference.top);
        router.go('/account/settings');
        await tester.pumpAndSettle();
        final settings = [
          'Thông tin đăng nhập',
          'Mật khẩu và bảo mật',
          'Tùy chọn mua sắm',
          'Quyền riêng tư và phiên đăng nhập',
        ].map((title) => tester.getRect(card(title))).toList();
        expect(settings.first.left, profile.left);
        expect(settings[1].right, profile.right);
        for (var row = 0; row < 4; row += 2) {
          expect(settings[row].size, settings[row + 1].size);
          expect(settings[row].top, settings[row + 1].top);
        }
        router.go('/account/addresses');
        await tester.pumpAndSettle();
        final addressCard = tester.getRect(
          find.byKey(const ValueKey('addresses-table')).evaluate().isNotEmpty
              ? find.byKey(const ValueKey('addresses-table'))
              : find.byKey(ValueKey('account-address-${address.id}')),
        );
        expect(addressCard.left, profile.left);
        expect(addressCard.right, profile.right);
        final addButton = tester.getRect(
          find.widgetWithText(FilledButton, 'Thêm địa chỉ'),
        );
        expect(addButton.right, closeTo(profile.right, 1));
      },
    );
  }
  testWidgets(
    'review empty state spans the same content width on ultrawide screens',
    (tester) async {
      tester.view.physicalSize = const Size(2560, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mountHistory(tester, (_) async => jsonResponse(historyJson([])));
      final empty = tester.getRect(find.byType(AccountEmptyState));
      expect(empty.left, closeTo(344, 1));
      expect(empty.right, closeTo(2504, 1));
      expect(empty.height, greaterThanOrEqualTo(360));
      expect(tester.takeException(), isNull);
    },
  );
}
