# Tiến độ bàn giao WEARLY

Cập nhật 19/10/2026. Mục tiêu đang hoạt động: hoàn thiện dự án để bàn giao và kiểm thử, chủ động sửa lỗi có bằng chứng; không xóa dữ liệu người dùng, không triển khai production.

Lượt trước **có tiến triển**: hồ sơ phong cách đã nối PostgreSQL, kiểm thử Chrome và sửa lỗi phong cách ảnh hưởng checkout; `main` tại `fcd3bc5`. Bằng chứng: 292 Flutter tests, 33 PostgreSQL E2E, 11 backend unit; chi tiết trong [docs/progress.md](docs/progress.md).

## Đang xử lý

- Đã triển khai chống trùng khi POST mất phản hồi hoặc đọc lại thất bại: receipt ở PostgreSQL và giữ nguyên mã/nội dung khi thử lại trong Flutter. Rà soát cuối tìm và sửa đua giữa phản hồi muộn, tải lại hồ sơ và retry. 299 Flutter tests đạt, analyzer sạch. Luồng API thật đã cố ý làm mất phản hồi sau commit rồi thử lại, chỉ còn một địa chỉ và đặt COD thành công.
- Đối chiếu các tiêu chí bàn giao trong Master Prompt với code, runtime, migration, tài liệu và kiểm thử thực tế. Chưa tuyên bố toàn bộ dự án hoàn thành.

## Kiểm chứng bàn giao còn phải tổng hợp

| Nhóm yêu cầu | Nguồn chứng minh cần kiểm tra |
|---|---|
| Flutter được giữ nguyên, API/client/session/loading/errors | frontend/lib, widget tests, release build, luồng Chrome |
| Auth, catalog/SKU/kho, giỏ/đơn, phân quyền | controller/service + E2E PostgreSQL, cạnh tranh tồn kho/idempotency |
| PostgreSQL/Prisma/migrations/seed | schema/migration status, generate, DB mới biệt lập và seed lặp an toàn |
| Worker riêng, Redis, uploads/S3, không giả AI thật | worker/storage opt-in tests, cấu hình và trạng thái provider |
| Docker/local Windows, phần mềm và hướng dẫn chạy | compose config/runtime, tools, README/setup |
| Bảo mật và không lộ secrets | guards/validation/logging/filter, tracked files và kiểm thử quyền |
| Tài liệu A–H, sơ đồ, endpoint và tồn đọng | docs/architecture.md, database.md, api.md, setup.md, migration-plan.md, báo cáo bàn giao |

Master Prompt cho phép AI/payment provider thật là giai đoạn sau; không giả kết quả hoặc giao dịch thành công. Các tính năng chưa nối API (promotions, khôi phục mật khẩu/email, uploads catalog, audit/đối soát COD và AI UI) vẫn cần ghi rõ, không dùng kiểm thử demo làm bằng chứng API thật.

Đã kiểm tra cấu hình Compose hợp lệ; Docker engine hiện chưa chạy. Luồng native PostgreSQL/Memurai/API/MinIO hoạt động. Khi bật worker/storage tests, phát hiện helper kiểm thử đọc snapshot BullMQ trước khi job chuyển trạng thái; đã sửa để lấy lại snapshot sau terminal state. Kết quả cuối: **53/53 backend E2E** (gồm worker Redis và private uploads MinIO), **11/11 unit**, backend lint/build đạt; **299 Flutter tests** đạt +2live opt-in bỏ qua trong suite thường, analyzer/release build đạt. Live shopping được chạy riêng và đạt, gồm mất phản hồi sau commit + retry + COD.

Đánh giá lượt này: có thay đổi code, migration cộng thêm, tái hiện lỗi trước sửa và kiểm chứng sau sửa. Không tuyên bố hoàn tất mục tiêu; bước tiếp theo là kiểm tra tính tái lập trên DB/schema mới biệt lập, seed lặp an toàn, thống nhất tài liệu bàn giao A–H và rà lại hạ tầng/điểm thiếu còn mở.

Quyết định: giữ payload theo mã trong RAM suốt phiên để lần thử lại vẫn chính xác sau refresh. Đổi lại RAM tăng theo số form đã tạo trong phiên; không lưu ra localStorage và cache được bỏ khi đổi danh tính. Không có Minor chưa xử lý được nêu trong rà soát.

Không có blocker cần người dùng quyết định ở thời điểm cập nhật này. Nhật ký chi tiết trước đây vẫn giữ tại [docs/progress.md](docs/progress.md).
