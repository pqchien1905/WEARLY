# WEARLY — Fashion AI Commerce

Ứng dụng Flutter hiện có và backend NestJS/PostgreSQL cho thương mại thời trang.

- [Cài đặt và chạy trên Windows](docs/setup.md)
- [Kiến trúc và quyết định thay đổi](docs/architecture.md)
- [Database, migrations và tồn kho](docs/database.md)
- [API thực tế và Swagger](docs/api.md)
- [Upload ảnh riêng tư, quyền truy cập và cleanup](docs/private-images.md)
- [Ánh xạ mock → API](docs/migration-plan.md)
- [Báo cáo triển khai, kiểm thử và phần còn thiếu](docs/backend-report.md)
- [Lịch sử frontend](README_FRONTEND.md)

```text
frontend/       Flutter, Riverpod, go_router; giữ UI và mock demo
backend/        NestJS 11, Prisma 7, REST API và AI worker riêng
docs/           Tài liệu, sơ đồ Mermaid, kiểm thử
design-system/  Thiết kế và tài sản tham chiếu hiện có
tools/          Script phát triển PowerShell/Node
docker-compose.yml  PostgreSQL, Redis; profile storage và app
```

Bắt đầu trên máy Windows đã cấu hình PostgreSQL và Memurai:

```powershell
Get-Service postgresql-x64-17,Memurai
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\start-storage.ps1
cd backend
npm ci
npm run prisma:generate
npm run prisma:deploy
npm run prisma:seed
npm run start:dev
```

Mở terminal riêng trong `backend` và chạy `npm run build` rồi `npm run worker`. pgAdmin nằm trong Start Menu → PostgreSQL 17, với kết nối **WEARLY - PostgreSQL 17 (Windows)** đã đăng ký trên máy này. Máy mới hoặc chạy bằng Docker: làm theo [setup.md](docs/setup.md); không ghi đè các file `.env` đang có.

Swagger: http://localhost:3000/api/docs. Catalog API: http://localhost:3000/api/v1/products.

Mở terminal thứ hai tại `D:\Fashion Shop`, chạy giao diện Flutter kết nối API:

```powershell
.\tools\frontend.ps1 api
```

Mở Chrome tại `http://localhost:8080`: đăng ký/đăng nhập, hồ sơ, địa chỉ, giỏ hàng, đặt COD, lịch sử và hủy đơn dùng dữ liệu PostgreSQL. Sau khi tải lại trang cần đăng nhập lại; dữ liệu vẫn được lưu trên máy chủ. Chạy `.\tools\frontend.ps1 run` để xem demo độc lập. Admin, yêu thích, AI và khôi phục mật khẩu chưa nối vào chế độ API; chưa có thanh toán online.
