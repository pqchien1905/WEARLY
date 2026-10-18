# Wearly backend

NestJS modular monolith. Node 24 LTS, TypeScript 5.9, Prisma **7.10.1** cho CLI/client/adapter-pg.

Từ thư mục này: `npm ci`, `npm run prisma:generate`, `npm run prisma:deploy`, `npm run prisma:seed`, `npm run start:dev`.

`prisma.config.ts` tải .env rõ ràng; schema không chứa connection URL. Generated client nằm ở `src/generated/prisma`, không đưa vào Git. Migration khởi tạo và migration CHECK constraints phải được giữ cùng nhau. Không dùng db push để triển khai.

`npm run build`, `npm run lint`, `npm test`. E2E cần TEST_DATABASE_URL trỏ database riêng có hậu tố _test; chạy `../tools/test-backend.ps1` từ PowerShell sau khi PostgreSQL chạy.

Worker: `npm run build` rồi `npm run worker` trong terminal riêng. Redis bắt buộc cho worker; AI provider mặc định Disabled. API ghi AIJob + OutboxEvent trong một transaction khi provider được triển khai và bật qua DI. Chỉ đặt AI_PROVIDER_URL/API_KEY chưa tự bật gọi AI.

[Xem hướng dẫn đầy đủ](../docs/setup.md), [API](../docs/api.md), [giới hạn nghiệm thu](../docs/backend-report.md).
