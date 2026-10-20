# Khôi phục mật khẩu

Chức năng dùng SMTP cấu hình được, PostgreSQL và worker BullMQ hiện có. Mặc
định tắt. Kiểm thử local dùng máy chủ SMTP nhận thư thật trên loopback; chưa
xác minh gửi tới hộp thư ngoài Internet.

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
PASSWORD_RESET_WEB_URL=https://store.example.com/#/reset-password
```

Thay bằng thông số của dịch vụ thực tế qua môi trường/secret store, không
commit credentials. `SMTP_USER` và `SMTP_PASSWORD` phải cùng có hoặc cùng
trống. Cổng587 dùng STARTTLS bắt buộc; cổng465 đặt `SMTP_SECURE=true` cho
TLS ngay từ đầu. Luôn xác minh chứng chỉ. Ngoại lệ plaintext chỉ dành cho
host loopback ở development/test; production từ chối.

URL phải thuộc một origin trong `CORS_ORIGINS`, không userinfo/query và có
fragment `#/reset-password`. Production bắt buộc HTTPS. Không xây URL từ
Host header của request. Website cần phục vụ đúng Flutter release tương ứng.

Chạy migration trước, sau đó khởi động cả API và worker. Chỉ bật gửi ngoài
Internet khi đã xác minh SMTP authentication, sender/domain, SPF/DKIM/DMARC,
hộp thư nhận và chính sách vận hành của nhà cung cấp. Những kiểm chứng này
hiện **BLOCKED** vì chưa có cấu hình dịch vụ được cung cấp.

## Contract và trạng thái

- `POST /api/v1/auth/forgot-password`, body `{email}`: email chuẩn hóa,
  tối đa254 ký tự. Trả202 `{accepted:true}` giống nhau cho tài khoản có,
  không có, inactive hoặc đang được deduplicate; không trả token. Tài khoản
  được tra ở worker. Tắt dịch vụ/hàng đợi lỗi trả503 `RECOVERY_UNAVAILABLE`.
- `POST /api/v1/auth/reset-password`, body `{token,password}`: token
  base64url43 ký tự, password12–128 ký tự. Thành công200 `{changed:true}`;
  token sai/hết hạn/đã dùng/inactive trả400 `RESET_LINK_INVALID`.
- Request giới hạn10/phút/IP, reset20/phút/IP theo throttler hiện có.
  Dedupe email bằng HMAC và Redis TTL60s; đa API replica vẫn cần shared
  IP throttling trước khi production.
- Queue producer có command timeout2s và deadline3s. Mất phản hồi có thể
  xảy ra sau enqueue; không coi503/timeout là bằng chứng chưa gửi thư.
  Worker thử tối đa3 lần với backoff. SMTP timeout hữu hạn; không ghi raw
  SMTP errors, địa chỉ, mật khẩu hoặc token vào log/failedReason.

## Token, giao dịch và phiên

Token ngẫu nhiên256bit, DB chỉ lưu SHA256, hết hạn15 phút. Worker gửi link
chứa token trong fragment, API nhận token ở POST body. Token không được lưu
ở Redis; job chứa email và thời điểm yêu cầu lấy từ PostgreSQL. Job hoàn
thành được xóa, failed jobs giới hạn100 bản/1 giờ (BullMQ dọn khi job kết
thúc). Redis vẫn chứa email, cần quyền truy cập và chính sách backup phù hợp.

Worker khóa theo user trước khi tạo token; SMTP nằm ngoài transaction.
Thất bại gửi thu hồi token của lần thử đó. Một request không thay mật khẩu
hoặc thu hồi phiên. Reset xác minh trước khi hash, rồi xác minh lại dưới
cùng khóa user; đổi Argon2id hash, ghi cutoff, tiêu thụ mọi reset token và
thu hồi mọi refresh/access session trong cùng transaction. Login kiểm tra
lại hash/active/role dưới khóa sau khi verify; refresh dùng cùng khóa.
Request/retry cũ ở hoặc trước cutoff bị bỏ qua. Mốc thời gian lấy dạng
timestamptz từ DB để tránh lệch timezone. Worker dọn token hết hạn mỗi phút.

Thư thông báo đổi mật khẩu không chứa token/password. Enqueue notification
là best effort sau commit: lỗi không đảo ngược mật khẩu; có warning cố định
để vận hành theo dõi. SMTP accepted không chứng minh thư tới inbox.

Frontend xóa query token khỏi route trước khi tạo page/widget keys, giữ
token trong bộ nhớ biểu mẫu, không browser storage. Reload cần mở lại link.
Sau thành công thu hồi trạng thái phiên local và yêu cầu đăng nhập lại.
Timeout, mất kết nối hoặc JSON không hợp lệ chuyển sang trạng thái chưa xác
nhận, bỏ token và không tự gửi lại. Phản hồi muộn không xóa phiên đăng nhập
mới nhờ kiểm tra generation. Trang đặt `no-referrer`.

## Kiểm tra

```powershell
powershell -File tools/test-backend.ps1 -WithWorker -WithStorage
node tools/test-frontend-api.cjs --recovery
```

Backend dùng DB riêng kết thúc `_test`, Redis namespace riêng và SMTP TCP
local. Kiểm tra email/unknown/inactive, dedupe/throttle, hash/expiry, hai reset
đồng thời, phiên khách/quản trị, login/refresh race, retry job trước cutoff,
SMTP failure, Redis đã kết nối nhưng ngừng trả lời, disabled và retention.
Chrome kiểm tra request→SMTP link→mobile reset→login→link reuse/reload.
Không gửi email ngoài local trong các lệnh này.
