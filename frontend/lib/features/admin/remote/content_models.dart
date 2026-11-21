import '../../../app/store_details.dart';
import '../../../core/network/api_client.dart';
import 'admin_providers.dart';

const contentGroups = ['Trang chủ', 'Giới thiệu', 'Liên hệ', 'Chính sách'];
const contentFields = [
  (
    key: 'banner',
    label: 'Tiêu đề trang chủ',
    max: 120,
    lines: 2,
    group: 0,
    required: true,
  ),
  (
    key: 'name',
    label: 'Tên cửa hàng',
    max: 80,
    lines: 1,
    group: 0,
    required: true,
  ),
  (
    key: 'tagline',
    label: 'Mô tả ngắn',
    max: 160,
    lines: 2,
    group: 0,
    required: false,
  ),
  (
    key: 'about',
    label: 'Giới thiệu cửa hàng',
    max: 5000,
    lines: 6,
    group: 1,
    required: false,
  ),
  (
    key: 'email',
    label: 'Email cửa hàng (không bắt buộc)',
    max: 254,
    lines: 1,
    group: 2,
    required: false,
  ),
  (
    key: 'phone',
    label: 'Điện thoại (không bắt buộc)',
    max: 40,
    lines: 1,
    group: 2,
    required: false,
  ),
  (
    key: 'address',
    label: 'Địa chỉ (không bắt buộc)',
    max: 300,
    lines: 3,
    group: 2,
    required: false,
  ),
  (
    key: 'policy',
    label: 'Nội dung chính sách',
    max: 5000,
    lines: 6,
    group: 3,
    required: true,
  ),
  (
    key: 'privacy',
    label: 'Quyền riêng tư',
    max: 5000,
    lines: 6,
    group: 3,
    required: false,
  ),
  (
    key: 'terms',
    label: 'Điều khoản sử dụng',
    max: 5000,
    lines: 6,
    group: 3,
    required: false,
  ),
];
Map<String, String> contentValues(AdminRecord row) => {
  'banner': row['banner'] as String? ?? '',
  'policy': row['policy'] as String? ?? '',
  ...StoreDetails.fromJson(row['details']).values,
};
String? contentValidation(String key, String value) {
  final field = contentFields.firstWhere((f) => f.key == key);
  final text = value.trim();
  if (field.required && text.isEmpty) return 'Vui lòng nhập thông tin.';
  if (text.length > field.max) return 'Tối đa ${field.max} ký tự.';
  if (key == 'email' &&
      text.isNotEmpty &&
      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) {
    return 'Email không hợp lệ.';
  }
  return null;
}

bool contentDiffers(Map<String, String> a, Map<String, String> b) =>
    contentFields.any((f) => a[f.key] != b[f.key]);
String contentError(Object error) {
  if (error is ApiException) {
    if (error.code == 'VERSION_CONFLICT') {
      return 'Nội dung đã thay đổi. Tải lại bản đã lưu trước khi tiếp tục.';
    }
    if (error.code == 'ALREADY_PUBLISHED' ||
        error.code == 'CONTENT_UNCHANGED') {
      return 'Bản nháp đã giống nội dung công khai. Tải lại để xem trạng thái mới nhất.';
    }
    if (error.code == 'CONTENT_NOT_PUBLISHED') {
      return 'Chưa có nội dung công khai để khôi phục.';
    }
    return error.message;
  }
  return 'Chưa xác định được kết quả. Tải lại bản đã lưu trước khi thao tác tiếp.';
}
