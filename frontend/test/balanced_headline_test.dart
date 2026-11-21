import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/features/home/home_hero.dart';

void main() {
  Future<RenderParagraph> pump(
    WidgetTester t,
    String text,
    double width,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: width,
            child: BalancedHeadline(
              text,
              style: const TextStyle(fontSize: 72, height: 1.1),
              minSize: 32,
            ),
          ),
        ),
      ),
    );
    return t.renderObject<RenderParagraph>(find.text(text));
  }

  int lines(RenderParagraph p) => p
      .getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: p.text.toPlainText().length),
      )
      .map((b) => b.top.round())
      .toSet()
      .length;

  testWidgets('long banners shrink to fit three lines without overflow', (
    t,
  ) async {
    const text = 'WEARLY — tủ đồ đương đại cho mỗi ngày và mọi dịp trong năm.';
    final p = await pump(t, text, 1200);
    expect(lines(p), lessThanOrEqualTo(3));
    expect((p.text.style?.fontSize ?? 72), lessThan(72));
    expect(p.didExceedMaxLines, isFalse);
    expect(t.takeException(), isNull);
  });

  testWidgets('short banners keep the largest size', (t) async {
    final p = await pump(t, 'Mặc theo cách bạn.', 900);
    expect(p.text.style?.fontSize, 72);
  });

  testWidgets('wrapping is balanced instead of leaving one word', (t) async {
    const text = 'WEARLY — tủ đồ đương đại cho mỗi ngày.';
    final p = await pump(t, text, 700);
    final n = lines(p);
    expect(n, greaterThan(1));
    // Narrowed to the tightest width that keeps the same line count.
    expect(p.size.width, lessThan(700));
  });

  testWidgets('explicit line breaks are kept', (t) async {
    const text = 'WEARLY —\ntủ đồ đương đại\ncho mỗi ngày.';
    final p = await pump(t, text, 900);
    expect(lines(p), 3);
  });
}
