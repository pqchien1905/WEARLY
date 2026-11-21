# Đánh giá sản phẩm

Mở sản phẩm trong cửa hàng trực tuyến, chọn **Xem đánh giá**. Khách chưa đăng nhập vẫn xem được nội dung và điểm trung bình; **Đăng nhập để đánh giá** đưa trở lại đúng sản phẩm sau đăng nhập.

Chỉ tài khoản có đơn **đã giao** chứa sản phẩm đó mới được gửi đánh giá. Đơn đang chờ, đang giao hoặc đã hủy không đủ điều kiện. Quyền này được kiểm tra tại máy chủ; việc đối soát COD không quyết định quyền đánh giá. Đăng nhập quản trị riêng không tự đăng nhập khách hàng.

Mỗi tài khoản có một đánh giá cho mỗi sản phẩm: chọn 1–5 sao và viết nội dung tối đa 2000 ký tự. Theo lựa chọn của chủ cửa hàng, đánh giá hiển thị ngay sau khi gửi. Nhãn người viết là **Khách đã mua hàng**; API công khai không trả tên, email, mã tài khoản hoặc thông tin đơn. Người viết tự chịu trách nhiệm không đưa thông tin liên hệ vào nội dung.

Chủ đánh giá có thể sửa hoặc xóa, có xác nhận trước khi xóa. Nếu dữ liệu đã đổi ở tab khác, phải tải lại trước khi thao tác tiếp. Nếu mất phản hồi, **Kiểm tra lại** lấy trạng thái từ máy chủ; không tự gửi lại lệnh. Danh sách và điểm trung bình cập nhật sau thao tác, kể cả khi phiên khách hàng kết thúc trong lúc chờ phản hồi. Nếu phản hồi đến sau thời gian chờ, ứng dụng làm mới dữ liệu thêm lần nữa khi nhận được phản hồi đó. Trình duyệt khác cần tải lại để thấy thay đổi.

Vào **Tài khoản → Đánh giá của tôi** (`/#/account/reviews`) để xem toàn bộ đánh giá đã viết, phân trang 5 mục. Tìm theo tên sản phẩm/nội dung, kết hợp lọc 1–5 sao trên toàn bộ lịch sử. Đóng hoặc lưu hộp thoại giữ nguyên trang; xóa mục cuối tự về trang còn dữ liệu. Thay đổi chưa lưu có xác nhận bỏ bản nháp. Tải lại lỗi giữ danh sách cũ để đọc, khóa sửa/xóa cho đến khi tải thành công. Khách chưa đăng nhập được đưa tới form khách hàng và trở lại đúng trang sau đăng nhập. Đăng xuất/đổi tài khoản loại bỏ danh sách cũ. Chế độ demo không tạo lịch sử đánh giá giả.

Sản phẩm bị ẩn hoặc không có SKU đang bán không có trang đánh giá công khai. Trong **Đánh giá của tôi**, nội dung của khách vẫn hiện dưới nhãn **Sản phẩm không còn mở bán**, không tiết lộ tên/đường dẫn sản phẩm đang ẩn; khách được xóa nhưng không sửa. Sản phẩm active hết tồn kho vẫn có thể sửa đánh giá nếu đã mua. Đánh giá cũ không có đơn đã giao vẫn thuộc lịch sử cá nhân để xóa, nhưng không được sửa hoặc tính vào danh sách/điểm công khai.

## API

Các đường dẫn sau có tiền tố `/api/v1/products/:productId/reviews`; `productId` là UUID.

| Method | Đường dẫn | Nội dung |
|---|---|---|
| GET | `/` | Public, `page=1&limit=5`, tối đa20/trang; items, total, page, limit, average (null khi rỗng) |
| GET | `/me` | Bearer khách hàng, `{review,canReview}` |
| POST | `/` | `{rating,comment}`; cần đơn đã giao, trùng đánh giá trả409 |
| PATCH | `/me` | `{rating,comment,expectedUpdatedAt}`; phiên bản cũ trả409 |
| DELETE | `/me` | `{expectedUpdatedAt}`; chỉ xóa của mình, lặp lại khi đã xóa vẫn thành công |

`expectedUpdatedAt` phải giữ nguyên giá trị `updatedAt` máy chủ trả về, dạng UTC `YYYY-MM-DDTHH:mm:ss.sssZ`. Dạng khác trả400 trước khi truy vấn dữ liệu. Giới hạn nội dung 2000 ký tự được tính theo Unicode code point ở cả API và Flutter, bao gồm emoji.

GET `/api/v1/users/me/reviews?page=1&limit=5` yêu cầu Bearer; chỉ lấy người dùng từ phiên đăng nhập, không nhận userId. Nhận thêm `q` (tối đa 100 ký tự, tìm từng từ không phân biệt hoa/thường, có phân biệt dấu) và `rating` (số nguyên 1–5). Mỗi từ phải xuất hiện trong nội dung hoặc tên sản phẩm đang mở bán; tên sản phẩm ẩn không tham gia tìm kiếm. Các ký tự `%`, `_` được tìm như văn bản thường. Trả `{items,total,page,limit}` với mỗi item gồm các trường đánh giá, `productId`, `product: {name,slug,image} | null`, `canEdit`. `total` là số kết quả sau lọc; tối đa20 mục/trang, mới nhất trước với id làm tie-break. Count và dữ liệu cùng snapshot. Các thao tác sửa/xóa dùng endpoint theo productId ở bảng trên; máy chủ kiểm tra lại điều kiện và phiên bản.

Chưa có hàng đợi duyệt, ảnh đính kèm, phản hồi của cửa hàng, thông báo email hoặc tùy chọn sắp xếp. Danh sách đánh giá công khai ở sản phẩm chưa có bộ lọc sao. Migrations thêm index cho truy vấn theo sản phẩm và theo người dùng, không xóa hay chuyển dữ liệu.

## Kiểm thử

`powershell -NoProfile -File tools/test-backend.ps1` chạy PostgreSQL E2E riêng. `node tools/test-frontend-api.cjs --reviews` tạo hai tài khoản và một đơn kiểm thử, đặt trạng thái đã giao làm điều kiện đầu vào, chạy Flutter release/Chrome, ẩn/khôi phục đúng sản phẩm fixture để thử xóa từ lịch sử cá nhân, rồi dọn đúng dữ liệu lượt chạy. Không đổi đơn/sản phẩm thật của người dùng. Ảnh/log tại `.tools/api-reviews-verification` (ignored). Sau đó `./tools/frontend.ps1 build-api` khôi phục API localhost3000 cho bản build thường.
