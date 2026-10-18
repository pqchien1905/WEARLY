# Đánh giá sản phẩm

Mở sản phẩm trong cửa hàng trực tuyến, chọn **Xem đánh giá**. Khách chưa đăng nhập vẫn xem được nội dung và điểm trung bình; **Đăng nhập để đánh giá** đưa trở lại đúng sản phẩm sau đăng nhập.

Chỉ tài khoản có đơn **đã giao** chứa sản phẩm đó mới được gửi đánh giá. Đơn đang chờ, đang giao hoặc đã hủy không đủ điều kiện. Quyền này được kiểm tra tại máy chủ; việc đối soát COD không quyết định quyền đánh giá. Đăng nhập quản trị riêng không tự đăng nhập khách hàng.

Mỗi tài khoản có một đánh giá cho mỗi sản phẩm: chọn 1–5 sao và viết nội dung tối đa 2000 ký tự. Theo lựa chọn của chủ cửa hàng, đánh giá hiển thị ngay sau khi gửi. Nhãn người viết là **Khách đã mua hàng**; API công khai không trả tên, email, mã tài khoản hoặc thông tin đơn. Người viết tự chịu trách nhiệm không đưa thông tin liên hệ vào nội dung.

Chủ đánh giá có thể sửa hoặc xóa, có xác nhận trước khi xóa. Nếu dữ liệu đã đổi ở tab khác, phải tải lại trước khi thao tác tiếp. Nếu mất phản hồi, **Kiểm tra lại** lấy trạng thái từ máy chủ; không tự gửi lại lệnh. Danh sách và điểm trung bình cập nhật sau thao tác, kể cả khi phiên khách hàng kết thúc trong lúc chờ phản hồi. Trình duyệt khác cần tải lại để thấy thay đổi.

Sản phẩm bị ẩn hoặc không có SKU đang bán không có trang đánh giá công khai. API riêng vẫn cho chủ tài khoản đọc/xóa đánh giá đã có, nhưng không thêm/sửa khi sản phẩm bị ẩn. UI đánh giá hiện nằm trên trang sản phẩm đang mở bán; chưa có trang riêng tập hợp đánh giá cá nhân. Dữ liệu cũ không có đơn đã giao không được tính vào danh sách/điểm công khai.

## API

Các đường dẫn sau có tiền tố `/api/v1/products/:productId/reviews`; `productId` là UUID.

| Method | Đường dẫn | Nội dung |
|---|---|---|
| GET | `/` | Public, `page=1&limit=5`, tối đa20/trang; items, total, page, limit, average (null khi rỗng) |
| GET | `/me` | Bearer khách hàng, `{review,canReview}` |
| POST | `/` | `{rating,comment}`; cần đơn đã giao, trùng đánh giá trả409 |
| PATCH | `/me` | `{rating,comment,expectedUpdatedAt}`; phiên bản cũ trả409 |
| DELETE | `/me` | `{expectedUpdatedAt}`; chỉ xóa của mình, lặp lại khi đã xóa vẫn thành công |

Chưa có hàng đợi duyệt, ảnh đính kèm, phản hồi của cửa hàng, thông báo email hoặc sắp xếp/lọc theo sao. Migration chỉ thêm index cho truy vấn đánh giá theo sản phẩm, không xóa hay chuyển dữ liệu.

## Kiểm thử

`powershell -NoProfile -File tools/test-backend.ps1` chạy PostgreSQL E2E riêng. `node tools/test-frontend-api.cjs --reviews` tạo hai tài khoản và một đơn kiểm thử, đặt trạng thái đã giao làm điều kiện đầu vào, chạy Flutter release/Chrome và dọn đúng dữ liệu lượt chạy. Không đổi đơn thật của người dùng. Ảnh/log tại `.tools/api-reviews-verification` (ignored). Sau đó `./tools/frontend.ps1 build-api` khôi phục API localhost3000 cho bản build thường.
