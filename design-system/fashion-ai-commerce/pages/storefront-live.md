# Cửa hàng kết nối API

Áp dụng cho trang chủ, cửa hàng, bộ sưu tập, chi tiết sản phẩm và footer.
Giữ màu mận/ink/canvas, Manrope và Be Vietnam Pro, khoảng cách và responsive
theo MASTER. Không thêm bộ màu hoặc font riêng cho trang mới.

- Cửa hàng chỉ trình bày sản phẩm mở bán, có biến thể hoạt động và ảnh.
- Ảnh thẻ dùng contain để giữ đủ dáng giày, túi và trang phục; khung 3:4 giữ
  geometry khi tải. Ảnh bìa và tên đến từ API, không nhân bản để lấp grid.
- Size giày, Freesize và phong cách lấy từ toàn bộ catalog, không lấy từ trang
  phân trang hiện tại. Lựa chọn đã chọn vẫn thấy được để có thể xóa bộ lọc.
- Tìm kiếm trong trang giữ danh mục/sắp xếp, xóa số trang cũ; hỗ trợ Enter và nút
  có nhãn. Trạng thái hết hàng lấy từ tất cả biến thể, giá khác nhau có tiền tố “Từ”.
- Bộ sưu tập chọn theo phong cách, ảnh bìa lấy từ kết quả API. Khi không có hàng
  hoặc kết nối lỗi, hiển thị trạng thái rỗng/thử lại thay cho hàng mẫu.
- Footer đăng ký nhận tin có nhãn email, đồng ý rõ ràng, trạng thái đang gửi,
  thành công và lỗi có thể thử lại. Không thông báo thành công trước phản hồi API.
- Tài khoản có gợi ý autofill, Enter gửi form; đăng ký/đăng nhập giữ đường dẫn
  mua sắm đang thực hiện. Tiêu đề thu nhỏ trên điện thoại.
- Bỏ nhãn demo khỏi dữ liệu API; giữ thông tin đúng về dịch vụ ngoài hệ thống
  chưa được cấu hình. Nguồn gốc catalog cũ được lưu trong tài liệu nhập hàng.
