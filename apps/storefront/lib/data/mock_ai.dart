import '../domain/ai.dart';
import '../domain/catalog.dart';

class MockStylistRepository implements StylistRepository {
  MockStylistRepository(
    this.catalog, {
    this.latency = const Duration(milliseconds: 900),
  });
  final ProductRepository catalog;
  final Duration latency;
  @override
  Future<StylistReply> reply(
    StylistRequest request, {
    String scenario = 'success',
  }) async {
    await Future<void>.delayed(latency);
    if (scenario != 'success') {
      throw StateError(
        scenario == 'timeout'
            ? 'Stylist chưa trả lời trong thời gian chờ mô phỏng. Thử lại.'
            : 'Không tạo được gợi ý trong kịch bản lỗi demo. Thử lại.',
      );
    }
    final keyword = request.prompt.toLowerCase();
    final style = request.style.isNotEmpty
        ? request.style
        : keyword.contains('tối giản')
        ? 'Tối giản'
        : keyword.contains('thanh lịch')
        ? 'Thanh lịch'
        : '';
    final page = await catalog.list(
      ProductQuery(
        size: request.size,
        color: request.color,
        style: style,
        maxPrice: request.budget,
        inStock: true,
        limit: 100,
        sort: 'price-asc',
      ),
    );
    final chosen = <Product>[];
    var remaining = request.budget;
    final categories = <String>{};
    final candidates =
        page.items
            .map((p) {
              final matching =
                  p.variants
                      .where(
                        (v) =>
                            v.size == request.size &&
                            v.stock > 0 &&
                            (request.color.isEmpty ||
                                v.color == request.color) &&
                            v.price <= request.budget,
                      )
                      .toList()
                    ..sort((a, b) => a.price.compareTo(b.price));
              return p.copyWith(variants: matching);
            })
            .where((p) => p.variants.isNotEmpty)
            .toList()
          ..sort((a, b) => a.price.compareTo(b.price));
    for (final p in candidates) {
      if (p.price <= remaining && !categories.contains(p.category)) {
        chosen.add(p);
        categories.add(p.category);
        remaining -= p.price;
      }
      if (chosen.length == 3) {
        break;
      }
    }
    return StylistReply(
      chosen.isEmpty
          ? 'Chưa tìm được món đồ phù hợp với size và ngân sách này. Bạn có thể tăng ngân sách hoặc đổi bộ lọc.'
          : 'Với kế hoạch “${request.prompt}”, hãy bắt đầu bằng ${chosen.first.name.toLowerCase()}. ${chosen.length > 1 ? 'Kết hợp các món bên cạnh để tạo một tổng thể dễ mặc.' : 'Giữ các món còn lại đơn giản để thiết kế này làm điểm nhấn.'} Tất cả lựa chọn còn size ${request.size}; tổng nằm trong ngân sách bạn chọn. Đây là tư vấn mô phỏng từ catalog.',
      chosen,
    );
  }
}

class MockTryOnRepository implements TryOnRepository {
  MockTryOnRepository({this.latency = const Duration(seconds: 1)});
  final Duration latency;
  int generation = 0;
  @override
  Stream<TryOnJob> create({
    required bool consent,
    required String sku,
    String scenario = 'success',
  }) async* {
    if (!consent || sku.isEmpty) {
      throw ArgumentError(
        'Cần chọn biến thể và đồng ý xử lý ảnh trong phiên demo.',
      );
    }
    final token = ++generation;
    final id = 'tryon-${DateTime.now().microsecondsSinceEpoch}-$token';
    yield TryOnJob(id, TryOnStatus.queued);
    await Future<void>.delayed(latency);
    if (token != generation) {
      yield TryOnJob(id, TryOnStatus.cancelled);
      return;
    }
    yield TryOnJob(id, TryOnStatus.processing);
    await Future<void>.delayed(latency);
    if (token != generation) {
      yield TryOnJob(id, TryOnStatus.cancelled);
      return;
    }
    yield TryOnJob(
      id,
      scenario == 'success' ? TryOnStatus.succeeded : TryOnStatus.failed,
      error: scenario == 'timeout'
          ? 'Hết thời gian xử lý mô phỏng.'
          : 'Kịch bản xử lý lỗi mô phỏng.',
    );
  }

  @override
  void cancel() {
    generation++;
  }
}
