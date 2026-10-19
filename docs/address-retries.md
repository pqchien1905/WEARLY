# Thử lại tạo địa chỉ

POST `/api/v1/users/me/addresses` nhận header tùy chọn `Idempotency-Key` dài16–128 ký tự ASCII chữ/số/gạch ngang/gạch dưới. Client cũ không gửi header vẫn hoạt động nhưng không được bảo đảm chống trùng khi gửi lại.

Với cùng tài khoản và mã, cùng nội dung trả địa chỉ hiện có; nội dung khác trả409 `IDEMPOTENCY_CONFLICT`. Replay không ghi đè sửa đổi mới hoặc đổi địa chỉ mặc định. Nếu địa chỉ đã xóa, trả410 `ADDRESS_REMOVED`, không tạo lại. Mã của tài khoản khác độc lập. GET và response không trả hash/receipt.

Hash SHA256 gồm recipient, phone, address, label (mặc định Nhà) và isDefault (mặc định false), theo thứ tự cố định. Receipt và địa chỉ được ghi trong cùng transaction có khóa user. Bảng `AddressCreateReceipt` giữ mã và hash, không sao chép nội dung địa chỉ; FK địa chỉ dùng SET NULL, FK user dùng CASCADE. Migration chỉ thêm bảng/index/FK.

Flutter tạo mã ngẫu nhiên cho mỗi form tạo mới. Repository giữ nội dung POST theo mã trong suốt phiên, kể cả quyết định đặt địa chỉ đầu tiên làm mặc định. Điều này bảo vệ cả trường hợp controller từ chối kết quả do hồ sơ được tải lại đồng thời. Lỗi mạng/timeout hoặc đọc lại thất bại giữ nguyên mã và nội dung. Form khóa trường nhập và cho **Thử lại yêu cầu này**; không tự gửi lại. Lỗi400 trước khi xác nhận tạo cho phép sửa dữ liệu. Phiên thay đổi không được gửi bản nháp cũ sang tài khoản mới; phản hồi đến muộn chỉ làm mới cache của cùng phiên khi không có lần tạo/thử lại đang chạy. Lần thử lại đang chạy tự đọc lại sổ địa chỉ, tránh tự vô hiệu hóa kết quả của chính nó.

Mã đang chờ nằm trong phiên trình duyệt, không ghi thông tin địa chỉ ra localStorage. Nếu đóng form hoặc tải lại trang, kiểm tra sổ địa chỉ trước khi tạo yêu cầu mới. Hai yêu cầu có mã khác nhau vẫn có thể lưu cùng nội dung một cách có chủ ý. PATCH/xóa địa chỉ giữ hợp đồng hiện có.

Kiểm chứng: backend E2E PostgreSQL kiểm tra concurrent replay, hash conflict, ownership, replay sau sửa/đổi mặc định/xóa và tương thích client cũ. Flutter kiểm tra giữ payload/default/key, chặn đổi bản nháp, phản hồi muộn/phiên cũ và retry UI. `node tools/test-frontend-api.cjs` cố ý làm mất phản hồi POST **sau khi API thật đã trả201**, rồi xác nhận chỉ một địa chỉ và hoàn tất luồng COD.
