import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/core/widgets/motion_widgets.dart';

void main() {
  Widget host(Widget child, {bool reduced = false}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Scaffold(body: Center(child: child)),
    ),
  );

  testWidgets('reduced motion shows route content on the first frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const PageReveal(child: Text('Ready to shop')), reduced: true),
    );
    final fade = tester.widget<FadeTransition>(
      find.descendant(
        of: find.byType(PageReveal),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fade.opacity.value, 1);
    expect(find.text('Ready to shop').hitTestable(), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('enabling reduced motion interrupts an entrance immediately', (
    tester,
  ) async {
    await tester.pumpWidget(host(const PageReveal(child: Text('Shop'))));
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpWidget(
      host(const PageReveal(child: Text('Shop')), reduced: true),
    );
    final fade = tester.widget<FadeTransition>(
      find.descendant(
        of: find.byType(PageReveal),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fade.opacity.value, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid hover changes keep the image frame stable and clickable', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 200,
          height: 260,
          child: InteractivePhoto(
            onTap: () => taps++,
            child: const ColoredBox(color: Colors.grey),
          ),
        ),
      ),
    );
    final photo = find.byType(InteractivePhoto);
    final rect = tester.getRect(photo);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(rect.center);
    await tester.pump(const Duration(milliseconds: 60));
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(milliseconds: 40));
    await mouse.moveTo(rect.center);
    await tester.pumpAndSettle();
    expect(tester.getRect(photo), rect);
    await tester.tap(photo);
    expect(taps, 1);
    await mouse.removePointer();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reduced motion keeps hover still and keyboard activation works',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 200,
            height: 260,
            child: InteractivePhoto(
              onTap: () => taps++,
              child: const Text('View garment'),
            ),
          ),
          reduced: true,
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(InteractivePhoto)));
      await tester.pumpAndSettle();
      final scale = tester.widget<ScaleTransition>(
        find.descendant(
          of: find.byType(InteractivePhoto),
          matching: find.byType(ScaleTransition),
        ),
      );
      expect(scale.scale.value, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(taps, 1);
      await mouse.removePointer();
    },
  );
}
