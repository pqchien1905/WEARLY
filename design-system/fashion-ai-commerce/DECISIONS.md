# Decisions

- 15/10/2026: Chọn NẾP (placeholder) và concept A sau so sánh. Thương hiệu/chính sách đổi qua config.
- Một Flutter app, hai shell storefront/admin; giảm trùng provider và giữ một nguồn catalog. Production RBAC vẫn thuộc backend.
- Riverpod dependency injection, typed immutable domain, async interfaces; mocks giữ state trong phiên. Không localStorage cho ảnh/PII.
- Tiền int VND; variant SKU và stock là nguồn chuẩn; checkout lưu snapshot, xác minh lại kho/giá.
- Thêm package vừa đủ: go_router, flutter_riverpod, file_selector. Chưa thêm dio/codegen khi chưa có remote adapter.
- Hash URL mặc định để static hosting deep links hoạt động; query filter/sort đi cùng URL, browser history dùng được.
- Demo shipping 30.000đ, miễn phí từ 1.500.000đ, express 50.000đ; cấu hình tập trung. Không hứa chính sách thật.
- Không có Git/Flutter trong PATH ban đầu. Chuẩn bị toolchain local, không thay PATH hệ thống. Workspace chưa là Git repo; không tạo worktree giả hoặc commit khi chưa có cấu hình tác giả.
- User đã yêu cầu tự chọn concept và triển khai ngay: không thêm vòng phê duyệt concept/plan. Theo dev-flow, implement inline.

- 16/10/2026: Theo yêu cầu đổi sang tên tiếng Anh, chọn **Wearly** (wordmark `wearly`), gợi trang phục hằng ngày và phù hợp góc Stylist. Đổi brand config, metadata web, favicon, email demo và prefix SKU/đơn demo sang WRL. Giữ slug kỹ thuật `nep-*` để các deep-link đang dùng tiếp tục hoạt động. Tên này là lựa chọn thiết kế, chưa xác minh nhãn hiệu hoặc tên miền.
