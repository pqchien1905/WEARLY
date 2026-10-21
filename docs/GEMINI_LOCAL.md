# Gemini trên máy local

Stylist và thử đồ bằng ảnh riêng tư dùng Gemini khi backend có khóa. Không có khóa,
màn hình báo dịch vụ chưa được cấu hình và không tạo phản hồi giả.

## Cấu hình

Đặt các biến trong `backend/.env`, rồi khởi động lại backend và worker:

```dotenv
GEMINI_API_KEY=
GEMINI_STYLIST_MODEL=gemini-3.5-flash-lite
AI_STYLIST_USER_DAILY_LIMIT=20
AI_STYLIST_GLOBAL_DAILY_LIMIT=200
AI_STYLIST_ESTIMATE_VND=500
GEMINI_TRYON_MODEL=gemini-nano-banana-2.1
AI_TRYON_USER_DAILY_LIMIT=3
AI_TRYON_GLOBAL_DAILY_LIMIT=20
AI_TRYON_ESTIMATE_VND=3000
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
Chỉ danh sách SKU hợp lệ được lấy từ phản hồi Gemini; lời mô tả hiển thị do
backend tạo từ kết quả đã xác thực. Lời tự do của model không được lưu/hiển thị.
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

Khi quay lại từ trang sản phẩm hoặc tải lại trang, Stylist tự đọc yêu cầu gần
nhất còn hạn của tài khoản bằng GET, kể cả khi phản hồi trước đó bị mất. Không
gọi Gemini thêm và không lưu nội dung nhập vào trình duyệt. Nếu chưa đọc được
yêu cầu cũ, cần bấm “Tải lại gợi ý gần nhất” trước khi tạo lượt mới. Phiên đăng
nhập được khôi phục theo hướng dẫn `BROWSER_SESSIONS_LOCAL.md`.

## Dữ liệu và kiểm chứng

### Thử đồ bằng ảnh riêng tư

Mở `/virtual-try-on` hoặc nút thử đồ trên sản phẩm có hỗ trợ. Chọn JPEG/PNG tĩnh,
tối đa8MB,16megapixel, mỗi chiều64–8192pixel. Đồng ý lưu ảnh tại cửa hàng rồi bấm
“Lưu ảnh riêng tư”. Chọn sản phẩm và đúng màu/size còn hàng; đồng ý gửi ảnh người
và ảnh trang phục tới Google Gemini, sau đó bấm “Thử trang phục”. Ảnh tạo ra chỉ
mô phỏng vẻ ngoài, không đo cơ thể và không đảm bảo sản phẩm vừa vặn.

Worker cần Redis và MinIO đang chạy. Hệ thống giữ một lượt trong hạn mức khi tiếp
nhận yêu cầu, đưa vào hàng đợi và chỉ cho phép một lần gọi Google. Yêu cầu chờ quá
5phút kết thúc; yêu cầu đang chạy quá hạn được đánh dấu không rõ kết quả. Cuộc gọi
ảnh tối đa90giây, toàn bước xử lý tối đa120giây. Lỗi không tự gọi Google lần nữa.
“Thử lượt mới” là một yêu cầu mới có tính hạn mức. Ngân sách ước tính và giới hạn
đồng thời được dùng chung với Stylist.

Mất phản hồi tải ảnh: bấm “Kiểm tra ảnh đã gửi”. Mất phản hồi tạo ảnh: bấm “Kiểm tra
yêu cầu đã gửi”. Máy chủ trả lại cùng ảnh/yêu cầu theo mã đã gửi. Trước khi gửi,
trình duyệt lưu mã thao tác theo tài khoản, cùng ID ảnh/SKU đối với lượt thử đồ;
không lưu ảnh, tên tệp, nội dung riêng tư, khóa đăng nhập hoặc URL ảnh. Mã chưa
rõ kết quả được giữ qua tải lại trang, kể cả trước khi máy chủ ghi nhận yêu cầu.
Nếu bộ nhớ trang web bị chặn, không bắt đầu lượt mới để tránh mất mã khôi phục.

Ảnh đang được lưu có trạng thái riêng để kiểm tra. Nếu lần tải ảnh chưa tới máy
chủ, chọn lại đúng ảnh, đồng ý lưu rồi tiếp tục bằng mã cũ; không tự tải ảnh từ
thiết bị. Không tự tạo lượt Gemini khi tải lại trang. Lịch sử `/account/try-ons` hiển thị
tối đa20 lượt gần nhất còn trong thời gian lưu, tải ảnh khi bạn bấm xem.
Đi từ trang chi tiết sản phẩm sẽ chọn sản phẩm đó cho lượt mới; đường dẫn tới
một yêu cầu cụ thể vẫn khôi phục đúng yêu cầu và trang phục cũ.

Ảnh đầu vào được chuẩn hóa, bỏ metadata và lưu riêng tư tối đa24giờ; kết quả hết
hạn cùng ảnh gốc. Trình duyệt lấy bytes qua API có xác thực, không nhận liên kết
ảnh có thể dùng như mật khẩu, không lưu ảnh vào localStorage. Khi rời trang, đổi
ảnh hoặc xóa, bản hiển thị được bỏ khỏi bộ nhớ đệm Flutter. Bytes đã tải xuống
thiết bị khác không thể thu hồi.

“Xóa ảnh và các kết quả” chặn đọc mới và chặn xuất bản kết quả đang xử lý ngay
khi máy chủ ghi nhận xóa. Dọn ảnh vật lý ở MinIO được thử lại khi lưu trữ lỗi,
kể cả đối tượng đến muộn. Việc xóa tại cửa hàng không thu hồi dữ liệu đã gửi tới
Google. `store:false` không thay thế chính sách xử lý dữ liệu của nhà cung cấp.

Ảnh trang phục chỉ lấy từ tài sản catalog đã xác minh thuộc sản phẩm hoặc ảnh
seed cục bộ hợp lệ. URL bên ngoài chưa nhập vào kho ảnh quản lý sẽ không chạy thử
đồ. Các job cũ chưa có bản ghi giữ hạn mức được kết thúc với mã
`AI_REQUEST_LEGACY`, tránh tự phát sinh lượt có phí sau nâng cấp.

### Stylist

Nội dung yêu cầu chỉ được lưu dưới dạng hash để kiểm tra gửi trùng. SKU đã chọn,
giá và điều kiện kiểm tra size/màu/ngân sách được lưu tối đa24giờ; sau đó bị xóa khi đọc hoặc trong đợt dọn dẹp
mỗi5phút. Nhật ký tối thiểu về model, trạng thái, token đã dùng, hash và ước tính
chi phí được giữ để tính hạn mức. API đọc kết quả chỉ cho chính chủ, không cache.

Kết nối dùng [Gemini Interactions v1](https://ai.google.dev/api/interactions-api-v1),
`store:false`, không history/tools/background. Khóa chỉ nằm trong header backend;
không ghi nội dung yêu cầu, ảnh, khóa hay phản hồi lỗi thô vào log. `store:false`
là cấu hình lưu tương tác của API; chính sách xử lý dữ liệu của Google vẫn áp dụng.

```powershell
powershell.exe -NoProfile -File tools/test-backend.ps1 -WithWorker -WithStorage
node tools/test-frontend-api.cjs --stylist
node tools/test-frontend-api.cjs --tryon
```

Kiểm thử chỉ dùng tài khoản/dữ liệu tạo riêng trong database `_test`. Gemini HTTP
trong kịch bản Chrome là phản hồi kiểm thử có kiểm soát để chứng minh consent,
giá/tồn kho, mất phản hồi, hạn mức và quyền đọc; không chứng minh tài khoản Google
đã kết nối thành công. Chỉ ghi nhận kiểm chứng Gemini thật sau khi có khóa và đã
quan sát một phản hồi từ dịch vụ. Không có khóa vẫn chạy được các kiểm thử local.
