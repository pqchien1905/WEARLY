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

Nội dung cửa hàng đã nối API: lưu bản nháp riêng, xuất bản có kiểm tra phiên
bản, tiêu đề trang chủ và chính sách công khai chỉ dùng bản đã xuất bản.
Trang quyền riêng tư/FAQ trong chế độ API mô tả đúng dữ liệu lưu trên máy chủ.

Khôi phục mật khẩu đã nối SMTP/worker: token dùng một lần15phút, thu hồi mọi
phiên, chống race với login/refresh và bỏ request cũ sau reset. Chrome đã
chạy từ thư SMTP local đến đăng nhập bằng mật khẩu mới; gửi thư qua dịch vụ
ngoài Internet còn chờ cấu hình. Xem [cấu hình khôi phục](password-recovery.md).

Upload catalog đã nối file picker → API → MinIO → preview/public storefront.
Ảnh được kiểm tra/làm sạch; retry không ghi trùng; thay đổi gallery và audit
nguyên tử. Bỏ ảnh khỏi gallery không xóa bytes mà đơn cũ có thể tham chiếu.
Xem [hướng dẫn ảnh catalog](catalog-images.md).

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
| `backend/src/modules/content`, StoreContent migration | Lưu nháp/xuất bản nguyên tử, version chống ghi đè, public không lộ draft |
| `frontend/.../content_page.dart`, `content_provider.dart`, `store_content.dart` | Form lưu/xuất bản, tải lại khi xung đột, cập nhật công khai sau phản hồi muộn |
| Home, info, FAQ, product policy links | Hiển thị nội dung đã xuất bản và sửa thông tin demo sai trong chế độ API |
| `backend/src/modules/recovery`, `worker/recovery.worker.ts`, migration | SMTP, token hash/expiry, cutoff, session revocation, queue deadlines/retention |
| `backend/src/common/transaction.ts`, auth service | Khóa login/reset và retry đúng raw PostgreSQL adapter conflict |
| Flutter auth/reset route/forms và helper Chrome | Request thật, token không giữ trong URL, password confirmation, kết quả không chắc chắn, bảo vệ phiên mới |
| `catalog-media`, CatalogAsset migration, storage/retention worker | ADMIN upload, public verified read, idempotency, khóa gallery, audit và dọn upload thất bại |
| Flutter multipart/admin product editor/FashionImage | Chọn file, preview, retry cùng key, gallery baseline, đường dẫn ảnh ổn định |

## Kết quả và giới hạn

- Backend lint/build đạt; **16 unit + 80 E2E** đạt.
- Flutter analyze sạch; **317 tests** đạt, gồm rời phiên lúc xuất bản;
  2 live opt-in không chạy trong suite
  thường. Năm suite Chrome/API riêng đạt.
- **13 regression tests** cho helper đạt. Kiểm tra URL preview thực tế đạt.
- Build image API/worker/migration và chạy container thật đạt; runtime không có
  Jest, TypeScript, Prisma CLI, source hoặc `.env`; các container test đã dừng.
- DB mới có đủ 12 migrations, schema diff zero, seed replay giữ dữ liệu sửa.
- Backup local mới nhất phục hồi vào DB mới, khớp 29 bảng, columns/lengths, enums,
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

Lượt nội dung: Chrome admin đã kiểm tra lưu nháp → xuất bản → sửa nháp không
đổi bản công khai, đủ 12 loại sự kiện audit. Review chỉ ra test cần chờ PUT
thành công trước khi chuyển trang; đã sửa và chạy lại đạt. Restore mới nhất
`wearly_restore_1792477270144_c48e1b3f_test` khớp schema/dữ liệu và **compiled
API smoke đạt trên chính bản phục hồi này**, gồm public content200, private
content/audit401 khi chưa đăng nhập.

Lượt khôi phục mật khẩu: thêm Chrome SMTP thật và chạy lại Chrome mua hàng đều
đạt. Review độc lập xác nhận các nhánh timeout, phản hồi muộn và retry
transaction đã sửa. Fresh bootstrap:
`wearly_handoff_1792479244018_790906ee_test`; restore:
`wearly_restore_1792479398226_e548ec01_test`. Có một credential tổng hợp đã
tiêu thụ để kiểm tra phục hồi bảng PasswordResetToken; toàn bộ28 bảng khớp,
source giữ nguyên và API smoke trên bản restore đạt. Default-API Web release
đã build lại.

Lượt catalog: Chrome quản trị chạy picker/upload thật và đọc ảnh công khai,
lưu ảnh bìa trên mobile, reload và xem storefront; đủ13 loại audit. Review
phát hiện và sửa form bị khóa khi gallery vừa đầy; regression đã qua.
Bootstrap `wearly_handoff_1792480803907_2ad86a6e_test`, restore
`wearly_restore_1792480903411_6d6b1003_test`. API smoke trên bản restore đạt,
kể cả đọc catalog object từ bucket nguồn còn giữ; chưa gọi đây là restore S3.

Sau đó đã chạy **restore object catalog riêng**: xuất file vào archive rồi
phục hồi sang bucket mới `wearly-restore-1792481409890-58861048-test`. API dùng
DB đã restore và bucket mới trả đúng bytes; hash/MIME/size và anonymous403
đạt, nguồn không đổi. Phạm vi một ảnh catalog tổng hợp; chưa kiểm chứng
private Try-On, backup ngoài máy hoặc phục hồi production.

Review công cụ phục hồi phát hiện lỗi Nest tự thoát trước cleanup khi khởi
tạo thất bại; đã sửa, kiểm thử bằng tiến trình con và chạy lại phục hồi
thành công vào `wearly-restore-1792481707240-02dceafb-test`.

Rà soát retention tiếp theo tái hiện object riêng tư được PUT muộn sau lần
DELETE đầu. Worker nay định kỳ dọn lại bản ghi đã thu hồi, giữ quyền đọc bị
chặn và không đổi quota.80 E2E đạt; API/worker image mới qua container checks
trên `wearly_handoff_1792481891987_07599963_test`. Không đổi schema; bằng chứng
DB/object restore ở trên vẫn thuộc lượt catalog.

## Còn thiếu

| Hạng mục | Trạng thái / thông tin cần có |
|---|---|
| Email khôi phục mật khẩu ngoài Internet | BLOCKED: cần cấu hình provider/sender và xác minh delivery; endpoint/frontend/SMTP local đã chạy thật |
| Try-On/Stylist và thanh toán online | BLOCKED: provider, tài khoản, contract và môi trường kiểm chứng |
| Khuyến mãi | BLOCKED: UI dùng %, schema dùng số tiền VND; đã hỏi quy tắc trước khi thay đổi tiền đơn hàng |
| Đối soát COD | Chờ quy tắc xác nhận thu tiền; không tự đổi DELIVERED thành PAID |
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

Migration mới `20261020100000_admin_audit`, `20261020110000_store_content`
và `20261020120000_password_recovery` thêm lịch sử/nội dung/token và cutoff
nullable, không đổi mật khẩu hoặc dữ liệu nghiệp vụ cũ. Chỉ áp dụng vào DB test; DB phát triển hiện có
cần chạy `prisma:deploy` trước khi dùng bản mới. Lệnh ở trên dành cho môi trường
local đã cấu hình; không phải phê duyệt triển khai production.

Đánh giá hiện tại: nền tảng local và các luồng đã tích hợp có bằng chứng hoạt
động; còn chức năng và điều kiện vận hành phải hoàn tất trước production.
