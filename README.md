# WEARLY — Fashion AI Commerce

Ứng dụng Flutter hiện có và backend NestJS/PostgreSQL cho thương mại thời trang.

- [Cài đặt và chạy trên Windows](docs/setup.md)
- [Kiến trúc và quyết định thay đổi](docs/architecture.md)
- [Database, migrations và tồn kho](docs/database.md)
- [API thực tế và Swagger](docs/api.md)
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

Bắt đầu sau khi Docker Engine hoạt động:

```powershell
node tools/init-env.cjs   # chỉ lần đầu; không ghi đè .env đã có
docker compose up -d --wait postgres redis
cd backend
npm ci
npm run prisma:generate
npm run prisma:deploy
npm run prisma:seed
npm run start:dev
```

Swagger: http://localhost:3000/api/docs. Catalog API: http://localhost:3000/api/v1/products.

Frontend mặc định vẫn là demo. Chỉ bật catalog từ API bằng `USE_REMOTE_CATALOG=true` và `API_BASE_URL`; đăng nhập/checkout/admin Flutter chưa chuyển sang API. Không có thanh toán online hoặc ảnh AI giả được trình bày như kết quả thật.
