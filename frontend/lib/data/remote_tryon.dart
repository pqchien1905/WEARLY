import 'dart:typed_data';
import '../core/network/api_client.dart';

const _invalid = ApiException(
  'INVALID_RESPONSE',
  'Dữ liệu thử đồ chưa hợp lệ. Hãy tải lại.',
);
int _number(Object? value) {
  final text = value.toString(), parsed = int.tryParse(value.toString());
  if (!RegExp(r'^\d+$').hasMatch(text) ||
      parsed == null ||
      parsed > 9007199254740991) {
    throw _invalid;
  }
  return parsed;
}

class RemoteTryOnStatus {
  const RemoteTryOnStatus({
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

class PrivateImageAsset {
  const PrivateImageAsset({
    required this.id,
    required this.mimeType,
    required this.createdAt,
    required this.expiresAt,
    this.requestKey,
  });
  final String id, mimeType;
  final String? requestKey;
  final DateTime createdAt, expiresAt;
}

typedef TryOnProduct = ({
  String name,
  String slug,
  String? image,
  bool tryOnSupported,
});

class RemoteTryOnJob {
  const RemoteTryOnJob({
    required this.id,
    required this.imageId,
    required this.sku,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    required this.estimatedCost,
    required this.resultAvailable,
    this.requestKey,
    this.errorCode,
    this.product,
    this.size,
    this.color,
  });
  final String id, imageId, sku, status;
  final String? requestKey, errorCode;
  final TryOnProduct? product;
  final String? size, color;
  final DateTime createdAt, expiresAt;
  final int estimatedCost;
  final bool resultAvailable;
  bool get pending => status == 'pending' || status == 'processing';
}

class RemoteTryOnRepository {
  RemoteTryOnRepository(this.api);
  final ApiClient api;
  Future<({String state, PrivateImageAsset? image})> uploadStatus(
    String key,
  ) async {
    final value = await api.get(
      'uploads/images/requests/${Uri.encodeComponent(key)}',
    );
    try {
      final row = value as Map, state = row['state'] as String;
      if (![
        'missing',
        'processing',
        'available',
        'unavailable',
      ].contains(state)) {
        throw _invalid;
      }
      final image = state == 'available' ? _image(row['image']) : null;
      if (image != null && image.requestKey != key) throw _invalid;
      return (state: state, image: image);
    } catch (_) {
      throw _invalid;
    }
  }

  Future<RemoteTryOnStatus> status() async {
    final value = await api.get('ai/try-on/status');
    try {
      final row = value as Map;
      if (row['costIsEstimate'] != true) throw _invalid;
      return RemoteTryOnStatus(
        configured: row['configured'] as bool,
        used: _number(row['used']),
        limit: _number(row['limit']),
        remaining: _number(row['remaining']),
        estimatedUsed: _number(row['estimatedUsedVnd']),
        estimatedPerRequest: _number(row['estimatedPerRequestVnd']),
        resetsAt: DateTime.parse(row['resetsAt'] as String),
      );
    } catch (_) {
      throw _invalid;
    }
  }

  Future<List<PrivateImageAsset>> images() async {
    final value = await api.get('uploads/images');
    try {
      return ((value as Map)['items'] as List).map(_image).toList();
    } catch (_) {
      throw _invalid;
    }
  }

  Future<PrivateImageAsset> upload(
    String key,
    Uint8List bytes,
    String mimeType, {
    required bool consent,
  }) async => _image(
    await api.uploadImage(
      'uploads/images',
      bytes: bytes,
      mimeType: mimeType,
      fields: {'consent': '$consent'},
      key: key,
    ),
  );
  Future<List<RemoteTryOnJob>> jobs() async {
    final value = await api.get('ai/try-on/jobs');
    try {
      return ((value as Map)['items'] as List).map(_job).toList();
    } catch (_) {
      throw _invalid;
    }
  }

  Future<RemoteTryOnJob> create(
    String key,
    String imageId,
    String sku, {
    required bool consent,
  }) async => _job(
    await api.request(
      'POST',
      'ai/try-on/jobs',
      headers: {'Idempotency-Key': key},
      body: {'imageId': imageId, 'sku': sku, 'consent': consent},
    ),
  );
  Future<RemoteTryOnJob> get(String id) async =>
      _job(await api.get('ai/try-on/jobs/${Uri.encodeComponent(id)}'));
  Future<Uint8List> photo(String id) =>
      api.getBytes('uploads/images/${Uri.encodeComponent(id)}/content');
  Future<Uint8List> result(String id) =>
      api.getBytes('ai/try-on/jobs/${Uri.encodeComponent(id)}/result');
  Future<void> deleteImage(String id) async {
    await api.request('DELETE', 'uploads/images/${Uri.encodeComponent(id)}');
  }

  PrivateImageAsset _image(Object? value) {
    try {
      final row = value as Map;
      final type = row['mimeType'] as String;
      if (!['image/jpeg', 'image/png'].contains(type)) throw _invalid;
      return PrivateImageAsset(
        id: row['id'] as String,
        requestKey: row['requestKey'] as String?,
        mimeType: type,
        createdAt: DateTime.parse(row['createdAt'] as String),
        expiresAt: DateTime.parse(row['expiresAt'] as String),
      );
    } catch (_) {
      throw _invalid;
    }
  }

  RemoteTryOnJob _job(Object? value) {
    try {
      final row = value as Map, state = row['status'] as String;
      if (!['pending', 'processing', 'completed', 'failed'].contains(state)) {
        throw _invalid;
      }
      final result = row['resultAvailable'] as bool;
      if (result && state != 'completed') throw _invalid;
      final product = row['product'] as Map?;
      return RemoteTryOnJob(
        id: row['id'] as String,
        imageId: row['imageId'] as String,
        sku: row['sku'] as String,
        size: row['size'] as String?,
        color: row['color'] as String?,
        product: product == null
            ? null
            : (
                name: product['name'] as String,
                slug: product['slug'] as String,
                image: product['image'] as String?,
                tryOnSupported: product['tryOnSupported'] as bool,
              ),
        requestKey: row['requestKey'] as String?,
        errorCode: row['errorCode'] as String?,
        status: state,
        estimatedCost: _number(row['estimatedCostVnd']),
        resultAvailable: result,
        createdAt: DateTime.parse(row['createdAt'] as String),
        expiresAt: DateTime.parse(row['expiresAt'] as String),
      );
    } catch (_) {
      throw _invalid;
    }
  }
}

String tryonError(Object error) {
  final code = error is ApiException ? error.code : error.toString();
  return switch (code) {
    'AI_PROVIDER_NOT_CONFIGURED' => 'Gemini chưa được cửa hàng kích hoạt.',
    'AI_DAILY_LIMIT' =>
      'Đã hết hạn mức AI hôm nay. Vui lòng quay lại sau khi đặt lại hạn mức.',
    'AI_BUSY' => 'Đang có yêu cầu AI khác. Hãy kiểm tra lại sau ít phút.',
    'AI_PROVIDER_RATE_LIMIT' =>
      'Gemini đang giới hạn lượt dùng. Yêu cầu này đã kết thúc.',
    'AI_PROVIDER_UNAVAILABLE' =>
      'Dịch vụ thử đồ tạm thời không phản hồi. Lượt thử này chưa tạo được ảnh.',
    'AI_CATALOG_CHANGED' =>
      'Trang phục đã thay đổi hoặc hết hàng. Hãy chọn lại sản phẩm.',
    'AI_GARMENT_UNAVAILABLE' =>
      'Trang phục này chưa có ảnh phù hợp để thử. Hãy chọn sản phẩm khác.',
    'AI_QUEUE_EXPIRED' =>
      'Yêu cầu chờ xử lý quá lâu và đã kết thúc. Bạn có thể chủ động tạo lượt mới.',
    'AI_OUTCOME_UNKNOWN' || 'PROVIDER_TIMEOUT' || 'PROVIDER_ABORTED' =>
      'Chưa xác định được kết quả. Hệ thống không tự gọi Gemini thêm; tạo yêu cầu mới sẽ dùng một lượt khác.',
    'IMAGE_UNAVAILABLE' ||
    'AI_RESULT_EXPIRED' ||
    'UPLOAD_UNAVAILABLE' => 'Ảnh đã bị xóa hoặc hết thời gian lưu.',
    'UPLOAD_IN_PROGRESS' =>
      'Ảnh đang được lưu. Hãy kiểm tra lại ảnh đã gửi trước khi tải thêm.',
    'IMAGE_QUOTA_EXCEEDED' =>
      'Đã đạt giới hạn ảnh. Xóa ảnh không dùng và chờ hệ thống dọn dẹp.',
    'AI_IMAGE_QUOTA_EXCEEDED' => 'Ảnh này đã đạt giới hạn thử đồ.',
    'AI_REQUEST_LEGACY' =>
      'Yêu cầu cũ không thể chạy bằng Gemini. Hãy tạo một lượt mới nếu muốn thử.',
    'INVALID_PROVIDER_OUTPUT' =>
      'Gemini chưa trả về ảnh hợp lệ. Không tự tạo thêm lượt.',
    'TIMEOUT' || 'CONNECTION_ERROR' =>
      'Chưa nhận được phản hồi. Hãy kiểm tra lại yêu cầu đã gửi.',
    _ =>
      error is ApiException
          ? error.message
          : 'Chưa xử lý được yêu cầu. Vui lòng thử lại.',
  };
}
