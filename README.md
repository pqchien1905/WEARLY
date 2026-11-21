# WEARLY — Fashion AI Commerce

Website thời trang tiếng Việt: Flutter Web cho cửa hàng và quản trị; NestJS, Prisma và PostgreSQL cho API; Redis, MinIO và worker cho tác vụ nền. Bản hiện tại dùng localhost, thanh toán sandbox và vận chuyển mô phỏng.

## Chạy trên máy hiện tại

Tại thư mục dự án, với PostgreSQL và Memurai đã chạy:

```powershell
.\tools\start-storage.ps1
node tools/mailpit-runtime.cjs start
.\tools\local.ps1 start
.\tools\local.ps1 status
```

- Cửa hàng: <http://localhost:8080>
- Quản trị: <http://localhost:8080/#/admin>
- Hộp thư thử Mailpit: <http://127.0.0.1:8025>
- API: <http://localhost:3000/api/v1>
- Swagger: <http://localhost:3000/api/docs>

Khi cập nhật mã nguồn:

```powershell
.\tools\local.ps1 stop
# Nếu có migration mới: sao lưu rồi chạy npm run prisma:deploy từ backend.
.\tools\local.ps1 build
.\tools\local.ps1 start
```

Runtime dùng cấu hình `backend/.env`, không tự migrate hoặc seed dữ liệu. Cần Node 24, Flutter, PostgreSQL, Redis/Memurai và MinIO. Hot reload giao diện dùng `.\tools\frontend.ps1 api` sau khi dừng web runtime đang chiếm cổng.

## Cấu trúc

```text
frontend/       Giao diện, tài sản và kiểm thử Flutter
backend/        API, worker, schema và migrations
tools/          Script phát triển, vận hành và kiểm thử
.tools/         SDK, dịch vụ local, bản sao lưu và file sinh tự động; không commit
```

## Kiểm tra

Backend: `npm run lint`, `npm test`, `npm run build` trong `backend`.

E2E: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-backend.ps1 -WithWorker -WithStorage`; cần database kiểm thử riêng có hậu tố `_test`.

Frontend: `flutter analyze`, `flutter test` trong `frontend` (hoặc SDK tại `.tools/flutter/bin`).

Ảnh chụp, log và kết quả kiểm thử là file sinh tự động, không đưa vào Git. Công cụ browser tự tạo lại thư mục đầu ra khi cần. Giữ nguyên file môi trường, dữ liệu dịch vụ và bản sao lưu khi dọn workspace.

Ghi nguồn ảnh và phông chữ: [ATTRIBUTION](frontend/assets/ATTRIBUTION.md).
