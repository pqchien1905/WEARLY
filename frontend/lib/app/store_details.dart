class StoreDetails {
  StoreDetails.fromJson(Object? json)
    : values = Map.unmodifiable({
        for (final entry in defaults.entries)
          entry.key: json is Map && json[entry.key] is String
              ? json[entry.key] as String
              : entry.value,
      });
  final Map<String, String> values;
  String operator [](String key) => values[key] ?? '';
  static const defaults = {
    'name': 'WEARLY',
    'tagline': 'Bản demo chạy local',
    'email': '',
    'phone': '',
    'address': '',
    'about':
        'WEARLY là cửa hàng minh họa chạy trên máy local. Catalog và ảnh dùng để trải nghiệm các chức năng; chưa đại diện cho hoạt động bán hàng thực tế.',
    'privacy':
        'Tài khoản, địa chỉ, đơn hàng và yêu cầu hỗ trợ được lưu trên máy chủ local. Phiên đăng nhập dùng cookie HttpOnly và có thể tiếp tục sau khi tải lại trang; đăng xuất để thu hồi phiên. Stylist gửi nội dung lựa chọn tới Google Gemini sau khi bạn đồng ý. Thử đồ chỉ lưu ảnh và gửi ảnh người/trang phục tới Gemini sau các bước đồng ý riêng. Ảnh riêng tư cần đăng nhập để xem, có thời hạn lưu và có thể xóa trong phòng thử; xóa hoặc hết hạn chặn truy cập, việc dọn bytes được xử lý nền. Thư hỗ trợ nằm trong hộp thư local. Hạn chế dùng dữ liệu cá nhân thật trong bản thử nghiệm.',
    'terms':
        'Đây là bản demo local. VNPay dùng môi trường thử nghiệm, vận chuyển được mô phỏng và COD được xác nhận thu tiền bằng thao tác đối soát có phân quyền. Kết quả Gemini chỉ hỗ trợ tham khảo, không xác nhận độ vừa vặn hay chất lượng sản phẩm. Không có cam kết giao hàng thực tế hoặc tự động hoàn tiền ngoài hệ thống.',
  };
  static const shipping =
      'Vận chuyển trên máy local được mô phỏng; phí hiển thị tại bước thanh toán. VNPay dùng sandbox. Với COD, trạng thái đã giao không tự xác nhận đã thu tiền: nhân viên có quyền phải đối soát. Yêu cầu trả hàng cần được duyệt và ghi nhận hàng nhận lại trước khi xử lý hoàn tiền. Chưa có giao hàng hoặc thu tiền thực tế.';
  static const fields = [
    (key: 'name', label: 'Tên cửa hàng', max: 80, lines: 1),
    (key: 'tagline', label: 'Mô tả ngắn', max: 160, lines: 1),
    (
      key: 'email',
      label: 'Email cửa hàng (không bắt buộc)',
      max: 254,
      lines: 1,
    ),
    (key: 'phone', label: 'Điện thoại (không bắt buộc)', max: 40, lines: 1),
    (key: 'address', label: 'Địa chỉ (không bắt buộc)', max: 300, lines: 2),
    (key: 'about', label: 'Giới thiệu cửa hàng', max: 5000, lines: 4),
    (key: 'privacy', label: 'Quyền riêng tư', max: 5000, lines: 4),
    (key: 'terms', label: 'Điều khoản sử dụng', max: 5000, lines: 4),
  ];
}
