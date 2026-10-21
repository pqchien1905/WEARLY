# Hoàn tiền COD và VNPay sandbox

Sau khi nhận hàng trả hoặc hủy đơn đã thu tiền, mở chi tiết đơn trong quản trị và
xem mục **Hoàn tiền**. Hệ thống tính số tiền từ đơn gốc và biên nhận; không nhập số
tiền tùy ý. Trả hàng sau giao giữ lại phí vận chuyển. Hủy trước giao hoặc vận đơn
hoàn về kho được hoàn cả phí giao. Tiền giảm giá không được hoàn lần nữa.

## COD

Chỉ có nguồn hoàn khi hệ thống đã ghi biên nhận thu COD. Sau khi thực tế trả tiền
cho khách, bấm **Ghi nhận hoàn COD**, nhập mã biên nhận riêng và xác nhận. Đây là
ghi nhận nghiệp vụ thủ công, không tự chuyển tiền qua ngân hàng. Mã biên nhận
không được dùng cho khoản hoàn khác. Gửi lặp cùng yêu cầu không ghi thêm khoản.

## VNPay thử nghiệm

Cần cấu hình sandbox theo `VNPAY_SANDBOX.md`. Mỗi lần thu thành công là một nguồn
tiền riêng; khoản thu thêm có thể hoàn riêng mà không sửa lần thanh toán ban đầu.

1. Chọn **Hoàn qua VNPay sandbox** ở đúng nguồn tiền. Hệ thống lưu mã yêu cầu trước
   khi gửi cổng. Cùng một yêu cầu chỉ được gửi ra cổng một lần.
2. `VNPay đang xử lý hoàn` chưa có nghĩa khách nhận tiền. `Cần xác minh kết quả hoàn`
   giữ số tiền để đối chiếu; không tạo khoản mới cho cùng nguồn khi còn khoản chờ.
3. Bấm **Kiểm tra kết quả hoàn**. Nếu chưa có mã giao dịch hoàn do mất phản hồi,
   tra trong cổng sandbox theo mã yêu cầu VNPay hiển thị rồi nhập mã giao dịch hoàn.
   Mã giao dịch thanh toán ban đầu không thay thế được mã hoàn. Chờ 10 giây giữa
   các lần truy vấn. Truy vấn không gửi thêm lệnh hoàn tiền.
4. Chỉ phản hồi có chữ ký và đúng nguồn, số tiền, loại giao dịch cùng định danh
   mới được ghi nhận. Phản hồi tạo khoản hoàn phải chứa đúng nội dung mang mã yêu
   cầu. Sai hoặc chưa xác minh được vẫn giữ khoản chờ. Chỉ từ chối đã xác minh mới
   giải phóng số tiền cho yêu cầu mới.

Nếu tiến trình dừng giữa lúc lưu và gửi, khoản chờ cũng cần đối chiếu. Hệ thống
chủ động không gửi lại một lệnh có khả năng đã được VNPay xử lý. Trường hợp không
tra được bằng mã yêu cầu cần kiểm tra trên sandbox; không tự đổi trạng thái trong DB.

## Trạng thái và báo cáo

Hoàn một phần khoản thu chính đặt thanh toán thành `Đã hoàn một phần`. Chỉ khi
toàn bộ khoản thu chính được hoàn mới là `Đã hoàn tiền`. Hoàn tiền không cộng kho;
việc nhận hàng trả đã xử lý tồn kho riêng. Khách xem các biên nhận và khoản chờ ở
chi tiết đơn; mã yêu cầu nội bộ và nguồn đối chiếu chỉ hiện cho admin.

Báo cáo tách tiền thu tổng, khoản thu thêm, tiền hoàn có biên nhận và tiền còn lại
đã xác định. Đơn cũ ghi `REFUNDED` nhưng thiếu sổ hoàn mới nằm ở **Hoàn cũ cần đối
chiếu**: không cộng vào tiền còn lại đã xác định và không tự tạo biên nhận giả.

Kiểm thử giao thức dùng phản hồi tổng hợp có chữ ký và Chrome dùng cổng mô phỏng
trong tiến trình test, không gọi VNPay thật. Cần chạy nghiệm thu với tài khoản
sandbox đã cấu hình để xác nhận quyền hoàn và khả năng phản hồi của nhà cung cấp.

Giao thức tham chiếu: [VNPay querydr/refund](https://sandbox.vnpayment.vn/apis/docs/truy-van-hoan-tien/querydr%26refund.html).
