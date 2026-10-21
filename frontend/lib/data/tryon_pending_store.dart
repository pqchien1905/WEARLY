import 'dart:convert';
import '../core/network/api_client.dart';

/// Only opaque operation/image IDs and the selected SKU; never image bytes,
/// tokens, filenames, prompts or private URLs.
class PendingTryOn {
  const PendingTryOn(this.key, {this.imageId, this.sku});
  final String key;
  final String? imageId, sku;
  String encode() => jsonEncode({'key': key, 'imageId': imageId, 'sku': sku});
  static PendingTryOn? decode(String? value) {
    if (value == null) return null;
    try {
      final row = jsonDecode(value) as Map;
      final key = row['key'] as String;
      final image = row['imageId'] as String?, sku = row['sku'] as String?;
      final uuid = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
      );
      if (!uuid.hasMatch(key) ||
          (image != null && !uuid.hasMatch(image)) ||
          (sku != null && (sku.isEmpty || sku.length > 100)) ||
          (image == null) != (sku == null)) {
        throw const FormatException();
      }
      return PendingTryOn(key, imageId: image, sku: sku);
    } catch (_) {
      throw recoveryUnavailable;
    }
  }
}

const recoveryUnavailable = ApiException(
  'TRYON_RECOVERY_UNAVAILABLE',
  'Chưa lưu hoặc đọc được mã khôi phục. Hãy cho phép bộ nhớ trang web rồi tải lại phòng thử.',
);

abstract interface class TryOnPendingStore {
  PendingTryOn? read(String owner, String kind);
  void save(String owner, String kind, PendingTryOn value);
  void clear(String owner, String kind, String key);
}

class MemoryTryOnPendingStore implements TryOnPendingStore {
  final values = <String, PendingTryOn>{};
  @override
  PendingTryOn? read(String owner, String kind) => values['$owner:$kind'];
  @override
  void save(String owner, String kind, PendingTryOn value) =>
      values['$owner:$kind'] = value;
  @override
  void clear(String owner, String kind, String key) {
    if (values['$owner:$kind']?.key == key) values.remove('$owner:$kind');
  }
}
