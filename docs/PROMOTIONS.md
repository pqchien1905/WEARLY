# Khuyến mãi local

Trong quản trị, mở **Khuyến mãi** để tạo hoặc chỉnh sửa mã. Mã dùng 3–32 ký tự
chữ/số/gạch ngang/gạch dưới và không đổi tên sau khi tạo. Có thể tắt mã đã dùng;
đơn cũ vẫn giữ đúng mã và số tiền đã giảm.

- Chọn giảm tiền VND hoặc phần trăm nguyên từ 1 đến 100. Giảm phần trăm làm tròn
  xuống VND, không vượt giá sản phẩm hoặc mức giảm tối đa đã cấu hình.
- Phí giao hàng tính theo giá sản phẩm trước giảm. Mã không giảm phí vận chuyển.
- Có mức chi tối thiểu, thời gian bắt đầu/hết hạn, giới hạn tổng lượt và mỗi khách.
  Ngày giờ nhập theo UTC+7. Để trống tổng lượt nghĩa là không giới hạn tổng.
- Khách áp dụng mã ở thanh toán. Thay đổi giỏ hoặc cách giao hàng cần áp dụng lại.
  Xem trước không giữ lượt; máy chủ kiểm tra lại khi tạo đơn.
- Tạo đơn giữ một lượt. Hủy đơn đang chờ trả lại lượt, đồng thời hoàn tồn kho.
  Gửi lại yêu cầu đặt đơn không giữ thêm lượt. Đơn đã xử lý vẫn giữ lịch sử dùng mã.
- Tổng bằng 0 hiển thị **Không cần thanh toán**, không tạo giao dịch VNPay hay
  biên nhận COD. Tổng dương được thu đúng số tiền sau giảm.
- Nếu người khác đã sửa mã, tải lại dữ liệu trước khi lưu để tránh ghi đè.

Kiểm chứng: `node tools/test-frontend-api.cjs --promotions` dùng cơ sở dữ liệu
kiểm thử riêng, tạo mã qua Chrome, đặt đơn giảm giá và hủy đơn để kiểm tra trả lượt.
Không gửi giao dịch đến dịch vụ thanh toán hay tạo vận đơn thật.
