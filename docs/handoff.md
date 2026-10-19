# Bàn giao WEARLY — kiểm chứng ngày 19/10/2026

Luồng cửa hàng và quản trị đã chạy với PostgreSQL thật. Flutter được giữ nguyên công nghệ; API là nguồn dữ liệu cho các chức năng đã tích hợp. Báo cáo này thay số liệu lịch sử trong `backend-report.md`, không tuyên bố sẵn sàng production hoặc mọi tính năng thương mại/AI đã hoàn tất.

## A. Cấu trúc thực tế

```text
frontend/
  lib/core/             API client, phiên khách/quản trị, router, widget dùng chung
  lib/features/         Màn hình cửa hàng, tài khoản, quản trị và demo AI
  test/                 Widget, repository, phiên, checkout và live opt-in tests
  web/                  Flutter Web; chưa có platform mobile
backend/
  src/modules/          auth, users, products, cart, orders, admin,
                        wishlist, reviews, health, uploads, ai
  src/worker/           Worker/outbox/retention chạy tiến trình riêng
  prisma/               schema, seed, 8 migrations
  test/                 E2E PostgreSQL, worker Redis, uploads S3/MinIO
tools/                  Lệnh Windows, kiểm thử, bootstrap/container verification
docs/diagrams/          system, modules, database-erd, order-flow (Mermaid)
docker-compose.yml      PostgreSQL, Redis; profile app và storage
```

## B. Kiến trúc và sơ đồ

[Kiến trúc](architecture.md) mô tả modular monolith, worker tách tiến trình, REST `/api/v1`, Prisma/PostgreSQL, BullMQ/Redis và storage private. Các nguồn Mermaid: [hệ thống](diagrams/system.mmd), [11 feature modules](diagrams/modules.mmd), [ERD](diagrams/database-erd.mmd), [đặt đơn](diagrams/order-flow.mmd).

Phiên khách và quản trị độc lập. Quản trị viên nhập `/#/admin`; chưa đăng nhập sẽ chuyển đến `/admin/login`. Trang đăng nhập và footer cửa hàng không dẫn sang quản trị. Guard vẫn kiểm tra quyền phía server; việc ẩn liên kết không thay thế phân quyền.

## C. Những phần đã triển khai

- Đăng ký/đăng nhập/refresh/logout, Argon2id, JWT rotation/replay và RBAC; token chỉ trong RAM, reload cần đăng nhập lại.
- Catalog, lọc/tìm kiếm, SKU, tồn kho, danh mục/thương hiệu; quản trị có kiểm tra version khi chỉnh sửa tồn kho/trạng thái đơn.
- Hồ sơ, địa chỉ, phong cách; receipt PostgreSQL và payload retry trong Flutter tránh tạo địa chỉ trùng sau mất phản hồi.
- Giỏ hàng, COD, lịch sử/chi tiết/hủy đơn; backend tính tiền, snapshot đơn, transaction tồn kho và idempotency.
- Yêu thích, đánh giá sau đơn đã giao và “Đánh giá của tôi”, gồm sản phẩm ngừng bán; hiển thị ngay theo yêu cầu.
- API ảnh private, consent/ownership/quota/retention; AIJob/outbox/worker riêng, provider mặc định Disabled và không tạo kết quả AI giả.
- `tools/verify-bootstrap.cjs` và `tools/verify-containers.cjs` kiểm chứng cài mới bằng DB test riêng, giữ lại bằng chứng.

Các contract chi tiết ở [API](api.md), [quản trị](admin.md), [đánh giá](reviews.md), [phong cách](style-preferences.md), [retry địa chỉ](address-retries.md), [ảnh private](private-images.md).

## D. Database, migrations và seed

Schema có **24 models, 8 migrations**. Lần kiểm chứng mới tạo database UTF8 độc lập trong Docker PostgreSQL17, chạy validate/generate/deploy/status, sau đó `prisma migrate diff --from-config-datasource --to-schema prisma/schema.prisma --exit-code` trả0.

Seed tạo32 sản phẩm,256 biến thể,256 tồn kho,256 movement,32 ảnh,4 danh mục và1 thương hiệu. Công cụ sửa giá/tồn/tên sản phẩm/danh mục/thương hiệu/alt ảnh và thêm khách giả lập vào DB mới, chụp count/hash của mọi bảng nghiệp vụ rồi seed lần hai: **toàn bộ snapshot giữ nguyên**, không nhân bản hoặc ghi đè chỉnh sửa.

Bằng chứng local: `.tools/handoff/wearly_handoff_1792428128410_caec0914_test/result.json`. DB và log được giữ nguyên, không đưa lên Git. Lần chạy đầu bị thiếu PATH của `tsx` khi gọi Prisma seed ngoài npm; đã sửa helper thêm `backend/node_modules/.bin`. DB thử đầu cũng được giữ lại. Không sửa `.env` hoặc dữ liệu native `wearly`.

## E. API thực tế

OpenAPI của API container trả **47 đường dẫn** (một đường dẫn có thể có nhiều HTTP methods). Swagger local tại `http://localhost:3000/api/docs`; toàn bộ endpoint và body ở [api.md](api.md). API container đã kiểm tra readiness DB/Redis, register, cart401 khi thiếu token, admin403 với khách, address replay, cart/đơn COD/order replay. Payment COD vẫn PENDING.

Worker container riêng nhận outbox qua Redis và ghi `FAILED / AI_PROVIDER_NOT_CONFIGURED`, attempts1, không có TryOnResult. Đây là bằng chứng hàng đợi/worker hoạt động, không phải thử đồ AI thật. Báo cáo tại `.tools/handoff/wearly_handoff_1792428128410_caec0914_test/containers.json`; hai container test đã dừng và vẫn được giữ. MinIO container chưa được thử trong lượt này; storage E2E dùng MinIO native.

## F. Lệnh chạy trên máy hiện tại

Terminal backend:

```powershell
cd 'D:\Fashion Shop\backend'
npm run start:dev
```

Terminal frontend:

```powershell
cd 'D:\Fashion Shop'
.\tools\frontend.ps1 api
```

Mở `http://localhost:8080`. Nếu terminal đang ở `frontend`, dùng `..\tools\frontend.ps1 api`. Sau sửa source khi Flutter đang chạy, nhấn `R` viết hoa trong terminal Flutter để hot restart.

PostgreSQL17/pgAdmin đã cài trực tiếp, service ở5432; Memurai ở6379. Docker dùng DB/Redis riêng ở5433/6380, không bắt buộc cho luồng native. Để dùng ảnh/worker, cài mới, cập nhật migrations hoặc chạy lại verification: [setup.md](setup.md). Không chạy seed/migration vào DB khác theo phỏng đoán cổng.

## G. Kiểm thử và giới hạn bằng chứng

| Nhóm | Kết quả đã quan sát |
|---|---|
| Backend unit/lint/build | 11 unit đạt, lint/build đạt trong đợt sửa address retry; backend không đổi sau đó |
| Backend E2E native | 53/53 đạt, gồm PostgreSQL, worker Redis và upload MinIO thật |
| Flutter sau gỡ footer quản trị | 299 tests đạt, 2 live opt-in không chạy trong suite thường; analyzer sạch, Web API release build đạt |
| Live Flutter/API shopping | Chạy riêng đã đạt: mất phản hồi address sau commit, retry chỉ1 địa chỉ, đặt COD; Chrome/DB thật |
| Bootstrap DB mới | 8 migrations, schema diff0, seed lần hai giữ snapshot24 bảng |
| Docker | API và worker build thành công; container API/worker thực thi các kiểm tra tại mục E |
| Dependency audit | `npm audit --omit=dev`:0; audit toàn bộ:20 moderate,0 high/critical |
| Credential scan | Không tìm giá trị secrets đang có trong root/backend `.env` ở503 tracked files lúc audit; không phải quét toàn bộ lịch sử Git hoặc chứng nhận không có secret khác |

20 cảnh báo dependency cùng lan từ `sprintf-js` qua argparse/js-yaml và bộ Jest. [Advisory GHSA-hp3w-g68c-fv3c](https://github.com/advisories/GHSA-hp3w-g68c-fv3c) chưa có bản vá tại thời điểm kiểm tra. Không áp dụng `npm audit fix --force` vì gợi ý hạ major Jest/ts-jest. Dockerfile hiện cài cả devDependencies nên image local vẫn chứa bộ kiểm thử; kết quả audit production0 không có nghĩa image không còn cảnh báo. Cần tách build/runtime và thẩm định image trước production.

Logs lượt này nằm trong `.superpowers/sdd/2026-10-19-handoff-verification/`, bootstrap/container evidence trong `.tools/handoff/`; đều local/ignored. Các test chỉ chứng minh luồng được bao phủ, chưa xác minh tải lớn, khôi phục backup, mobile hoặc mọi trình duyệt.

## H. Các phần chưa hoàn tất

Theo [ánh xạ tính năng](migration-plan.md), vẫn còn reset mật khẩu/email, promotions, upload catalog chuyên dụng, audit/đối soát COD, Try-On/Stylist remote và thanh toán online. AI/provider trả phí và thanh toán online được Master Prompt cho phép ở giai đoạn sau; chưa có credential/provider phù hợp để bật. Các giao diện demo không được tính là chức năng API đã xong.

Trước production còn cần TLS/domain, backup/restore thực nghiệm, Redis-backed throttling khi scale, observability, quản lý secrets, image/dependency hardening và kiểm thử vận hành. Hiện chỉ xác minh môi trường phát triển local. Tiến độ và bước tiếp theo ở [PROGRESS.md](../PROGRESS.md).
