import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/app/app.dart';

void main() {
  for (final route in [
    '/products/nep-1',
    '/ai-stylist',
    '/virtual-try-on?product=nep-1',
    '/login',
    '/faq',
  ]) {
    testWidgets('$route keeps expansion state separate from page scrolling', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 750);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          child: NepApp(router: createRouter(initialLocation: route)),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      final pageScroll = find
          .descendant(
            of: find.byKey(PageStorageKey(route)),
            matching: find.byType(Scrollable),
          )
          .first;
      final scrollState = tester.state<ScrollableState>(pageScroll);
      final bucket = PageStorage.of(scrollState.context);
      final firstTile = find.byType(ExpansionTile).first;

      final offset = math.min(
        834.9332637389532,
        scrollState.position.maxScrollExtent,
      );
      expect(offset, greaterThan(0));
      scrollState.position.jumpTo(offset);
      await tester.pumpAndSettle();

      // Docking DevTools changes the responsive tree after the page has scrolled.
      tester.view.physicalSize = const Size(600, 750);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Opening a section must never replace the saved numeric scroll offset.
      await tester.ensureVisible(firstTile);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: firstTile, matching: find.byType(ListTile)),
      );
      await tester.pumpAndSettle();
      expect(bucket.readState(scrollState.context), isA<double>());

      scrollState.position.jumpTo(offset);
      await tester.pumpAndSettle();

      for (final width in [600.0, 1440.0, 375.0, 1440.0]) {
        tester.view.physicalSize = Size(width, 750);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final sections = tester.widgetList<Expansible>(find.byType(Expansible));
        expect(sections.first.controller.isExpanded, isTrue);
        expect(
          sections.skip(1).every((section) => !section.controller.isExpanded),
          isTrue,
        );
        expect(bucket.readState(scrollState.context), isA<double>());
      }
    });
  }
}
