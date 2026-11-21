# Khôi phục mật khẩu

Chức năng dùng SMTP cấu hình được, PostgreSQL và worker BullMQ hiện có. Mặc
định tắt. Ngày 22/10/2026 đã xác minh Gmail SMTP thực tế: gửi yêu cầu từ giao
diện, worker xử lý thành công và người dùng xác nhận nhận được email trong
hộp thư. Kiểm thử tự động tiếp tục dùng SMTP loopback và database riêng.
Luồng mã 6 số đã được kiểm tra lại qua giao diện local trên cùng ngày: API202,
worker ghi nhận SMTP chấp nhận email mới và mật khẩu tài khoản thử giữ nguyên.
Toàn bộ thao tác xác nhận mã/đổi mật khẩu được kiểm tra trên tài khoản fixture riêng.

## Cấu hình

Đặt cùng cấu hình ở API và worker, theo `backend/.env.example` (Compose dùng
`.env` ở root):

```dotenv
PASSWORD_RECOVERY_ENABLED=true
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_SECURE=false
SMTP_USER=
SMTP_PASSWORD=
SMTP_FROM=store@example.com
SMTP_ALLOW_INSECURE_LOCAL=false
PASSWORD_RESET_WEB_URL="https://store.example.com/#/reset-password"
```

Thay bằng thông số của dịch vụ thực tế qua môi trường/secret store, không
commit credentials. `SMTP_USER` và `SMTP_PASSWORD` phải cùng có hoặc cùng
trống. Cổng587 dùng STARTTLS bắt buộc; cổng465 đặt `SMTP_SECURE=true` cho
TLS ngay từ đầu. Luôn xác minh chứng chỉ. Ngoại lệ plaintext chỉ dành cho
host loopback ở development/test; production từ chối.

URL phải thuộc một origin trong `CORS_ORIGINS`, không userinfo/query và có
fragment `#/reset-password`. Production bắt buộc HTTPS. Không xây URL từ
Host header của request. Website cần phục vụ đúng Flutter release tương ứng.
Giữ cấu hình URL này để tương thích; email mới tự trỏ về `#/forgot-password`,
không chứa email, mã xác nhận hoặc token trong URL.

Chạy migration trước, sau đó khởi động cả API và worker. Khi thay cấu hình
SMTP, khởi động lại cả hai tiến trình; chỉ tải lại trình duyệt không cập nhật
cấu hình gửi thư.

### Gmail cho môi trường local

Tạo App Password ở https://myaccount.google.com/apppasswords sau khi bật xác
minh hai bước. Cập nhật các biến hiện có trong `backend/.env`:

```dotenv
PASSWORD_RECOVERY_ENABLED=true
LOCAL_MAIL_ENABLED=false
SMTP_HOST=smtp.gmail.com
SMTP_PORT=465
SMTP_SECURE=true
SMTP_USER=your-sender@gmail.com
SMTP_PASSWORD=your-app-password-without-spaces
SMTP_FROM=your-sender@gmail.com
SMTP_ALLOW_INSECURE_LOCAL=false
PASSWORD_RESET_WEB_URL="http://localhost:8080/#/reset-password"
```

`SMTP_FROM` dùng cùng địa chỉ với `SMTP_USER`. `LOCAL_MAIL_ENABLED` dành cho
outbox thử nghiệm qua SMTP loopback, cần tắt khi dùng Gmail. Giữ
`http://localhost:8080` trong `CORS_ORIGINS`. Mật khẩu ứng dụng chỉ lưu trong
cấu hình cục bộ bị Git bỏ qua; không đưa vào frontend, tài liệu hay log.

Mở chức năng Quên mật khẩu bằng email tài khoản đang hoạt động để kiểm tra.
Liên kết `localhost` phải mở trên máy đang chạy website. Khi triển khai cho
khách hàng, đổi sang URL HTTPS công khai và cập nhật `CORS_ORIGINS` tương ứng;
đợt xác minh Gmail này chưa bao gồm triển khai website công khai.

## Contract và trạng thái

- `POST /api/v1/auth/forgot-password`, body `{email}`: email chuẩn hóa,
  tối đa254 ký tự. Trả202 `{accepted:true}` giống nhau cho tài khoản có,
  không có, inactive hoặc đang được deduplicate; không trả token. Tài khoản
  được tra ở worker. Tắt dịch vụ/hàng đợi lỗi trả503 `RECOVERY_UNAVAILABLE`.
  Chỉ tài khoản CUSTOMER được nhận mã. Email của nhân sự/quản trị vẫn nhận
  phản hồi202 giống nhau nhưng không gửi thư; mã/token cũ không thể đặt lại
  mật khẩu sau khi tài khoản chuyển sang vai trò nhân sự.
- `POST /api/v1/auth/reset-password`, body `{token,password}`: token
  base64url43 ký tự, password12–128 ký tự. Thành công200 `{changed:true}`;
  token sai/hết hạn/đã dùng/inactive trả400 `RESET_LINK_INVALID`.
- `POST /api/v1/auth/verify-reset-code`, body `{email,code}`: mã là chuỗi đúng
  6 chữ số (giữ số 0 đầu). Thành công200 `{resetToken,expiresIn:600}`. Mã sai,
  hết hạn, đã dùng hoặc tài khoản không hoạt động trả400 `RESET_CODE_INVALID`.
  Tối đa 5 lần nhập sai cho mỗi mã; lần thứ 5 vô hiệu mã nhưng không khóa đăng nhập.
- Request giới hạn10/phút/IP, xác nhận/reset20/phút/IP theo throttler hiện có.
  Dedupe email bằng HMAC và Redis TTL60s; đa API replica vẫn cần shared
  IP throttling trước khi production.
- Queue producer có command timeout2s và deadline3s. Mất phản hồi có thể
  xảy ra sau enqueue; không coi503/timeout là bằng chứng chưa gửi thư.
  Worker thử tối đa3 lần với backoff. SMTP timeout hữu hạn; không ghi raw
  SMTP errors, địa chỉ, mật khẩu, mã xác nhận hoặc token vào log/failedReason.

## Mã xác nhận, giao dịch và phiên

Worker sinh mã ngẫu nhiên bằng CSPRNG, đủ 6 chữ số, có hiệu lực 10 phút. Bảng
`PasswordResetCode` chỉ lưu HMAC SHA256 có khóa, gắn với user và ID yêu cầu,
số lần sai, thời hạn và trạng thái gửi/sử dụng; mỗi user có một mã hiện hành.
Gửi lại thay mã cũ và đặt lại số lần thử. Mã chỉ dùng được sau khi SMTP chấp nhận.
Email có HTML theo giao diện Wearly và bản plain text; mã là văn bản có thể sao chép.

Xác nhận mã thành công tiêu thụ mã và cấp token ngẫu nhiên256bit dành riêng cho
bước đặt mật khẩu, hết hạn10 phút. DB chỉ lưu SHA256 của token. API nhận mã và
token trong POST body. Cả hai không được lưu ở Redis; job chứa email và thời
điểm yêu cầu lấy từ PostgreSQL. Job hoàn
thành được xóa, failed jobs giới hạn100 bản/1 giờ (BullMQ dọn khi job kết
thúc). Redis vẫn chứa email, cần quyền truy cập và chính sách backup phù hợp.

Worker khóa theo user trước khi tạo mã; SMTP nằm ngoài transaction.
Thất bại gửi thu hồi mã của lần thử đó; retry tạo mã mới. Job cũ không thay thế
yêu cầu mới hơn hoặc mã đã gửi của cùng yêu cầu. Worker có thể tiếp tục yêu cầu
chưa được gửi nếu bị dừng đột ngột. Một request không thay mật khẩu
hoặc thu hồi phiên. Reset xác minh trước khi hash, rồi xác minh lại dưới
cùng khóa user; đổi Argon2id hash, ghi cutoff, tiêu thụ mọi mã/reset token và
thu hồi mọi refresh/access session trong cùng transaction. Login kiểm tra
lại hash/active/role dưới khóa sau khi verify; refresh dùng cùng khóa.
Request/retry cũ ở hoặc trước cutoff bị bỏ qua. Mốc thời gian lấy dạng
timestamptz từ DB để tránh lệch timezone. Worker dọn mã/token hết hạn mỗi phút.

Thư thông báo đổi mật khẩu không chứa token/password. Enqueue notification
là best effort sau commit: lỗi không đảo ngược mật khẩu; có warning cố định
để vận hành theo dõi. SMTP accepted không chứng minh thư tới inbox.

Trang `#/forgot-password` gồm ba bước ngay trong cùng form: email → mã 6 số →
mật khẩu mới. Ô mã hỗ trợ dán và autofill, nút gửi lại đếm ngược 60 giây, có
thao tác đổi email. Form dùng được trên desktop và màn hình 375px. Token chỉ
giữ trong bộ nhớ biểu mẫu, không URL/browser storage. Sau reload, có thể nhập
email và chọn “Tôi đã có mã xác nhận” nếu mã chưa được dùng; nếu đã xác nhận
mã rồi thì cần yêu cầu mã mới. Mật khẩu mới phải có 12–128 ký tự và nhập lại khớp.

Liên kết cũ `#/reset-password?token=...` còn hạn vẫn được hỗ trợ. Frontend xóa
query token trước khi tạo page/widget keys. Email mới không gửi loại liên kết này.
Sau thành công thu hồi trạng thái phiên khách hàng local và yêu cầu đăng nhập
lại. Mật khẩu và phiên của tài khoản quản trị độc lập được giữ nguyên.
Timeout, mất kết nối hoặc JSON không hợp lệ chuyển sang trạng thái chưa xác
nhận, bỏ token và không tự gửi lại. Phản hồi muộn không xóa phiên đăng nhập
mới nhờ kiểm tra generation. Trang đặt `no-referrer`.

## Kiểm tra

```powershell
powershell -File tools/test-backend.ps1 -WithWorker -WithStorage
node tools/test-frontend-api.cjs --recovery
```

Backend dùng DB riêng kết thúc `_test`, Redis namespace riêng và SMTP TCP
local. Kiểm tra email/unknown/inactive, dedupe/throttle, HMAC/expiry, mã có số 0 đầu,
5 lần sai đồng thời, gửi lại, retry sau gián đoạn, một lần xác nhận, hai reset
đồng thời, phiên khách/quản trị, login/refresh race, retry job trước cutoff,
SMTP failure, Redis đã kết nối nhưng ngừng trả lời, disabled và retention.
Chrome kiểm tra request→SMTP code→xác nhận→mobile reset→login→code reuse/reload.
Không gửi email ngoài local trong các lệnh này.
