# Thiết lập trên Windows

## Cài mới từ repository trên máy Windows khác

Phần này dành cho máy mới, dùng PostgreSQL/Redis Docker và backend chạy trên host. Máy hiện tại đã có dữ liệu native: dùng mục kế tiếp, không tạo lại `.env` hoặc đổi cổng theo phần cài mới.

1. Cài Git for Windows; cài **Node24 LTS** từ [Node.js](https://nodejs.org/en/download), giữ tùy chọn thêm PATH. Prisma nằm trong dependencies dự án, không cần cài Prisma global.
2. Cài [Docker Desktop cho Windows](https://docs.docker.com/desktop/setup/install/windows-install/), chọn WSL2/Linux containers, làm theo yêu cầu bật ảo hóa/WSL của bộ cài và Restart khi Windows yêu cầu. Mở Docker Desktop, chờ Engine running rồi kiểm tra `docker info`.
3. Cài [Flutter SDK](https://docs.flutter.dev/install/manual), thêm thư mục `bin` vào user PATH; cài Chrome để chạy Web. Dùng SDK stable có Dart>=3.10 theo `frontend/pubspec.yaml`, chạy `flutter doctor` để kiểm tra Web toolchain. Không cần cài Android Studio để chạy Web.
4. Mở PowerShell mới. Nếu máy cá nhân chặn `npm.ps1`, đặt `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` rồi mở terminal mới; không đổi chính sách máy do tổ chức quản lý. Máy hiện tại đã dùng RemoteSigned và chạy được `npm`.

Clone vào thư mục mới chưa có repository; không chạy clone đè dự án đang dùng:

```powershell
git clone https://github.com/pqchien1905/WEARLY.git
cd WEARLY
node --version
npm --version
flutter --version
node tools/init-env.cjs
docker compose config --quiet
docker compose up -d --wait postgres redis
cd backend
npm ci
npm run prisma:validate
npm run prisma:generate
npm run prisma:deploy
npm run prisma:seed
npm run start:dev
```

`init-env` sinh secrets ngẫu nhiên và tạo root/backend `.env`, từ chối ghi đè. Mặc định máy mới dùng localhost5432/6379; nếu các cổng đó đã bị chiếm, chọn cổng khác rồi cập nhật đồng bộ `POSTGRES_PUBLISHED_PORT`, `REDIS_PUBLISHED_PORT` ở root `.env` và `DATABASE_URL`, `REDIS_PORT` trong backend `.env` trước khi chạy. Chỉ đổi password env không đổi password của volume PostgreSQL đã khởi tạo; không xóa volume để né lỗi kết nối.

Terminal thứ hai tại root clone: `.\tools\frontend.ps1 api`. Mở `http://localhost:8080`, Swagger `http://localhost:3000/api/docs`. Từ backend, `npm run prisma:studio` mở giao diện database theo URL CLI in ra. Đăng ký tài khoản, rồi từ root dùng `node tools/grant-admin.cjs email-cua-ban@example.com` để cấp ADMIN cho chính tài khoản cần quản trị; đăng nhập lại tại `/#/admin`.

Các bước trên chạy catalog/tài khoản/giỏ/COD. Ảnh và worker cần storage/helper theo mục **Containers và storage**; provider AI chưa bật. `.tools` không nằm trên Git, vì vậy SDK/helper binary của máy cũ không được mang theo khi clone. Không cần cài PostgreSQL hoặc Memurai trực tiếp khi đã chọn Docker cho hai dịch vụ này.

## Công cụ và trạng thái máy ngày 18/10/2026

Node 24.22.0 LTS, Flutter/Dart portable đã có trong .tools; đã thêm vào user PATH. Git for Windows 2.55.0.5, WSL 3.0.3 và Docker Desktop 4.95.0 đã cài. Docker CLI 29.8.2, Compose 5.6.0 kiểm tra được.

**Đã cài PostgreSQL trực tiếp trên Windows:** PostgreSQL 17.11, psql và pgAdmin 4 từ [bộ cài EDB được PostgreSQL giới thiệu](https://www.postgresql.org/download/windows/). Service `postgresql-x64-17` tự khởi động cùng Windows, chỉ nghe localhost:5432. Database `wearly` và `wearly_test` dùng UTF8, owner `wearly` không có quyền superuser/CREATEDB/CREATEROLE.

**Hàng đợi local:** Memurai Developer 4.1.2 chạy dưới service `Memurai`, chỉ nghe 127.0.0.1:6379, AOF và `noeviction`. Đây là [Redis-compatible runtime trên Windows](https://redis.io/partners/memurai/). Bản Developer chỉ dành cho phát triển/test và tự dừng sau 10 ngày; khởi động lại service khi cần. Docker Redis vẫn là cấu hình triển khai dự kiến.

**Docker đã hoạt động sau restart lúc20:39 ngày18/10/2026:** bản sửa DISM hoàn tất lúc19:18 chỉ được áp dụng sau lần khởi động lại này. `vmcompute` và `hns` đã có đủ binary/service và đang Running; Windows không còn cờ CBS RebootPending. WSL2 chạy distro docker-desktop; Docker Desktop4.95.0/Engine29.8.2 khởi động thành công. `docker run --rm hello-world` tải image và chạy thành công (exit0). Không cần đổi BIOS hoặc reset dữ liệu Docker.

## Chạy bằng PostgreSQL và Memurai đã cài

Mở PowerShell mới để nhận PATH. Từ root:

```powershell
cd 'D:\Fashion Shop'
node --version
git --version
flutter --version
psql --version
Get-Service postgresql-x64-17,Memurai
& 'C:\Program Files\Memurai\memurai-cli.exe' ping
```

Máy hiện tại đã có root/.env và backend/.env; không chạy lại `node tools/init-env.cjs`. Script đó chỉ dùng lần đầu trên máy mới để tạo secret ngẫu nhiên, từ chối ghi đè. Database native đã được cấp tài khoản theo `backend/.env`, không cần thay mật khẩu. Nếu service dừng, chạy `Start-Service postgresql-x64-17,Memurai` trong PowerShell Administrator.

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

**Cập nhật 19/10/2026:** có 8 migrations, gồm đánh giá, hồ sơ phong cách và receipt chống tạo địa chỉ trùng. Sau khi lấy code mới, chạy generate/deploy/build trước khi khởi động lại API/worker. PostgreSQL/Memurai là Windows services tự khởi động; MinIO dùng helper bên dưới. `node tools/smoke-backend.cjs` từ root kiểm tra compiled API trên cổng tạm và tự đóng.

Terminal riêng:

```powershell
cd 'D:\Fashion Shop\backend'
npm run prisma:studio
```

Mở URL CLI Studio in ra.

### Mở pgAdmin

Start Menu → PostgreSQL 17 → **pgAdmin 4**. Kết nối đã được đăng ký ở nhóm **Wearly**, tên **WEARLY - PostgreSQL 17 (Windows)**. Host `127.0.0.1`, port `5432`, database và username `wearly`. Mật khẩu kết nối được đọc từ file riêng có ACL tại `.tools/pgadmin/pgpass.conf`; file này không được đưa lên Git. Nếu cần nhập thủ công, đọc credential trong `backend/.env`, không gửi qua chat hay đưa vào tài liệu công khai.

Đường dẫn cài: `C:\Program Files\PostgreSQL\17`. Dữ liệu service nằm trong thư mục `data` bên trong đường dẫn này; không nằm trong `.tools` và không mất khi đóng Codex. Tài khoản admin `postgres` chỉ dùng cài đặt; thông tin riêng được lưu tại `.tools/postgres-admin.json`.

Worker terminal:

```powershell
cd 'D:\Fashion Shop\backend'
npm run build
npm run worker
```

Redis cần sẵn sàng. Provider mặc định Disabled; AI_PROVIDER_URL/API_KEY chưa tự kích hoạt AI. Phải triển khai TryOnProvider và bind ở API/worker đồng thời.

`AI_QUEUE_PREFIX` mặc định `wearly`. Nếu đã chạy bản cũ với prefix mặc định của BullMQ (`bull`) và còn job, giữ `AI_QUEUE_PREFIX=bull` cho đến khi xử lý hết; không đổi prefix tùy ý vì mỗi prefix là một hàng đợi riêng.

## Flutter

Từ root dự án, khi backend đã chạy:

```powershell
.\tools\frontend.ps1 api
```

Lệnh mở Flutter trên Chrome, cổng8080, bật `USE_REMOTE_API=true` và API `http://localhost:3000/api/v1`. CORS hiện tại đã cho phép `http://localhost:8080`. Đăng ký tài khoản mới với mật khẩu12–128 ký tự, thêm địa chỉ, chọn size sản phẩm rồi đặt COD. Lịch sử đơn và giỏ hàng lưu theo tài khoản trong PostgreSQL; tải lại trang cần đăng nhập lại vì token chỉ ở RAM. Không cần Docker cho luồng native này.

`./tools/frontend.ps1 build-api` tạo Web release cho API mặc định. `-ApiUrl http://host:port/api/v1` đổi đích kết nối; cấu hình CORS của backend phải khớp origin frontend. Nếu cổng8080 đang chạy Flutter cũ, dùng `Ctrl+C` trong terminal đó rồi chạy lại lệnh trên.

Chạy demo độc lập bằng `.\tools\frontend.ps1 run`, hoặc:

```powershell
cd 'D:\Fashion Shop\frontend'
flutter pub get
flutter run -d chrome --web-port 5173 --dart-define=DEMO_MODE=true
```

Catalog API opt-in:

```powershell
flutter run -d chrome --web-port 5173 --dart-define=USE_REMOTE_CATALOG=true --dart-define=API_BASE_URL=http://localhost:3000/api/v1
```

`USE_REMOTE_CATALOG` chỉ đọc catalog API, các chức năng khác giữ chế độ demo. Dùng `USE_REMOTE_API` cho toàn bộ luồng mua hàng đã nối; không bật chức năng chưa hỗ trợ bằng dữ liệu mô phỏng. Xem [migration-plan.md](migration-plan.md).

Kiểm thử luồng mua hàng với database test riêng (cần backend đã build và migrate `wearly_test`):

```powershell
node tools/test-frontend-api.cjs
node tools/test-frontend-api.cjs --browser
```

Helper xác minh tên database kết thúc `_test`, tạo API trên cổng tạm, tạo fixture riêng rồi dọn đúng dữ liệu của lần chạy. Tùy chọn browser cần Playwright trong `.tools/browser`, Chrome cài sẵn và cổng4183 trống; tự build Web với URL API tạm. Sau kiểm thử browser, chạy `build-api` nếu muốn bản release dùng backend thường. Test không sửa dữ liệu trong `wearly`.

Android emulator (sau khi bổ sung platform) dùng http://10.0.2.2:3000/api/v1. iOS simulator trên macOS thường dùng localhost; thiết bị thật dùng IP LAN của máy host và firewall phù hợp. Web production dùng HTTPS domain, không hardcode localhost. Dự án hiện chỉ có Flutter Web; chưa xác nhận mobile build.

## Containers và storage

Kho ảnh native đã được cấu hình độc lập với Docker. Từ root chạy `powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\start-storage.ps1` để khởi động MinIO local, kiểm checksum và chuẩn bị hai bucket private/unversioned. API9000, console9001 chỉ nghe loopback; credential lấy từ backend/.env. Binary/data/log/PID trong `.tools/minio`; chạy lại helper sau reboot. Release cố định chỉ dùng phát triển, không xem là storage production đã được thẩm định. Chi tiết [private-images.md](private-images.md).

Docker Engine đã hoạt động. Có thể dùng môi trường Docker độc lập:

```powershell
cd 'D:\Fashion Shop'
docker info
docker compose config --quiet
docker compose up -d --wait postgres redis
```

Trên máy này `.env` đặt `POSTGRES_PUBLISHED_PORT=5433`, `REDIS_PUBLISHED_PORT=6380` để không tranh cổng với service Windows. Bản `.env.example` mặc định 5432/6379 dành cho máy chỉ dùng Docker. Hai PostgreSQL có volume/dữ liệu riêng; chạy migration/seed cho đúng database, không kỳ vọng dữ liệu native tự xuất hiện trong container. Khi chạy backend trên host với database Docker, đặt DATABASE_URL port 5433 và REDIS_PORT=6380 trong process/backend env. Container API/worker luôn dùng hostname postgres:5432 và redis:6379.

Đã chạy thực tế `docker compose up -d --wait postgres redis`: cả hai container Healthy; PostgreSQL17.11 trả query version thành công, Redis trả PONG. Cổng host127.0.0.1:5433/6380 đã xác nhận; Windows PostgreSQL/Memurai vẫn dùng5432/6379. Ngày19/10 đã build API/worker bằng hai Dockerfile, chạy trên database test Docker mới và xác minh auth, phân quyền, địa chỉ, giỏ, COD, replay và worker/outbox Redis. Database mặc định của Compose không được dùng cho lần xác minh này; backend/.env vẫn dùng native. MinIO container chưa kiểm chứng trong lượt này; storage E2E dùng MinIO native. Chi tiết [bàn giao hiện tại](handoff.md).

```powershell
docker compose --profile app up -d --build
docker compose --profile storage up -d minio
```

API container tự deploy migrations sau PostgreSQL healthy; worker chờ API healthy. Root .env dùng localhost cho host. Compose override DATABASE_URL hostname postgres, REDIS_HOST=redis, storage=minio. Không copy DATABASE_URL container về cấu hình host.

MinIO console http://localhost:9001, API9000. Dừng đúng process MinIO native trước khi chạy container cùng cổng; dữ liệu hai môi trường riêng biệt. Tạo bucket theo S3_BUCKET và bucket hậu tố -test bằng `node tools/prepare-storage.cjs` khi endpoint local đã sẵn sàng. Giữ private và không versioning. API upload đã triển khai. `S3_PUBLIC_ENDPOINT` dùng ký URL cho browser/provider, khác endpoint nội bộ `minio`; production cần HTTPS/DNS có thể truy cập từ client/provider.

Named volumes giữ DB/Redis/MinIO. Không chạy `docker compose down -v` nếu muốn giữ dữ liệu.

## Kiểm thử

Kiểm chứng cài mới trên Docker PostgreSQL (cần `npm ci` trong backend, root `.env`, Docker services ở trên và cổng3001 trống):

```powershell
node tools/verify-bootstrap.cjs --docker --check-config
node tools/verify-bootstrap.cjs --docker
docker build -t wearly-handoff-api:local -f backend/Dockerfile backend
docker build -t wearly-handoff-worker:local -f backend/Dockerfile.worker backend
node tools/verify-containers.cjs TEN_DATABASE_VUA_IN_RA
```

Thay `TEN_DATABASE_VUA_IN_RA` bằng tên `wearly_handoff_..._test` trong kết quả bootstrap. Công cụ dùng network Compose `wearly_default`, tạo DB mới bằng tài khoản Docker có CREATEDB; tài khoản ứng dụng native không có quyền này. Bootstrap xác minh đủ migrations, schema không lệch và seed lần hai giữ nguyên các bản ghi đã sửa. Container verifier dùng DB đó, tạo fixture mới, giữ lại dữ liệu và container đã dừng; báo cáo/log tại `.tools/handoff/<database>`. Không reset, drop, truncate hoặc xóa volume. Các báo cáo chứa metadata/hash, không chứa credential. Đây là công cụ phát triển local, không dùng với production.

Helper ghi checkpoint tên/ID container trước và trong quá trình chạy. Ctrl+C yêu cầu dừng có kiểm soát; chờ helper hoàn tất. Nếu Docker không phản hồi, kiểm tra `cleanup[].stopError` trong `containers.json` và dừng đúng ID test còn chạy; không reset Docker. Kill cưỡng bức tiến trình hoặc mất điện không thể bảo đảm cleanup tự chạy. Regression cho các nhánh ngắt/lỗi: `node --test tools/verify-containers.test.cjs`.

```powershell
cd 'D:\Fashion Shop'
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\backend.ps1 check
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-backend.ps1 -WithWorker -WithStorage
cd frontend
flutter analyze
flutter test
flutter build web --release
flutter test test/live_catalog_test.dart --dart-define=LIVE_API_BASE_URL=http://localhost:3000/api/v1
```

test-backend dùng database riêng hậu tố _test, không reset/drop DB. Native `wearly_test` đã được tạo bằng tài khoản admin vì role ứng dụng không có CREATEDB. TEST_DATABASE_URL có thể override rõ ràng; script lưu vào backend/.env.test bị ignore. `-WithWorker` bật thêm test PostgreSQL + Redis/Memurai thật; chỉ provider AI và object storage dùng test doubles. Mỗi lượt dùng queue namespace UUID riêng, không FLUSHDB. Bỏ flag nếu chỉ muốn kiểm tra commerce; worker tests sẽ được báo skipped. TEST_REDIS_HOST/TEST_REDIS_PORT có thể trỏ một Redis test khác.

Chỉ chạy một worker suite trên cùng test database: suite giữ PostgreSQL advisory lock và từ chối lượt chạy trùng. Nếu một lượt bị ngắt để lại AIJob pending/processing hoặc outbox chưa publish, suite tiếp theo dừng trước khi khởi động worker để người phát triển kiểm tra fixture đó; không tự xử lý job cũ bằng test provider.

`-WithStorage` bật7 upload E2E với PostgreSQL và S3/MinIO thật, dùng bucket riêng kết thúc `-test`; mặc định cùng endpoint/credential backend/.env. TEST_S3_ENDPOINT/TEST_S3_BUCKET có thể override. Không bật flag thì suite đó skip. Worker suite vẫn dùng storage double để điều khiển race; không gọi provider AI trả phí.

## PostgreSQL portable của phiên trước

Ở phiên đầu, khi Docker chưa chạy được, PostgreSQL thật18.4 tại127.0.0.1:55432 trong .tools/test-services được dùng cho migrations/seed/E2E. Không cài thành Windows service. Credentials chỉ nằm trong .tools bị ignore. DB UTF8: wearly_utf8 và wearly_utf8_test. Hai DB WIN1252 từ thử nghiệm đầu không bị xóa; chúng không chứa dữ liệu kinh doanh.

PostgreSQL tạm không còn được dùng sau reboot. Backend hiện dùng PostgreSQL 17 Windows tại 5432 với cấu hình sẵn có trong backend/.env. Dữ liệu demo đã seed lại; không xóa các database thử nghiệm cũ trong .tools.

## Xử lý lỗi

- Flutter báo `double/int is not a subtype of bool?` sau khi bấm F12 hoặc thay đổi chiều rộng: đã sửa xung đột PageStorage giữa vị trí cuộn và các mục thu gọn. Trong terminal đang chạy `flutter run`, nhấn `R` viết hoa để hot restart và nạp bản sửa, xóa trạng thái lỗi cũ trong bộ nhớ.
- Docker500 hoặc WSL virtualization: kiểm tra vmcompute/hns, `wsl --status` và trạng thái Windows pending restart. Lỗi trên máy này đã hết sau khi Restart áp dụng bản sửa DISM; không chạy reset/unregister distro để xử lý lỗi này.
- P1001/connect refused: kiểm tra port/host/container health và DATABASE_URL.
- Invalid environment: thay placeholder, secrets khác nhau dài≥32, durations tính theo giây.
- UTF8/22P05: DB phải UTF8; không đổi dữ liệu tiếng Việt thành ASCII để né lỗi.
- Port3000 bị chiếm: tắt API dev cũ của dự án hoặc đổi PORT/CORS/base URL tương ứng.
- Prisma không tìm generated client: npm run prisma:generate trước build/test.
- npm11 chặn lifecycle script: package.json đã lưu allowScripts cho Prisma/argon2/esbuild/native packages; telemetry @scarf/scarf bị deny.
- pg8 hiện có deprecation warning từ query scheduling của Prisma khi include relations; không có query/test thất bại, chưa nâng pg9.
- PowerShell báo scripts disabled: dùng lệnh -ExecutionPolicy Bypass -File cho đúng script local như ví dụ; không cần đổi execution policy toàn máy.
