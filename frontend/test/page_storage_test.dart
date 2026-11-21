import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/app/app.dart';
import 'account_journeys_test.dart' show signedIn;

void main() {
  testWidgets('account menu keeps expansion separate from style page scroll', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 750);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = await signedIn(tester);
    addTearDown(container.dispose);
    final router = createRouter(initialLocation: '/account/style');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: NepApp(router: router),
      ),
    );
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const PageStorageKey('/account/style')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    final bucket = PageStorage.of(scroll.context);
    scroll.position.jumpTo(300);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(375, 812);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final menu = find.byKey(
      const PageStorageKey('account-menu-/account/style'),
    );
    await tester.ensureVisible(menu);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: menu, matching: find.byType(ListTile)).first,
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Expansible>(find.byType(Expansible).first)
          .controller
          .isExpanded,
      isTrue,
    );
    expect(bucket.readState(scroll.context), isA<double>());
    for (final width in [1440.0, 768.0, 1440.0, 375.0]) {
      tester.view.physicalSize = Size(width, 812);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (width < 920) {
        expect(
          tester
              .widget<Expansible>(find.byType(Expansible).first)
              .controller
              .isExpanded,
          isTrue,
        );
      }
    }
  });

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
