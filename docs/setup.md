# Thiết lập trên Windows

## Công cụ và trạng thái máy ngày 18/10/2026

Node24.22.0 LTS, Flutter/Dart portable đã có trong .tools; đã thêm vào user PATH. Git for Windows2.55.0.5, WSL3.0.3 và Docker Desktop4.95.0 đã cài. Docker CLI29.8.2, Compose5.6.0 kiểm tra được.

**Cần khởi động lại Windows:** Virtual Machine Platform và các Windows features báo RestartNeeded=true. Docker Engine hiện báo Virtual Machine Platform not enabled. Không tự khởi động lại để tránh mất công việc đang mở. Sau reboot mở Docker Desktop và chờ Engine running.

Nếu còn báo virtualization sau reboot, kiểm tra `wsl --status`, `docker info` và virtualization trong BIOS/UEFI. HypervisorPresent hiện true; không kết luận BIOS bị tắt chỉ từ WMI khi Windows hypervisor đang hoạt động.

Trên máy mới cài [Node LTS](https://nodejs.org/en/download), [Git](https://git-scm.com/download/win), [Flutter](https://docs.flutter.dev/install) và [Docker Desktop](https://docs.docker.com/desktop/setup/install/windows-install/). WSL cần quyền admin lần đầu theo [Microsoft](https://learn.microsoft.com/en-us/windows/wsl/install). Không cần PostgreSQL hoặc Redis cài như Windows service.

## Chạy theo thứ tự

Mở PowerShell mới để nhận PATH. Từ root:

```powershell
cd 'D:\Fashion Shop'
node --version
git --version
flutter --version
docker info
docker compose version
node tools/init-env.cjs
docker compose config --quiet
docker compose up -d --wait postgres redis
```

init-env chỉ chạy lần đầu: tạo secret random vào root/.env và backend/.env bị Git ignore; từ chối ghi đè file có sẵn. Máy hiện tại đã có hai file này, bỏ qua init-env. Ví dụ cấu hình công khai nằm ở .env.example, không dùng placeholder cho production. DATABASE_URL password cần URL-encode nếu tự đặt ký tự đặc biệt; script tạo hex không gặp vấn đề này.

```powershell
cd backend
npm ci
npm run prisma:validate
npm run prisma:generate
npm run prisma:deploy
npm run prisma:seed
npm run start:dev
```

Swagger http://localhost:3000/api/docs, health http://localhost:3000/api/v1/health, readiness /api/v1/health/ready. Backend fail startup nếu DB không kết nối được. `npm run build; npm start` để chạy compiled code.

Terminal riêng:

```powershell
cd 'D:\Fashion Shop\backend'
npm run prisma:studio
```

Mở URL CLI Studio in ra. pgAdmin là tùy chọn, không bắt buộc.

Worker terminal:

```powershell
cd 'D:\Fashion Shop\backend'
npm run build
npm run worker
```

Redis cần sẵn sàng. Provider mặc định Disabled; AI_PROVIDER_URL/API_KEY chưa tự kích hoạt AI. Phải triển khai TryOnProvider và bind ở API/worker đồng thời.

## Flutter

```powershell
cd 'D:\Fashion Shop\frontend'
flutter pub get
flutter run -d chrome --web-port 5173 --dart-define=DEMO_MODE=true
```

Catalog API opt-in:

```powershell
flutter run -d chrome --web-port 5173 --dart-define=USE_REMOTE_CATALOG=true --dart-define=API_BASE_URL=http://localhost:3000/api/v1
```

Giữ CORS_ORIGINS khớp origin Flutter. Các chức năng account/checkout/admin vẫn demo, catalog remote chỉ đọc; xem migration-plan.md. Bỏ flag để trở lại demo đầy đủ.

Android emulator (sau khi bổ sung platform) dùng http://10.0.2.2:3000/api/v1. iOS simulator trên macOS thường dùng localhost; thiết bị thật dùng IP LAN của máy host và firewall phù hợp. Web production dùng HTTPS domain, không hardcode localhost. Dự án hiện chỉ có Flutter Web; chưa xác nhận mobile build.

## Containers và storage

```powershell
docker compose --profile app up -d --build
docker compose --profile storage up -d minio
```

API container tự deploy migrations sau PostgreSQL healthy; worker chờ API healthy. Root .env dùng localhost cho host. Compose override DATABASE_URL hostname postgres, REDIS_HOST=redis, storage=minio. Không copy DATABASE_URL container về cấu hình host.

MinIO console http://localhost:9001, API9000. Tạo bucket theo S3_BUCKET, giữ private; không public ảnh người dùng. Chưa có upload API. Nếu triển khai signed URL cho browser ngoài Docker, cần public S3 endpoint và DNS phù hợp; cấu hình nội bộ minio không dùng trực tiếp cho browser.

Named volumes giữ DB/Redis/MinIO. Không chạy `docker compose down -v` nếu muốn giữ dữ liệu.

## Kiểm thử

```powershell
cd 'D:\Fashion Shop'
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\backend.ps1 check
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-backend.ps1
cd frontend
flutter analyze
flutter test
flutter build web --release
flutter test test/live_catalog_test.dart --dart-define=LIVE_API_BASE_URL=http://localhost:3000/api/v1
```

test-backend tạo database riêng hậu tố _test nếu chưa có, không reset/drop DB. TEST_DATABASE_URL có thể override rõ ràng; script lưu vào backend/.env.test bị ignore. E2E tạo dữ liệu tổng hợp với UUID riêng cho mỗi lượt.

## PostgreSQL thử nghiệm đang chạy trước reboot

Do Docker Engine còn chờ reboot, phiên này dùng PostgreSQL thật18.4 tại 127.0.0.1:55432 trong .tools/test-services để chạy migrations/seed/E2E. Không cài thành Windows service. Credentials chỉ nằm trong .tools bị ignore. DB UTF8: wearly_utf8 và wearly_utf8_test. Hai DB WIN1252 từ thử nghiệm đầu không bị xóa; chúng không chứa dữ liệu kinh doanh.

API đang chạy với DATABASE_URL override trong process; backend/.env vẫn trỏ cấu hình Docker5432. Sau reboot PostgreSQL tạm không tự khởi động. Chạy quy trình Docker ở trên để dùng PostgreSQL17 đã khai báo trong Compose và seed lại dữ liệu demo.

## Xử lý lỗi

- Docker500 hoặc WSL virtualization: hoàn tất reboot, kiểm tra docker info; chưa coi compose up là thành công.
- P1001/connect refused: kiểm tra port/host/container health và DATABASE_URL.
- Invalid environment: thay placeholder, secrets khác nhau dài≥32, durations tính theo giây.
- UTF8/22P05: DB phải UTF8; không đổi dữ liệu tiếng Việt thành ASCII để né lỗi.
- Port3000 bị chiếm: tắt API dev cũ của dự án hoặc đổi PORT/CORS/base URL tương ứng.
- Prisma không tìm generated client: npm run prisma:generate trước build/test.
- npm11 chặn lifecycle script: package.json đã lưu allowScripts cho Prisma/argon2/esbuild/native packages; telemetry @scarf/scarf bị deny.
- pg8 hiện có deprecation warning từ query scheduling của Prisma khi include relations; không có query/test thất bại, chưa nâng pg9.
- PowerShell báo scripts disabled: dùng lệnh -ExecutionPolicy Bypass -File cho đúng script local như ví dụ; không cần đổi execution policy toàn máy.
