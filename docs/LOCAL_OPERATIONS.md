# Vận hành trên máy local

Phạm vi: Windows, PostgreSQL/Redis (Memurai)/MinIO có sẵn, Gemini và VNPay
sandbox do chủ máy cấu hình. Vận chuyển dùng bộ mô phỏng local. Các lệnh dưới
chạy tại thư mục chứa phiên bản code muốn dùng; mỗi worktree có bộ tiến trình riêng.

## Khởi động và dừng

Node24, Flutter3.47.7 tại `.tools/flutter`, dependencies backend đã cài và schema
đã migrate là điều kiện trước khi chạy. Bản native hiện có27 migrations. Với bản
nâng cấp có migration mới, sao lưu trước, kiểm tra đúng database rồi chạy migration
theo hướng dẫn bản nâng cấp. Lệnh runtime không migrate, seed hoặc sửa `.env`.

```powershell
Get-Service postgresql-x64-17,Memurai
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\start-storage.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\local.ps1 build
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\local.ps1 start
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\local.ps1 status
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\local.ps1 stop
```

Nếu bật email local/khôi phục mật khẩu, khởi động Mailpit trước bằng helper được
mô tả trong [hướng dẫn email](MAIL_SUPPORT_LOCAL.md). Web mở tại
`http://localhost:8080`, API tại `http://localhost:3000/api/v1`. API và các
tiến trình chỉ nghe loopback. Khi đổi cổng, truyền cùng `-ApiPort` và `-WebPort`
cho `build` và `start`; trình chạy đặt CORS và URL trả về tương ứng trong tiến trình.
`-EnvFile` mặc định `backend/.env` và phải nằm trong workspace được phép.

`build` ghi dấu kiểm tra nội dung backend/web và URL API. Sau khi sửa code hoặc
chạy một browser fixture tạo bản web khác, chạy lại `build`. `start` từ chối bản
build không khớp, cổng đã có người dùng, dịch vụ thiếu hoặc worker khác còn sống
trong cùng namespace. Không chạy đồng thời worker dev và worker runtime.

Worker bắt đầu xử lý công việc đã được chấp nhận ngay khi khởi động, kể cả trước
khi lệnh `start` hoàn tất. Nếu Gemini đã cấu hình, công việc này có thể phát sinh
chi phí. Khi khởi động lỗi, rollback chỉ dừng các tiến trình vừa tạo, không hoàn
tác thư đã gửi hoặc yêu cầu provider đã thực hiện. Kiểm tra công việc đang chờ
trước khi bật lại worker; không đổi namespace để bỏ qua chúng.

`stop` chỉ gửi yêu cầu có xác thực đến API/worker/web do chính worktree đã tạo;
không dừng PostgreSQL, Redis, MinIO, Mailpit hay tiến trình chiếm cổng của người dùng.
Worker có thể cần khoảng150 giây để kết thúc công việc đang chạy. Đừng đóng cưỡng
bức terminal trong khi đang dừng. `status` chỉ đọc và không tạo file trạng thái.

Thông tin sở hữu nằm trong `.tools/runtime/<mã-workspace>/runtime.json`, chứa
secret điều khiển riêng: không chia sẻ hoặc đưa lên Git. Khi mất điện hay process
bị đóng bên ngoài, trạng thái có thể thành `unverified`. Kiểm tra process, command
line, cổng và nhật ký để xác định mọi child của lần chạy đó đã dừng; sau đó lưu
bản sao và gỡ đúng file trạng thái/lock cũ. Không dùng PID từ file cũ để kill vì
Windows có thể tái sử dụng PID. Nếu chưa xác minh được, giữ nguyên file.

Nhật ký từng vai trò chỉ chứa mã sự kiện đã cho phép, xoay vòng tối đa3 file
khoảng1MiB/file, không lưu request body, ảnh hay khóa provider. Dùng trạng thái
dịch vụ và báo cáo kiểm thử để chẩn đoán; không chia sẻ file cấu hình riêng.

## Màn hình Vận hành & AI

Đăng nhập ADMIN tại `/#/admin`, mở **Vận hành & AI**. API yêu cầu quyền
`staff.manage`; MANAGER và khách hàng không được xem. Nút tải lại do người dùng
chủ động bấm, không tự tạo lại tác vụ AI.

- Database: kết nối, tương thích schema, số migration.
- Redis: số việc chờ/đang chạy/trì hoãn/thất bại; không đọc payload. Tuổi việc
  chờ không có khi thứ tự ưu tiên không cho phép suy ra thời điểm cũ nhất.
- Worker: heartbeat mỗi10 giây, hết hạn30 giây. Có heartbeat chứng minh worker
  còn sống, chưa chứng minh công việc đang tiến triển; xem thêm queue và lỗi.
- AI: lượt dùng và chi phí **ước tính** từ đầu ngày UTC, reservation/processing
  quá hạn, nhóm mã lỗi. Đây không phải hóa đơn Gemini.
  Lỗi24 giờ tính theo thời điểm kết thúc; bản ghi cũ thiếu thời điểm này dùng
  thời điểm tạo làm mốc thay thế.
- Outbox, email, ảnh cần dọn: số lượng đang chờ hoặc lỗi để xử lý tiếp.
- Storage: truy cập bucket; SMTP: kết nối socket, chưa xác nhận thư đã được gửi.
- Gemini/VNPay: có cấu hình hay chưa; chưa chứng minh khóa hợp lệ hoặc đã giao dịch.

`Không xác định` khác với0. Khi Redis lỗi, phần database vẫn có thể hiển thị;
không suy ra queue rỗng. Không reset Redis hoặc đổi queue prefix để che lỗi.
Email đã có retry theo quy trình; giao dịch AI không rõ kết quả không tự gọi lại
provider trả phí. Xem [Gemini](GEMINI_LOCAL.md) và [tiến độ](LOCAL_COMPLETION_PROGRESS.md).

Phiên cửa hàng và quản trị độc lập, giữ qua tải lại trang bằng cookie HttpOnly.
JWT chỉ ở bộ nhớ; đăng xuất hoặc bị thu hồi phiên sẽ yêu cầu đăng nhập lại.
Không gửi Gemini API key, VNPay HashSecret hoặc file `.env` qua chat.

## Kiểm thử

Chạy tuần tự, không build/generate backend trong lúc E2E đang chạy và không chạy
nhiều lệnh Flutter đồng thời:

```powershell
.\tools\acceptance.ps1 quick
.\tools\acceptance.ps1 full
.\tools\acceptance.ps1 browser -Browser operations
.\tools\acceptance.ps1 runtime
```

`quick`: lint/build/unit backend, guards Node, Flutter analyze/test.
`full`: thêm E2E trên database riêng hậu tố `_test`, Redis namespace riêng và
bucket `-test`; cần các dịch vụ local sẵn sàng. Không gọi Gemini/VNPay thật.
`browser`: một luồng Chrome qua helper hiện có, mặc định operations; cần Chrome
và Playwright tại `.tools/browser`. Helper có thể build lại web.
`runtime`: build/start/status/stop trên test resources và cổng riêng; kiểm tra
dependency lỗi, API, web và heartbeat. `-ReuseBuild` chỉ dùng khi manifest còn khớp.

CI tại `.github/workflows/verify.yml` chuẩn bị checkout mới với dependencies đã
khóa, Flutter3.47.7, Node24, PostgreSQL17, Redis7 và MinIO phiên bản cố định.
`tools/ci-verify.cjs` chỉ dùng tài nguyên tổng hợp local có tên/credential CI cố
định; từ chối `.env` có sẵn và provider thật trước khi ghi hay kết nối. Không chạy
`prepare` trong thư mục làm việc có cấu hình của bạn. Workflow chỉ đọc repository,
không publish hay deploy. Cấu hình đã được chuẩn bị và các kiểm tra tương đương đã
chạy local; chưa có bằng chứng workflow chạy trên GitHub được lưu trong đợt này.
Tham khảo [GitHub service containers](https://docs.github.com/en/actions/tutorials/use-containerized-services/create-postgresql-service-containers)
và [Flutter3.47.7](https://github.com/flutter/flutter/releases/tag/3.47.7).

Giới hạn đã ghi nhận: Mailpit được cấu hình lưu dữ liệu nhưng bước xác minh giữ
thư qua stop/restart đã bị automatic approval review từ chối với lý do
`blocked by policy`; chưa được xác nhận và không được coi là kiểm thử đã đạt.
Backup/restore dữ liệu nghiệp vụ native đã có diễn tập riêng; xem
[hướng dẫn phục hồi](NATIVE_RECOVERY.md). Công cụ tạo đích mới và khóa phiên/tác vụ
cũ, không tự chuyển cửa hàng sang database phục hồi.
