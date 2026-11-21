# Thử lại tạo địa chỉ

POST `/api/v1/users/me/addresses` nhận header tùy chọn `Idempotency-Key` dài16–128 ký tự ASCII chữ/số/gạch ngang/gạch dưới. Client cũ không gửi header vẫn hoạt động nhưng không được bảo đảm chống trùng khi gửi lại.

Với cùng tài khoản và mã, cùng nội dung trả địa chỉ hiện có; nội dung khác trả409 `IDEMPOTENCY_CONFLICT`. Replay không ghi đè sửa đổi mới hoặc đổi địa chỉ mặc định. Nếu địa chỉ đã xóa, trả410 `ADDRESS_REMOVED`, không tạo lại. Mã của tài khoản khác độc lập. GET và response không trả hash/receipt.

Hash SHA256 gồm recipient, phone, address, label (mặc định Nhà) và isDefault (mặc định false), theo thứ tự cố định. Receipt và địa chỉ được ghi trong cùng transaction có khóa user. Bảng `AddressCreateReceipt` giữ mã và hash, không sao chép nội dung địa chỉ; FK địa chỉ dùng SET NULL, FK user dùng CASCADE. Migration chỉ thêm bảng/index/FK.

Flutter tạo mã ngẫu nhiên cho mỗi form tạo mới. Repository giữ nội dung POST theo mã trong suốt phiên, kể cả quyết định đặt địa chỉ đầu tiên làm mặc định. Điều này bảo vệ cả trường hợp controller từ chối kết quả do hồ sơ được tải lại đồng thời. Lỗi mạng/timeout hoặc đọc lại thất bại giữ nguyên mã và nội dung. Form khóa trường nhập và cho **Thử lại yêu cầu này**; không tự gửi lại. Lỗi400 trước khi xác nhận tạo cho phép sửa dữ liệu. Phiên thay đổi không được gửi bản nháp cũ sang tài khoản mới; phản hồi đến muộn chỉ làm mới cache của cùng phiên khi không có lần tạo/thử lại đang chạy. Lần thử lại đang chạy tự đọc lại sổ địa chỉ, tránh tự vô hiệu hóa kết quả của chính nó.

Mã đang chờ nằm trong phiên trình duyệt, không ghi thông tin địa chỉ ra localStorage. Nếu đóng form hoặc tải lại trang, kiểm tra sổ địa chỉ trước khi tạo yêu cầu mới. Hai yêu cầu có mã khác nhau vẫn có thể lưu cùng nội dung một cách có chủ ý. Lỗi409/410 yêu cầu kiểm tra lại sổ địa chỉ thay vì tiếp tục gửi cùng mã.

Máy chủ tự đặt địa chỉ mới làm mặc định khi chưa có mặc định, kể cả client không gửi `isDefault: true`. Xóa địa chỉ khóa cùng user như thao tác thêm/đổi mặc định; nếu còn địa chỉ nhưng không còn mặc định, chọn mục có `createdAt` sớm nhất (id tăng dần khi trùng thời gian). Việc xóa và chọn thay thế nằm trong một transaction; trình duyệt chỉ DELETE rồi đọc lại, không PATCH chọn thay thế. Địa chỉ trong đơn hàng đã tạo không thay đổi.

Trang sổ địa chỉ có tải lại, giữ dữ liệu cũ để đọc khi tải lỗi và khóa thay đổi đến khi cập nhật thành công. Form giới hạn tên gợi nhớ50, người nhận100, địa chỉ500 ký tự và số điện thoại10 chữ số bắt đầu bằng0; dữ liệu gửi đi được trim. Hủy bản nháp có xác nhận, lưu dữ liệu không đổi bị vô hiệu hóa. PATCH mất phản hồi phải kiểm tra lại trước khi sửa tiếp; phản hồi muộn của PATCH/DELETE làm mới cache của đúng phiên. Đổi tài khoản ẩn ngay form/hộp thoại xóa cũ. API chưa có kiểm tra phiên bản địa chỉ giữa hai tab; đây không phải cơ chế ngăn ghi đè đồng thời.

Kiểm chứng: backend E2E PostgreSQL kiểm tra concurrent replay, hash conflict, ownership, replay sau sửa/đổi mặc định/xóa và tương thích client cũ. Flutter kiểm tra giữ payload/default/key, chặn đổi bản nháp, phản hồi muộn/phiên cũ và retry UI. `node tools/test-frontend-api.cjs` cố ý làm mất phản hồi POST **sau khi API thật đã trả201**, rồi xác nhận chỉ một địa chỉ và hoàn tất luồng COD.

`node tools/verify-addresses-workflow-browser.cjs` kiểm tra trang8080 với khách tạm, lỗi mất phản hồi sau POST201, sửa/đổi mặc định/tải lại, lỗi tải danh sách, xác nhận xóa, xóa mặc định và màn hình320–2560px/nằm ngang. Hỗ trợ `ADDRESSES_TEST_BASE=http://localhost:5173` cho bản release. Tài khoản và dữ liệu thử được dọn sau chạy; ảnh/báo cáo ở `.tools/addresses-workflow/`.
