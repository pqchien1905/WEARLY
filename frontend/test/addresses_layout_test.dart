import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/app/account_details.dart';
import 'account_journeys_test.dart' show signedIn, delivery;

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.pump();
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final config in [
    (320.0, 2.0),
    (375.0, 1.0),
    (768.0, 1.0),
    (1440.0, 1.0),
    (2560.0, 1.0),
  ]) {
    testWidgets(
      'address columns and editor fit ${config.$1}px at ${config.$2} text scale',
      (tester) async {
        tester.view.physicalSize = Size(config.$1, 1100);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = config.$2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final container = await signedIn(tester);
        addTearDown(container.dispose);
        const office = DeliveryAddress(
          id: '',
          label: 'Văn phòng làm việc tại trung tâm thành phố',
          recipient: 'Nguyễn Minh Quang Chiến',
          phone: '0901234568',
          address:
              'Tầng 12, tòa nhà văn phòng, số 128 đường Nguyễn Văn Cừ, phường Trường Vinh, tỉnh Nghệ An',
        );
        await tester.runAsync(() async {
          await container
              .read(accountDetailsProvider.notifier)
              .saveAddress(delivery);
          await container
              .read(accountDetailsProvider.notifier)
              .saveAddress(office);
        });
        final router = createRouter(initialLocation: '/account/addresses');
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: NepApp(router: router),
          ),
        );
        await tester.pumpAndSettle();
        final saved = container
            .read(accountDetailsProvider)
            .requireValue
            .addresses;
        final officeRow = find.byKey(
          ValueKey('account-address-${saved.last.id}'),
        );
        expect(tester.takeException(), isNull);
        expect(find.text(office.address), findsOneWidget);
        expect(find.text('Mặc định'), findsOneWidget);
        final table = find.byKey(const ValueKey('addresses-table'));
        if (config.$1 >= 1440) {
          final bounds = tester.getRect(table);
          expect(bounds.left, closeTo(344, 1));
          expect(bounds.right, closeTo(config.$1 - 56, 1));
          final recipient = tester.getRect(find.text(office.recipient));
          final address = tester.getRect(find.text(office.address));
          expect(recipient.right, lessThan(address.left));
          expect(recipient.top, closeTo(address.top, 1));
        } else {
          expect(table, findsNothing);
        }
        await tapVisible(
          tester,
          find.descendant(
            of: officeRow,
            matching: find.text('Đặt làm mặc định'),
          ),
        );
        expect(
          container.read(accountDetailsProvider).requireValue.defaultAddressId,
          saved.last.id,
        );
        await tapVisible(
          tester,
          find.descendant(of: officeRow, matching: find.text('Chỉnh sửa')),
        );
        expect(find.text('Chỉnh sửa địa chỉ'), findsOneWidget);
        final nameField = find.widgetWithText(TextFormField, 'Người nhận');
        final phoneField = find.widgetWithText(
          TextFormField,
          'Điện thoại nhận hàng',
        );
        if (config.$1 >= 768) {
          final name = tester.getRect(nameField),
              phone = tester.getRect(phoneField);
          expect(name.top, closeTo(phone.top, 1));
          expect(name.width, closeTo(phone.width, 1));
        }
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Tên gợi nhớ'),
          'Văn phòng',
        );
        await tapVisible(tester, find.text('Lưu địa chỉ demo'));
        expect(
          container
              .read(accountDetailsProvider)
              .requireValue
              .addresses
              .last
              .label,
          'Văn phòng',
        );
        await tapVisible(
          tester,
          find.descendant(of: officeRow, matching: find.text('Xóa')),
        );
        expect(find.text('Xóa địa chỉ Văn phòng?'), findsOneWidget);
        await tapVisible(tester, find.text('Giữ lại'));
        expect(
          container.read(accountDetailsProvider).requireValue.addresses.length,
          2,
        );
        await tapVisible(
          tester,
          find.descendant(of: officeRow, matching: find.text('Xóa')),
        );
        await tapVisible(tester, find.text('Xác nhận'));
        final remaining = container.read(accountDetailsProvider).requireValue;
        expect(remaining.addresses.length, 1);
        expect(remaining.defaultAddressId, remaining.addresses.single.id);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
