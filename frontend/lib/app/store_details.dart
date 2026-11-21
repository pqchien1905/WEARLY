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
    'tagline': 'Tủ đồ đương đại, theo cách bạn.',
    'email': '',
    'phone': '',
    'address': '',
    'about':
        'Khám phá những thiết kế, màu sắc và cách phối dành cho phong cách riêng của bạn. WEARLY giúp bạn lưu sản phẩm yêu thích, chọn kích cỡ, theo dõi đơn hàng và tìm cảm hứng cho tủ đồ mỗi ngày.',
    'privacy':
        'Tài khoản, địa chỉ, đơn hàng, yêu cầu hỗ trợ và đăng ký nhận tin được lưu trên máy chủ. Phiên đăng nhập dùng cookie HttpOnly; đăng xuất để thu hồi phiên. Email khôi phục được gửi tới địa chỉ tài khoản. Khi dịch vụ Gemini được bật, Stylist chỉ gửi nội dung lựa chọn sau khi bạn đồng ý; phòng thử yêu cầu đồng ý riêng trước khi tải ảnh và tạo kết quả. Ảnh riêng tư cần đăng nhập để xem, có thời hạn lưu và có thể xóa trong phòng thử. Xóa hoặc hết hạn chặn truy cập, việc dọn tệp được xử lý nền.',
    'terms':
        'Giá và tồn kho được kiểm tra lại khi đặt hàng. COD được xác nhận thu tiền bằng thao tác đối soát có phân quyền. VNPay, MoMo và ZaloPay hiện dùng môi trường thử nghiệm; theo dõi vận chuyển chưa kết nối với đơn vị giao hàng bên ngoài. Kết quả Gemini chỉ hỗ trợ tham khảo, không xác nhận độ vừa vặn hay chất lượng sản phẩm. Không có tự động giao hàng hoặc hoàn tiền ngoài hệ thống.',
  };
  static const shipping =
      'Vận chuyển trên máy local được mô phỏng; phí hiển thị tại bước thanh toán. VNPay, MoMo và ZaloPay dùng sandbox. Với COD, trạng thái đã giao không tự xác nhận đã thu tiền: nhân viên có quyền phải đối soát. Yêu cầu trả hàng cần được duyệt và ghi nhận hàng nhận lại trước khi xử lý hoàn tiền. Chưa có giao hàng hoặc thu tiền thực tế.';
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
