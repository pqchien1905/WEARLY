# Ảnh catalog

Quản trị viên mở sản phẩm đã lưu, lưu các thay đổi đang sửa rồi chọn **Tải
ảnh từ máy**. Upload thêm ngay vào bộ ảnh trên server; không cần bấm Lưu
lần nữa. Ảnh đầu tiên là ảnh bìa. Có thể sửa mô tả/màu, bỏ ảnh hoặc tiếp
tục dùng URL HTTPS và ảnh bundled như trước.

Ảnh catalog có đường dẫn công khai, kể cả khi sản phẩm chưa mở bán. Không
dùng chức năng này cho ảnh cá nhân. Ảnh Try-On vẫn có endpoint, quyền sở
hữu, consent và vòng đời riêng; bucket S3 không được mở public.

## API

- `POST /api/v1/admin/products/:id/images`: ADMIN, multipart một `file`,
  `alt` bắt buộc (có thể rỗng, tối đa200 ký tự), `color` tùy chọn tối đa60.
  Header `Idempotency-Key` là UUIDv4, phạm vi theo quản trị viên.
- JPEG/PNG tối đa8MiB,64–8192px mỗi chiều và16MP. MIME, signature, cấu trúc
  và giải mã phải phù hợp. Re-encode loại metadata, EXIF/GPS và payload dư.
- Thành công201 trả `{id,productId,url,alt,color,mimeType,size,width,height}`.
  `url` có dạng `catalog/images/<UUID>`, giải theo base API cấu hình. Không
  trả object key, credentials hoặc signed URL.
- `GET /api/v1/catalog/images/:id` công khai chỉ phục vụ asset đã xác minh.
  Đọc S3 có giới hạn thời gian/dung lượng, so hash và size đã lưu trước khi
  trả MIME cố định, `nosniff`, CORP cross-origin, cache public một giờ.
  UUID private-user/không tồn tại trả404; storage lỗi trả503 an toàn.
- Gallery tối đa20 ảnh. `PATCH /admin/products/:id` vẫn thay toàn bộ gallery
  khi gửi `images`; managed reference phải thuộc đúng sản phẩm.

## Gửi lại và tính nhất quán

Reservation lưu input hash của sản phẩm, bytes gốc, MIME và metadata. Chỉ
request tạo reservation sở hữu quyền PUT. Replay khác input trả409;
request còn chạy trả409 `UPLOAD_IN_PROGRESS`. Replay đã thành công trả
receipt gốc, không PUT, thêm ảnh hay ghi audit lần nữa, kể cả ảnh đã bị
bỏ khỏi gallery sau đó.

PUT chạy ngoài cơ chế tự retry transaction, dưới khóa asset. Finalize lấy
cùng khóa dòng Product với gallery PATCH, kiểm tra giới hạn rồi ghi gallery,
verified asset và `PRODUCT_IMAGE_UPLOADED` trong cùng transaction. Lỗi PUT
hoặc audit không công khai ảnh; reservation thất bại không được tái sử dụng.

Mất phản hồi giữ nguyên file/key trong RAM. **Kiểm tra lại ảnh tải lên** gửi
lại key đó rồi đọc gallery hiện tại, cập nhật cả form và baseline. Chưa
xác định kết quả thì khóa chỉnh sửa; từ chối chắc chắn như gallery đầy sẽ
đọc lại gallery rồi cho sửa tiếp. Refresh token chỉ retry một lần sau401,
không tự retry các lỗi mạng/503. Đổi phiên vô hiệu hóa kết quả cũ.

## Vòng đời và vận hành

Migration `20261020130000_catalog_upload` thêm CatalogAsset và enum audit.
Chạy generate/deploy/build trước khi khởi động lại API/worker. Dùng cấu
hình S3 hiện có; không cần policy public bucket.

Worker dọn reservation chưa xác minh quá15phút hoặc đã thất bại, tối đa50
mỗi lượt. Khóa asset bảo vệ upload đang finalize; revoke trước DELETE.
Tombstone được kiểm tra lại mỗi24giờ để dọn PUT được provider hoàn tất muộn;
DELETE lỗi retry sau5phút. Không tự xóa verified asset khi bỏ khỏi gallery
hoặc ẩn sản phẩm, vì snapshot đơn hàng có thể còn tham chiếu.

`productId`/`actorId` trên CatalogAsset là UUID lịch sử, không cascade. Cần
sao lưu cả PostgreSQL và object store; restore riêng DB không khôi phục
bytes ảnh. Chính sách xóa lâu dài/off-host recovery cần được chốt trước
production.

Kiểm thử: `tools/test-backend.ps1 -WithWorker -WithStorage` dùng DB/bucket test
riêng; `node tools/test-frontend-api.cjs --admin` kiểm tra file picker thật,
preview, lưu ảnh bìa và reload. E2E kiểm tra replay/concurrency, rollback audit,
late PUT cleanup, private bucket và managed references sai sản phẩm.
