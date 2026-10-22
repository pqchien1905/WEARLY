# Tích hợp bản hoàn thiện local —22/10/2026

Mã từ nhánh `codex/completion-2026-10-21` đã được fast-forward vào thư mục chính
`D:\Fashion Shop`, nhánh `codex/system-completion-2026-10-20`, tại 26bd174.
Không push, không đổi nhánh của người dùng và không ghi đè thay đổi chưa commit;
thư mục chính sạch trước khi tích hợp, là ancestor của nhánh đã kiểm chứng.

Ruling: yêu cầu hoàn thiện A-Z bao gồm đưa kết quả chạy được về thư mục dự án
chính; fast-forward local là bước có thể hoàn tác, không yêu cầu xác nhận lặp lại.
Giữ worktree cũ vì có cấu hình/artifact riêng và đường dẫn phục hồi đã ghi nhận;
không force-delete dữ liệu riêng hay các bản sao.

Root `.env` được bổ sung **chỉ những mục còn thiếu** để dùng SMTP/Mailpit local
và khôi phục mật khẩu. Mọi khóa/giá trị đã có giữ nguyên. Link đặt lại mật khẩu
mặc định trỏ cửa hàng local 8080. Bản trước thay đổi và kết quả đối chiếu nằm riêng
tư dưới `.tools/final-integration-20261022`, ACL chỉ chủ máy/SYSTEM; không commit.
Không cấu hình gửi email ra bên ngoài.
Lần khởi động đầu phát hiện giá trị SMTP_FROM mới thêm dùng dạng tên kèm địa chỉ,
trong khi bộ kiểm tra yêu cầu địa chỉ email thuần. Đã sửa riêng mục vừa thêm thành
`wearly@local.test`, kiểm tra cấu hình và đối chiếu lại mọi giá trị gốc trước khi
khởi động thành công.

Kiểm tra trước tích hợp:204E2E,86unit,53tool,428Flutter+2skip có chủ đích,
lint/build/analyze; Chrome375/1440 quản trị/khách hàng; native runtime start/status/
stop và business smoke. Sau review còn có kiểm thử HTTP URL viết hoa và smoke
compiled mới, đều đạt. Các lượt trên không gọi Gemini/VNPay thật.

Kiểm tra lại tại thư mục chính đã hoàn tất:

- `tools/acceptance.ps1 -Profile full`: 204 E2E, 86 unit, 53 tool,
  428 Flutter đạt, 2 kiểm thử opt-in bỏ qua có chủ đích; lint/build/analyze đạt.
- `tools/local.ps1 build` đạt; `start` và `status` báo API, worker, web đều ready.
  Cửa hàng: `http://localhost:8080`; API: `http://localhost:3000/api/v1`;
  hộp thư local: `http://localhost:8025`. Giữ các tiến trình này chạy để sử dụng.
- Chrome chỉ đọc ở 1440×900 và 375×812: trang điều khoản, tên WEARLY,
  thông báo demo local đúng; không có lỗi JavaScript. Health, Mailpit và sitemap
  viết hoa trả 200; web/HTML preview giữ noindex. Đã xem hai ảnh chụp giao diện.
- Bản sao business mới có 27 migrations, 42 bảng; phục hồi vào DB/bucket mới,
  đối chiếu assets/schema/API đạt, dữ liệu nguồn và môi trường giữ nguyên.
  Archive `1792635431858-e4bcb00d-771b-48fb-812b-25a8415fec17`, DB đích
  `wearly_recovery_1792635432515_b3940a8f`, dưới `.tools/recovery/2d9cabf5b2b3ff250b16`.
  Lượt business không có fixture ảnh managed/session cũ nên ghi rõ hai bước bỏ
  qua; các fixture này đã được kiểm chứng riêng trong milestone phục hồi.

Log `full.log`, `build.log`, `start.log`, kết quả `browser-result.json`,
`recovery-result.json` và ảnh giao diện nằm trong thư mục riêng tư nêu trên.
Không chạy acceptance test ghi dữ liệu trên DB business. Dịch vụ gốc và tiến trình
do người dùng mở tại cổng 5173 được giữ nguyên. Người dùng xác nhận giữ WEARLY,
ghi rõ demo local; thông tin liên hệ chưa cung cấp được để trống.

Chưa chứng nhận provider: ba mục GEMINI_API_KEY,VNPAY_TMN_CODE,VNPAY_HASH_SECRET
còn trống ở lần kiểm tra gần nhất; chủ máy đã nói sẽ cấu hình trong backend/.env.
VNPay cần thêm VNPAY_ENABLED=true và các URL local theo hướng dẫn sandbox khi đã
có cặp khóa thử nghiệm. Không tự tạo khóa, dùng khóa giả hay báo kết nối thành công.

Hosted CI được chuẩn bị nhưng chưa push/chạy. Kiểm tra khởi động lại Mailpit để
chứng minh lưu thư qua restart từng bị automatic approval review từ chối với lý
do “blocked by policy”; không thử lại hoặc đi vòng. Lưu trữ đã cấu hình, nhưng
bằng chứng restart vẫn chưa có. Các luồng gửi/đọc thư local đã được kiểm thử.
