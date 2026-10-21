# Gemini trên máy local

Stylist dùng Gemini thật khi backend có khóa. Không có khóa, màn hình báo dịch vụ
chưa được cấu hình và không tạo phản hồi giả. Thử đồ bằng ảnh riêng tư là mốc tiếp
theo, chưa được tính là hoàn tất trong phần Stylist này.

## Cấu hình

Đặt các biến trong `backend/.env`, rồi khởi động lại backend:

```dotenv
GEMINI_API_KEY=
GEMINI_STYLIST_MODEL=gemini-3.5-flash-lite
AI_STYLIST_USER_DAILY_LIMIT=20
AI_STYLIST_GLOBAL_DAILY_LIMIT=200
AI_STYLIST_ESTIMATE_VND=500
AI_GLOBAL_DAILY_ESTIMATE_VND=100000
```

Điền khóa riêng của bạn ở dòng đầu. Không đưa khóa vào Flutter, Git hay nội dung
chat. Tên model có thể đổi theo quyền truy cập của tài khoản Google. Kiểm tra
[danh sách model chính thức](https://ai.google.dev/gemini-api/docs/models) khi đổi.

Các số tiền trên là **ước tính do người vận hành đặt**, dùng để giới hạn tổng
yêu cầu local; không phải hóa đơn Google và không thu thêm từ khách mua hàng.
Chi phí thực tế, gói miễn phí và hạn mức của tài khoản cần kiểm tra tại Google.
Hạn mức được đặt lại lúc00:00 UTC (07:00 tại Việt Nam/Thái Lan).

## Cách dùng

Đăng nhập khách hàng, mở `/ai-stylist`, nhập dịp phối đồ, size, ngân sách và màu
nếu muốn giới hạn. Có thể dùng hồ sơ phong cách đã lưu. Đọc nội dung đồng ý gửi
thông tin tới Google Gemini rồi bấm “Nhờ Gemini gợi ý”.

Backend chỉ gửi tối đa40 SKU đang hoạt động/còn hàng. Kết quả tối đa4 sản phẩm,
mỗi sản phẩm một SKU. Giá, size, màu, tồn kho và tổng ngân sách được đối chiếu
lại tại backend; model không được tự cung cấp giá hay tạo SKU ngoài danh sách.
Gợi ý không giữ chỗ tồn kho và chưa bao gồm phí vận chuyển. Mở trang sản phẩm để
chọn mua theo tình trạng hiện tại.

Nếu mất phản hồi, dùng “Kiểm tra / thử lại yêu cầu”. Trang đọc lại cùng mã yêu cầu;
khi máy chủ chưa nhận mã đó, gửi lại đúng mã và nội dung cũ. Không tự tạo lượt
Gemini thứ hai. Kết quả chưa rõ sau lỗi hoặc khởi động lại backend được đánh dấu
không xác định; “Yêu cầu mới” là một lượt mới và phải do bạn chủ động bấm.

Yêu cầu đã được tiếp nhận tính vào hạn mức, kể cả lỗi/không rõ kết quả. Giới hạn
đồng thời là2 yêu cầu mỗi người và8 toàn hệ thống. Yêu cầu không hợp lệ, chưa có
khóa hoặc không có sản phẩm phù hợp chưa được tính lượt. Mỗi lần gọi Google có
giới hạn20giây, bao gồm đọc phản hồi; không tự gọi lại dịch vụ khi lỗi.

Trang giữ mã đang theo dõi trong bộ nhớ. Tải lại trang không tự tạo lượt mới;
nút tạo yêu cầu mới là hành động chủ động. Phiên đăng nhập vẫn được khôi phục
theo hướng dẫn `BROWSER_SESSIONS_LOCAL.md`.

## Dữ liệu và kiểm chứng

Nội dung yêu cầu chỉ được lưu dưới dạng hash để kiểm tra gửi trùng. Phản hồi AI
và SKU đã chọn được lưu tối đa24giờ; sau đó bị xóa khi đọc hoặc trong đợt dọn dẹp
mỗi5phút. Nhật ký tối thiểu về model, trạng thái, token đã dùng, hash và ước tính
chi phí được giữ để tính hạn mức. API đọc kết quả chỉ cho chính chủ, không cache.

Kết nối dùng [Gemini Interactions v1](https://ai.google.dev/api/interactions-api-v1),
`store:false`, không history/tools/background. Khóa chỉ nằm trong header backend;
không ghi nội dung yêu cầu, ảnh, khóa hay phản hồi lỗi thô vào log. `store:false`
là cấu hình lưu tương tác của API; chính sách xử lý dữ liệu của Google vẫn áp dụng.

```powershell
powershell.exe -NoProfile -File tools/test-backend.ps1 -WithWorker -WithStorage
node tools/test-frontend-api.cjs --stylist
```

Kiểm thử chỉ dùng tài khoản/dữ liệu tạo riêng trong database `_test`. Gemini HTTP
trong kịch bản Chrome là phản hồi kiểm thử có kiểm soát để chứng minh consent,
giá/tồn kho, mất phản hồi, hạn mức và quyền đọc; không chứng minh tài khoản Google
đã kết nối thành công. Chỉ ghi nhận kiểm chứng Gemini thật sau khi có khóa và đã
quan sát một phản hồi từ dịch vụ. Không có khóa vẫn chạy được các kiểm thử local.
