# Trả hàng và hủy đơn local

Khách hàng có thể yêu cầu trả một phần hoặc toàn bộ sản phẩm trong 7 ngày kể từ
sự kiện giao hàng được hệ thống ghi nhận. Đơn phải đã thanh toán; COD phải có đối
soát thu tiền trước. Đơn cũ thiếu ngày giao không được tự suy đoán thời hạn.

Trong chi tiết đơn, nhập số lượng và lý do, xem số tiền dự kiến rồi gửi yêu cầu.
Mỗi đơn có tối đa một yêu cầu đang chờ duyệt hoặc chờ nhận hàng. Yêu cầu bị từ chối
không tiêu hao số lượng được trả. Sau khi nhận trả một phần, khách có thể gửi tiếp
cho phần còn lại nếu còn thời hạn. Khi mất phản hồi, nút thử lại sử dụng đúng yêu
cầu ban đầu, kể cả sau khi rời rồi mở lại chi tiết đơn trong cùng phiên.

Admin duyệt hoặc từ chối, sau đó xác nhận thực tế đã nhận hàng. Chỉ lần xác nhận
nhận đầu tiên hoàn kho; gửi lặp không cộng kho lần nữa. Ghi chú của admin hiển thị
cho khách. Hoàn kho và hoàn tiền là hai bước riêng biệt.

Tiền hàng được trả tính theo giá đơn gốc sau giảm giá, phân bổ bằng số nguyên VND.
Các lần trả một phần cộng lại không vượt tiền hàng sau giảm giá. Phí vận chuyển
được giữ lại khi khách trả hàng sau giao. Đơn miễn phí không tạo khoản hoàn tiền.

Khách được hủy đơn đang chờ xác nhận; admin được hủy trước khi giao vận với lý do
và phiên bản đơn hiện hành. Đơn đã thu tiền giữ nguyên bản ghi thanh toán để xử lý
hoàn tiền riêng. Phải đối chiếu giao dịch VNPay còn chờ trước khi hủy. Hủy hoàn kho
và giải phóng lượt mã giảm giá đúng một lần.

Kiểm chứng: 131 kiểm thử API PostgreSQL, 29 unit backend, 343 Flutter (2 kiểm thử
opt-in bỏ qua); lint/build/analyze sạch. Chrome thực hiện yêu cầu trả một phần có
giảm giá, duyệt, nhận, tải lại và hủy đơn đã thu tiền. Các giao dịch trong bài
kiểm thử là dữ liệu tổng hợp ở DB test, không chứng minh kết nối VNPay thật.

Số tiền dự kiến hoàn chưa phải biên nhận hoàn tiền. Sau khi nhận hàng, thực hiện
quy trình riêng tại [REFUNDS_LOCAL.md](REFUNDS_LOCAL.md).
