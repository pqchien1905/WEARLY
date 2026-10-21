import '../core/network/api_client.dart';
import '../domain/ai.dart';
import '../domain/catalog.dart';
import 'remote_catalog.dart';

const invalidStylistResponse = ApiException(
  'INVALID_RESPONSE',
  'Dữ liệu gợi ý chưa hợp lệ. Hãy kiểm tra lại kết quả.',
);
int _amount(Object? value) {
  final text = value.toString();
  final amount = int.tryParse(text);
  if (!RegExp(r'^\d+$').hasMatch(text) ||
      amount == null ||
      amount > 9007199254740991) {
    throw invalidStylistResponse;
  }
  return amount;
}

class StylistAvailability {
  const StylistAvailability({
    required this.configured,
    required this.used,
    required this.limit,
    required this.remaining,
    required this.estimatedUsed,
    required this.estimatedPerRequest,
    required this.resetsAt,
  });
  final bool configured;
  final int used, limit, remaining, estimatedUsed, estimatedPerRequest;
  final DateTime resetsAt;
}

class StylistPick {
  const StylistPick(this.product, this.variant);
  final Product product;
  final ProductVariant variant;
}

class StylistReceipt {
  const StylistReceipt({
    required this.id,
    required this.requestKey,
    required this.status,
    required this.estimatedCost,
    this.errorCode,
    this.message,
    this.total = 0,
    this.picks = const [],
  });
  final String id, requestKey, status;
  final String? errorCode, message;
  final int total, estimatedCost;
  final List<StylistPick> picks;
  bool get pending => status == 'processing';
}

class RemoteStylistRepository {
  RemoteStylistRepository(this.api);
  final ApiClient api;
  Future<StylistAvailability> status() async {
    final response = await api.get('ai/status');
    try {
      final s = (response as Map)['stylist'] as Map;
      if (s['costIsEstimate'] != true) throw invalidStylistResponse;
      return StylistAvailability(
        configured: s['configured'] as bool,
        used: _amount(s['used']),
        limit: _amount(s['limit']),
        remaining: _amount(s['remaining']),
        estimatedUsed: _amount(s['estimatedUsedVnd']),
        estimatedPerRequest: _amount(s['estimatedPerRequestVnd']),
        resetsAt: DateTime.parse(s['resetsAt'] as String),
      );
    } catch (_) {
      throw invalidStylistResponse;
    }
  }

  Future<StylistReceipt> create(
    String key,
    StylistRequest request, {
    required bool consent,
  }) async => _receipt(
    await api.request(
      'POST',
      'ai/stylist/requests',
      headers: {'Idempotency-Key': key},
      body: {
        'prompt': request.prompt,
        'budget': request.budget,
        'size': request.size,
        'style': request.style,
        'color': request.color,
        'consent': consent,
      },
    ),
  );
  Future<StylistReceipt> get(String key) async => _receipt(
    await api.get('ai/stylist/requests/${Uri.encodeComponent(key)}'),
  );
  StylistReceipt _receipt(Object? response) {
    try {
      final data = response as Map;
      final status = data['status'] as String;
      if (!['processing', 'completed', 'failed', 'unknown'].contains(status)) {
        throw invalidStylistResponse;
      }
      final result = data['result'];
      final picks = <StylistPick>[];
      var total = 0;
      String? message;
      if (result != null) {
        if (status != 'completed' || result['currency'] != 'VND') {
          throw invalidStylistResponse;
        }
        total = _amount(result['total']);
        message = result['message'] as String;
        for (final pick in result['picks'] as List) {
          final product = RemoteProductRepository.productFromJson(
            pick['product'] as Map<String, dynamic>,
          );
          final variant = product.variants.singleWhere(
            (v) => v.sku == pick['sku'],
          );
          if (!product.active ||
              variant.stock < 1 ||
              variant.price != _amount(pick['price'])) {
            throw invalidStylistResponse;
          }
          picks.add(StylistPick(product, variant));
        }
        if (picks.isEmpty ||
            picks.length > 4 ||
            picks.map((p) => p.product.id).toSet().length != picks.length ||
            picks.fold<int>(0, (sum, p) => sum + p.variant.price) != total) {
          throw invalidStylistResponse;
        }
      }
      return StylistReceipt(
        id: data['id'] as String,
        requestKey: data['requestKey'] as String,
        status: status,
        estimatedCost: _amount(data['estimatedCostVnd']),
        errorCode: data['errorCode'] as String?,
        message: message,
        total: total,
        picks: picks,
      );
    } catch (_) {
      throw invalidStylistResponse;
    }
  }
}

String stylistError(Object error) {
  final code = error is ApiException ? error.code : error.toString();
  return switch (code) {
    'AI_PROVIDER_NOT_CONFIGURED' =>
      'Gemini đang chờ cửa hàng kích hoạt. Bạn có thể xem sản phẩm trong lúc chờ.',
    'AI_NO_CATALOG_MATCH' =>
      'Chưa có sản phẩm còn hàng theo size, màu và ngân sách này. Hãy điều chỉnh lựa chọn.',
    'AI_CATALOG_CHANGED' =>
      'Giá hoặc tồn kho đã thay đổi. Hãy tạo yêu cầu mới để nhận gợi ý phù hợp.',
    'AI_DAILY_LIMIT' =>
      'Đã hết hạn mức AI hôm nay. Hãy quay lại sau thời điểm đặt lại hạn mức.',
    'AI_BUSY' =>
      'Đang có yêu cầu khác được xử lý. Hãy đợi một chút rồi thử lại.',
    'AI_PROVIDER_RATE_LIMIT' =>
      'Gemini đang giới hạn lượt dùng. Bạn có thể tạo yêu cầu mới sau.',
    'AI_OUTCOME_UNKNOWN' || 'PROVIDER_TIMEOUT' =>
      'Chưa xác định được kết quả từ Gemini. Lượt này đã được ghi nhận; chỉ tạo yêu cầu mới khi bạn muốn thử thêm.',
    'AI_RESULT_EXPIRED' =>
      'Gợi ý đã hết thời gian lưu 24 giờ. Bạn có thể tạo yêu cầu mới.',
    'INVALID_PROVIDER_OUTPUT' =>
      'Gemini chưa trả được gợi ý phù hợp với catalog và ngân sách. Bạn có thể tạo yêu cầu mới.',
    'AI_PROVIDER_AUTH' =>
      'Chưa xác thực được dịch vụ Gemini. Cửa hàng cần kiểm tra cấu hình.',
    'SESSION_CHANGED' => 'Tài khoản đã thay đổi. Hãy mở lại Stylist.',
    _ =>
      'Chưa nhận được kết quả. Dùng nút kiểm tra để lấy lại yêu cầu cũ trước khi thử thêm.',
  };
}
