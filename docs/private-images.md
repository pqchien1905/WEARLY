# Ảnh riêng tư và vòng đời dữ liệu

Backend hiện hỗ trợ upload thật qua S3-compatible storage. Flutter Try-On vẫn là demo; chưa có adapter AI thật. Các kiểm thử dùng ảnh tổng hợp, không dùng ảnh cá nhân.

## API

Tất cả route cần bearer token, dưới `/api/v1/uploads/images`:

| Method | Đường dẫn | Kết quả |
|---|---|---|
| POST | `/uploads/images` | Multipart `file` và `consent=true`; 201 trả metadata, không trả object key |
| GET | `/uploads/images` | `{items:[...]}` tối đa20 ảnh còn hạn của chính user |
| GET | `/uploads/images/:id` | Metadata, `url`, `urlExpiresIn:60`; ảnh thiếu/khác owner/đã xóa/hết hạn trả404 |
| DELETE | `/uploads/images/:id` | 202 `{id,deleted:true}`; gọi lại vẫn202, khác owner404 |

Swagger có form multipart. POST nhận một JPEG/PNG tối đa8MiB,64..8192px mỗi chiều và tối đa16 triệu pixel. Backend kiểm tra magic bytes và MIME khớp, giải mã nghiêm ngặt, từ chối ảnh lỗi/animation, tự xoay theo orientation rồi mã hóa lại để bỏ EXIF/ICC/GPS và dữ liệu thừa. Tên file do client gửi không dùng làm đường dẫn. SHA256 tính trên bytes đã làm sạch.

Giới hạn hiện tại:30 POST/phút/IP trong một API process,20 ảnh chưa được purge và100 lượt upload/24h/user. Mỗi ảnh giữ24h; mỗi ảnh tối đa20 job AI. Giới hạn per-user dùng transaction/lock nên request đồng thời không vượt quota. Khi storage lỗi trả503 `STORAGE_UNAVAILABLE`; file quá lớn413; quota429. Rate limit phân tán và quota thương mại cần bổ sung trước khi chạy nhiều API replica.

## Lưu, đọc và xóa

Database lưu reservation trước khi ghi S3; chỉ đặt `verifiedAt` sau khi storage thành công. Nếu S3 trả lỗi hoặc mất phản hồi, reservation vẫn còn để cleanup xóa đúng key, kể cả object đã được S3 nhận. Reservation chưa verified sau15 phút được xem là dở dang. Không lưu bytes ảnh trong PostgreSQL.

DELETE đánh dấu `deletedAt`, ngăn cấp URL mới và chuyển job PENDING/PROCESSING thành FAILED với mã `IMAGE_UNAVAILABLE`. Worker chạy cleanup mỗi60s, tối đa50 ảnh/lượt; xóa ảnh gốc, các kết quả đã ghi metadata và key kết quả xác định từ job ID. Chỉ ghi `purgedAt` sau khi S3 xác nhận xóa thành công. Lỗi từng phần giữ tombstone để retry; cần worker và storage hoạt động để hoàn tất xóa vật lý. Metadata tombstone và job được giữ để vận hành; chưa có chính sách xóa metadata tài khoản dài hạn.

Worker công bố kết quả, cấp URL đọc và DELETE dùng cùng transaction lock theo ảnh. Nếu DELETE đến trước, worker không được công bố; nếu ghi kết quả đang diễn ra, DELETE chờ bước đó kết thúc rồi thu hồi quyền đọc và lên lịch purge. Upload bị tạm dừng phải kiểm tra lại reservation dưới lock trước khi ghi S3, tránh ghi lại ảnh đã purge. Lỗi/retry không đổi một job terminal trở lại pending. Timeout decode5s, S3 request8s, transaction công bố20s.

Cleanup lỗi được hẹn lại sau5 phút bằng `purgeRetryAt`. Mỗi lượt ưu tiên ảnh chưa thử, sau đó retry cũ nhất; một nhóm object lỗi không được chặn toàn bộ các ảnh khác. PNG được kiểm tra đủ chunk, CRC và IEND trước khi giải mã, bao gồm từ chối bytes thừa sau IEND.

URL đã cấp có hiệu lực tối đa60s, hoặc ngắn hơn khi object được purge. Xóa không thể thu hồi bytes đã tải xuống. Bucket phải private và **không bật versioning**: DeleteObjects hiện xóa object hiện tại, không quản lý lịch sử phiên bản hay Object Lock. Trên production, chọn storage phù hợp và credential chỉ có quyền cần thiết trên bucket/prefix của ứng dụng; helper tạo bucket local dùng tài khoản quản trị phát triển.

`S3_ENDPOINT` dùng cho server ghi/xóa. `S3_PUBLIC_ENDPOINT` dùng ký URL cho browser/provider; để trống thì dùng `S3_ENDPOINT`. Với Compose, endpoint nội bộ là `http://minio:9000`, URL local cho browser là `http://localhost:9000`. Provider ngoài máy cần endpoint HTTPS thực sự truy cập được, không dùng localhost hoặc hostname Docker nội bộ.

## Kho local và kiểm thử

Từ root, sau `npm ci` trong backend:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\start-storage.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\test-backend.ps1 -WithWorker -WithStorage
```

Helper tải bản MinIO Windows cố định từ [release chính thức](https://github.com/minio/minio/releases/tag/RELEASE.2025-09-07T16-13-09Z), kiểm SHA256 trước chạy, chỉ nghe127.0.0.1:9000/9001. Binary/data/log/PID nằm trong `.tools/minio` bị Git ignore; chạy lại helper sau reboot. Bucket chính theo `S3_BUCKET`, bucket test thêm `-test`; cả hai không có policy public và không có versioning. Helper từ chối sửa policy có sẵn. Không chạy native MinIO và container MinIO cùng cổng.

Release MinIO này chỉ dùng phát triển local; repository chính thức đã được archive. Đây không phải lựa chọn triển khai production đã được thẩm định.

E2E upload dùng PostgreSQL thật và MinIO thật: upload, strip metadata, anonymous403, signed GET200, ownership404, consent/format/size, xóa idempotent, storage outage, quota đồng thời, expiry/stale reservation, retry purge. Worker E2E dùng PostgreSQL và Memurai thật, provider/storage doubles để điều khiển race chính xác. Suite không reset DB hoặc xóa cả bucket.

Trước khi nối Flutter Web, cấu hình S3 CORS theo origin ứng dụng; chưa có remote Try-On UI ở phiên này. Thay đổi source/build đã được kiểm thử, nhưng API/worker cũ đang chạy trên máy chưa nạp bản mới vì lệnh dừng/khởi chạy tiến trình bị execution policy từ chối. Sau khi đóng tiến trình dev cũ hoặc reboot, chạy lại API/worker theo setup.md để bật cleanup và routes mới.
