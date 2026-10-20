# Bàn giao tiến độ hoàn thiện — 20/10/2026

**Goal chưa hoàn tất.** Các thay đổi dưới đây đã kiểm chứng local; chưa triển
khai production. Phạm vi mở và phần phụ thuộc bên ngoài nằm trong
[SYSTEM_AUDIT.md](SYSTEM_AUDIT.md) và
[IMPLEMENTATION_PROGRESS.md](IMPLEMENTATION_PROGRESS.md).

## Chức năng đã xác minh

Catalog, đăng ký/đăng nhập, địa chỉ, giỏ hàng, COD, lịch sử/hủy đơn; quản trị
danh mục/thương hiệu/sản phẩm/ảnh/SKU/tồn kho/trạng thái đơn; yêu thích; đánh giá
sau mua hàng và lịch sử đánh giá; hồ sơ phong cách; lịch sử quản trị lưu thật,
phân trang trên dashboard. Năm suite Chrome chạy với
API/PostgreSQL thật, kiểm tra responsive và tính độc lập giữa các tài khoản.
Upload private và worker/outbox kiểm tra bằng MinIO/Redis/PostgreSQL thật.
Provider AI vẫn disabled, không được tính là kết quả AI thật.

## Sửa đổi đã thực hiện

| File/module | Kết quả |
|---|---|
| `backend/src/common/filters/api-exception.filter.ts` | Request JSON quá lớn trả 413; thông báo parser 400 không lặp lại body; FK không tồn tại trả 400 INVALID_REFERENCE |
| `backend/test/{commerce,admin,uploads}.e2e-spec.ts` | Regression lỗi đầu vào/FK/rollback; luôn đóng app và S3 khi cleanup lỗi |
| `backend/Dockerfile`, `Dockerfile.worker`, `docker-compose.yml` | Image runtime tách công cụ build/test; migration riêng chạy thành công trước API; runtime non-root |
| `tools/verify-containers{,.test}.cjs` | Kiểm chứng migration/runtime/COD/worker và 7 nhánh ngắt/lỗi cleanup |
| `tools/verify-bootstrap.cjs` | Không coi seed preservation là đạt nếu fixture UPDATE không tác động đúng một dòng |
| `tools/verify-recovery{,.test}.cjs` | Backup/restore local có guard, DB đích mới, giữ dữ liệu và so sánh schema/dữ liệu |
| `tools/verify-api-browser.cjs` | Đồng bộ focus Flutter và selector địa chỉ, bỏ lỗi giả trong browser test |
| `tools/serve.cjs` | URL sai encoding/NUL trả 400, không làm sập preview |
| `docs/setup.md` và tài liệu goal | Lệnh triển khai container, migration, backup/restore, audit và tiến độ |
| `backend/prisma`, `backend/src/modules/admin` | Bảng lịch sử và 10 loại thao tác, ghi nguyên tử cùng nghiệp vụ; API đọc chỉ ADMIN |
| `frontend/lib/features/admin/remote/admin_activity.dart` | Lịch sử thật trên dashboard, phân trang/tải lại và trạng thái lỗi/trống |
| Test admin/backend/Flutter và helper Chrome/container | Actor đúng, không lộ payload, rollback, phân quyền, lịch sử tồn tại sau reload |

## Kết quả và giới hạn

- Backend lint/build đạt; **11 unit + 58 E2E** đạt.
- Flutter analyze sạch; **301 tests** đạt, 2 live opt-in không chạy trong suite
  thường. Năm suite Chrome/API riêng đạt.
- **9 regression tests** cho helper đạt. Kiểm tra URL preview thực tế đạt.
- Build image API/worker/migration và chạy container thật đạt; runtime không có
  Jest, TypeScript, Prisma CLI, source hoặc `.env`; các container test đã dừng.
- DB mới có đủ 9 migrations, schema diff zero, seed replay giữ dữ liệu sửa.
- Backup local mới nhất phục hồi vào DB mới, khớp 26 bảng, columns/lengths, enums,
  constraints và indexes; source không đổi. API smoke trên bản phục hồi đạt.
- Production npm audit **0**; toàn bộ dependency tree vẫn có **20 Moderate**
  thuộc công cụ phát triển. Gitleaks history và tracked diff không phát hiện
  secrets. Không coi đây là pentest hoặc chứng nhận an toàn tuyệt đối.
- Có warning deprecation từ Prisma/pg khi chạy một số truy vấn; chưa gây test
  failure, cần kiểm tra trước nâng major pg.

Lượt E2E đầu thất bại 6 bài vì MinIO chưa chạy và cleanup bị treo; sau sửa và
khởi động storage, 55 bài đạt. Các lượt container đầu phát hiện Prisma optional
peers còn kéo CLI vào runtime; chỉ báo đạt sau kiểm tra image đã prune đúng.
Review độc lập tìm thêm trường hợp parser echo body; đã tái hiện, sửa và
review lại. Bằng chứng chi tiết local dưới `.tools/goal-*` và `.tools/handoff/`.

Lượt nhật ký quản trị: review độc lập không tìm thấy lỗi cần sửa; Chrome admin
chạy lại đạt, kiểm chứng đủ 10 loại thao tác và actor. Bản restore mới nhất là
`wearly_restore_1792476581460_91be3fa9_test`; lịch sử đã có dữ liệu cũng được
phục hồi khớp. API smoke trên bản restore thuộc lượt trước; lượt mới kiểm
schema/dữ liệu, không tuyên bố đã chạy lại smoke trên bản restore mới.

## Còn thiếu

| Hạng mục | Trạng thái / thông tin cần có |
|---|---|
| Email khôi phục mật khẩu | BLOCKED: cần lựa chọn/contract và cấu hình mail provider; chưa có endpoint reset thật |
| Try-On/Stylist và thanh toán online | BLOCKED: provider, tài khoản, contract và môi trường kiểm chứng |
| Khuyến mãi | BLOCKED: UI dùng %, schema dùng số tiền VND; đã hỏi quy tắc trước khi thay đổi tiền đơn hàng |
| Catalog upload chuyên dụng, đối soát COD, nội dung quản trị | Chưa hoàn tất; cần chốt phạm vi/quy tắc dựa trên thiết kế hiện có |
| Production | Chưa xác minh TLS/domain, secrets, tải lớn, nhiều instance, backup off-host, roles/grants và khôi phục S3; chưa có target/approval |

Các blockers ở bảng là blockers của từng hạng mục, không phải tuyên bố goal
hoàn thành hoặc toàn bộ công việc bị chặn.

## Khởi chạy

Terminal backend:

```powershell
cd 'D:\Fashion Shop\backend'
npm run prisma:deploy
npm run start:dev
```

Terminal frontend:

```powershell
cd 'D:\Fashion Shop'
.\tools\frontend.ps1 api
```

Mở `http://localhost:8080`; quản trị tại `/#/admin`. Swagger ở
`http://localhost:3000/api/docs`. Worker/storage và máy mới: xem
[setup.md](setup.md). Không ghi đè `.env`, không reset DB.

Migration mới `20261020100000_admin_audit` thêm bảng lịch sử, không sửa dữ liệu
cũ. Trong phiên này chỉ áp dụng migration vào DB test; DB phát triển hiện có
cần chạy `prisma:deploy` trước khi dùng bản mới. Lệnh ở trên dành cho môi trường
local đã cấu hình; không phải phê duyệt triển khai production.

Đánh giá hiện tại: nền tảng local và các luồng đã tích hợp có bằng chứng hoạt
động; còn chức năng và điều kiện vận hành phải hoàn tất trước production.
