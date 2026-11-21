# Bộ sưu tập

Áp dụng MASTER: Manrope cho tiêu đề, Be Vietnam Pro cho nội dung; màu ink,
plum, canvas và surface dùng token `T`, không thêm palette riêng.

- Index: breadcrumb, tiêu đề 52 px desktop/36 px mobile, mô tả và tổng số từ API.
- Hai cột khi chiều rộng nội dung từ 700 px, một cột dưới ngưỡng đó; khoảng
  ngang 32 px, dọc 40 px. Thẻ ảnh tỷ lệ 4:3, contain, giữ nguyên sản phẩm.
- Số thiết kế trên ảnh, phong cách nhỏ màu accent, tiêu đề 32/28 px, mô tả
  muted, nút khám phá có nhãn riêng. Ảnh nhấn được có semantics rõ nghĩa.
- Detail: quay lại danh sách; hero nền canvas, tiêu đề 48/36 px, ảnh 300 px
  bên phải ở màn rộng và xếp dưới nội dung ở màn hẹp. Không lặp ảnh giả để lấp chỗ.
- Thanh điều khiển tự xuống hàng: số kết quả, chip còn hàng, dropdown sắp xếp.
  ProductGrid tái sử dụng thẻ sản phẩm và chọn size của cửa hàng, tối đa 4 cột.
- Phân trang bằng nút có nhãn, giữ query. Mọi nguồn dữ liệu từ API PostgreSQL;
  loading, error/retry, empty và missing là trạng thái riêng.
- Admin dùng AdminCard và AdminMutationDialog hiện có; chọn ảnh từ sản phẩm
  thật cùng phong cách, preview contain; URL readonly sau tạo; lỗi lưu hiện
  trong form, xung đột bắt buộc tải lại trước lần lưu tiếp.

Đã xem ảnh chụp Chrome thực tế ở 1440, 768 và 375 px; không tràn bố cục, không
ảnh fallback. Chi tiết kiểm chứng: `docs/COLLECTIONS_COMPLETION_2026-10-23.md`.
