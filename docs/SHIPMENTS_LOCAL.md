# Theo dõi vận chuyển local

Đơn vị mặc định là **Mô phỏng vận chuyển local**. Các thao tác dưới đây chỉ ghi
nhận dữ liệu thử nghiệm trong hệ thống; không đặt đơn giao hàng vật lý.

1. Trong quản trị, mở đơn và **Xác nhận đơn**. Đơn VNPay cần xác minh đã thanh toán.
2. Chọn **Bắt đầu giao hàng**. Hệ thống tạo mã `LOCAL-…` và lưu mốc đang vận chuyển.
3. Có thể cập nhật **Đang giao đến khách**, **Giao thất bại**, hoặc **Đánh dấu đã giao**.
4. Khi giao thất bại, chọn **Giao lại** để tiếp tục. Nếu kiện hàng đã quay về, chọn
   **Xác nhận hàng hoàn về kho** sau khi nhận đủ toàn bộ hàng. Thao tác này trả tồn
   kho một lần và kết thúc vận đơn. Ghi chú nhập tại đây hiển thị cho khách.

Giao thành công vẫn để COD chờ **Đối soát COD**. Hoàn kiện COD chưa thu sẽ hủy khoản
phải thu. Tiền đã thu trước đó vẫn giữ nguyên, cần quy trình hoàn tiền riêng.
Mã khuyến mãi trên đơn đã gửi đi vẫn tính là đã dùng.

Khách xem mã vận đơn, ghi chú và lịch sử trong **Tài khoản → Đơn hàng → Chi tiết**.
Thời gian hiển thị UTC+7. Đơn cũ không được tự tạo các mốc lịch sử chưa từng ghi nhận.
Khi gặp xung đột phiên bản hoặc mất phản hồi, tải lại dữ liệu trước thao tác tiếp.

Kiểm chứng tự động: `node tools/test-frontend-api.cjs --shipments`. Chrome thực hiện
giao thất bại, giao lại, hoàn kho và giao thành công; kiểm tra lịch sử khách hàng
trên desktop/mobile và cơ sở dữ liệu thử nghiệm riêng. Không gọi hãng vận chuyển.

GHN sandbox là lựa chọn adapter ngoài nếu cần kiểm thử với tài khoản sandbox sau
này. Phiên bản local hiện tại không cần khóa dịch vụ vận chuyển.
