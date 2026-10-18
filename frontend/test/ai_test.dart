import 'package:flutter_test/flutter_test.dart';
import 'package:nep_storefront/data/mock_ai.dart';
import 'package:nep_storefront/data/mock_catalog.dart';
import 'package:nep_storefront/domain/ai.dart';

void main() {
  test('stylist recommendations fit total budget, size and catalog', () async {
    final catalog = MockProductRepository(latency: Duration.zero);
    final repo = MockStylistRepository(catalog, latency: Duration.zero);
    final reply = await repo.reply(
      const StylistRequest(
        prompt: 'Đi làm tối giản',
        budget: 1300000,
        size: 'M',
      ),
    );
    expect(reply.products, isNotEmpty);
    expect(reply.total, lessThanOrEqualTo(1300000));
    expect(
      reply.products.every(
        (p) =>
            catalog.products.any((x) => x.id == p.id) &&
            p.variants.any((v) => v.size == 'M' && v.stock > 0),
      ),
      isTrue,
    );
  });
  test('try-on requires consent and has ordered status lifecycle', () async {
    final repo = MockTryOnRepository(latency: Duration.zero);
    await expectLater(
      repo.create(consent: false, sku: 'WRL-1-MAIN-M').toList(),
      throwsArgumentError,
    );
    expect(
      (await repo.create(consent: true, sku: 'WRL-1-MAIN-M').toList()).map(
        (j) => j.status,
      ),
      [TryOnStatus.queued, TryOnStatus.processing, TryOnStatus.succeeded],
    );
  });
  test('cancelled try-on never emits a successful result', () async {
    final repo = MockTryOnRepository(latency: Duration.zero);
    final statuses = <TryOnStatus>[];
    await for (final job in repo.create(consent: true, sku: 'WRL-1-MAIN-M')) {
      statuses.add(job.status);
      if (job.status == TryOnStatus.processing) {
        repo.cancel();
      }
    }
    expect(statuses, contains(TryOnStatus.cancelled));
    expect(statuses, isNot(contains(TryOnStatus.succeeded)));
  });
}
