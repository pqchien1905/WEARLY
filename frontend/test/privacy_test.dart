import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/features/virtual_tryon/private_image.dart';

void main() {
  testWidgets('private photo eviction removes retained image cache key', (
    tester,
  ) async {
    final data = await rootBundle.load('assets/images/shirt.jpg');
    final bytes = data.buffer.asUint8List();
    final provider = MemoryImage(bytes);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Image(image: provider)),
      ),
    );
    await tester.pumpAndSettle();
    final key = await provider.obtainKey(ImageConfiguration.empty);
    expect(
      PaintingBinding.instance.imageCache.statusForKey(key).tracked,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await evictPrivateImage(bytes);
    expect(
      PaintingBinding.instance.imageCache.statusForKey(key).tracked,
      isFalse,
    );
  });
}
