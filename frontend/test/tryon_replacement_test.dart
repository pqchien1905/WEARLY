import 'dart:async';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/app/app.dart';
import 'package:nep_storefront/app/providers.dart';
import 'package:nep_storefront/core/widgets/primitives.dart';
import 'package:nep_storefront/data/mock_catalog.dart';

class DelayedPhoto extends XFile {
  DelayedPhoto() : super('replacement.jpg');
  final data = Completer<Uint8List>();
  @override
  Future<int> length() async => 1024;
  @override
  Future<Uint8List> readAsBytes() => data.future;
}

class PhotoPicker extends FileSelectorPlatform {
  PhotoPicker(this.first, this.second);
  final XFile first, second;
  int calls = 0;
  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => calls++ == 0 ? first : second;
}

void main() {
  testWidgets(
    'try-on cannot start against an old photo while replacement is reading',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final original = FileSelectorPlatform.instance;
      addTearDown(() => FileSelectorPlatform.instance = original);
      final image = (await rootBundle.load(
        'assets/images/shirt.jpg',
      )).buffer.asUint8List();
      final replacement = DelayedPhoto();
      FileSelectorPlatform.instance = PhotoPicker(
        XFile.fromData(image, name: 'first.jpg'),
        replacement,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productRepositoryProvider.overrideWithValue(
              MockProductRepository(latency: Duration.zero),
            ),
          ],
          child: NepApp(
            router: createRouter(initialLocation: '/virtual-try-on'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Chọn ảnh từ thiết bị'));
        for (
          var i = 0;
          i < 100 && find.text('Đổi ảnh').evaluate().isEmpty;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
        }
      });
      expect(find.text('Đổi ảnh'), findsOneWidget);
      await tester.tap(find.text('Chọn màu và size'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trắng / M').last);
      await tester.pumpAndSettle();
      final consent = find.byType(CheckboxListTile).first;
      await tester.ensureVisible(consent);
      await tester.tap(consent);
      await tester.pumpAndSettle();
      final run = find.widgetWithText(AppButton, 'Tạo bản thử đồ demo');
      expect(tester.widget<AppButton>(run).onPressed, isNotNull);
      await tester.ensureVisible(find.text('Đổi ảnh'));
      await tester.tap(find.text('Đổi ảnh'));
      await tester.pump();
      expect(tester.widget<AppButton>(run).onPressed, isNull);
      // Completing after leaving must not restore a private image or result.
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        replacement.data.complete(image);
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
