# Wearly backend

NestJS modular monolith. Node 24 LTS, TypeScript 5.9, Prisma **7.10.1** cho CLI/client/adapter-pg.

Từ thư mục này: `npm ci`, `npm run prisma:generate`, `npm run prisma:deploy`, `npm run prisma:seed`, `npm run start:dev`.

`prisma.config.ts` tải .env rõ ràng; schema không chứa connection URL. Generated client nằm ở `src/generated/prisma`, không đưa vào Git. Migration khởi tạo và migration CHECK constraints phải được giữ cùng nhau. Không dùng db push để triển khai.

`npm run build`, `npm run lint`, `npm test`. E2E cần TEST_DATABASE_URL trỏ database riêng có hậu tố _test; chạy `powershell -NoProfile -ExecutionPolicy Bypass -File ../tools/test-backend.ps1 -WithWorker` để kiểm tra commerce và worker trên PostgreSQL cùng Redis/Memurai. Mỗi lượt kiểm thử worker dùng queue namespace riêng; paid AI và object storage được thay bằng test doubles.

Worker: `npm run build` rồi `npm run worker` trong terminal riêng. Redis bắt buộc cho worker; AI provider mặc định Disabled. API ghi AIJob + OutboxEvent trong một transaction khi provider được triển khai và bật qua DI. Chỉ đặt AI_PROVIDER_URL/API_KEY chưa tự bật gọi AI.

`AI_QUEUE_PREFIX` mặc định `wearly`; giữ nguyên prefix giữa các lần khởi động để xử lý cùng hàng đợi. Lỗi provider được chuyển thành mã an toàn trước khi BullMQ lưu vào Redis.

Private upload JPEG/PNG, ownership, consent, quota và cleanup đã có. Chạy helper `tools/start-storage.ps1` từ root; thêm `-WithStorage` vào test helper để kiểm thử MinIO thật. Worker xử lý retention mỗi60s cả khi AI provider Disabled. Giữ đủ4 migrations, bucket private/unversioned; xem [private-images.md](../docs/private-images.md).

[Xem hướng dẫn đầy đủ](../docs/setup.md), [API](../docs/api.md), [giới hạn nghiệm thu](../docs/backend-report.md).
