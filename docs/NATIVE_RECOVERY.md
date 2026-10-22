# Sao lưu và phục hồi dữ liệu native local

Công cụ dành cho máy Windows đang chạy PostgreSQL17 và MinIO local. Nó tạo bản
sao mới, phục hồi vào database và bucket mới, rồi khóa phiên/tác vụ cũ trên bản
phục hồi. Không thay database đang dùng, không tự khởi động worker hay chuyển cửa
hàng sang bản phục hồi. Không cần dừng PostgreSQL, Redis, MinIO hoặc Mailpit.

## Tạo bản sao

Tại thư mục chứa code và `backend/.env` của cửa hàng:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\recovery.ps1 backup
```

Cần Node24, dependencies backend đã cài và bộ công cụ tại
`C:\Program Files\PostgreSQL\17\bin`. Chỉ chấp nhận database/S3 loopback và
môi trường không phải production. `-EnvFile` có thể chọn file cấu hình khác nằm
trong workspace, nhưng không sửa file đó. Không dùng file test cho dữ liệu thật.

Lệnh in đường dẫn bản sao trong `.tools/recovery/<mã-workspace>/<thời-gian-uuid>`.
`manifest.json` phải có `status: complete`. Giữ cả thư mục, không chỉ `database.dump`.

- Database dùng một snapshot PostgreSQL nhất quán: thay đổi sau thời điểm chụp
  không xuất hiện trong bản sao, dù quá trình sao lưu vẫn đang chạy.
- Ảnh catalog đã xác minh được sao chép từ bucket private và kiểm tra kích thước,
  SHA256. Ảnh cần thiết bị thiếu hoặc thay đổi làm bản sao thất bại.
- Ảnh đi kèm code trong `frontend/assets/images` được giữ riêng trong `bundled`;
  không tự ghi đè ảnh/code của workspace khi phục hồi. Lưu lại phiên bản Git
  được ghi trong manifest nếu cần khôi phục đúng phiên bản ứng dụng.
- Không tải URL ảnh bên ngoài, không sao lưu ảnh riêng tư Try-On hoặc ảnh kết quả.
  Manifest ghi số tham chiếu ngoài phạm vi. Metadata lịch sử trong database vẫn
  được giữ, rồi vô hiệu hóa khi phục hồi.
- Không sao chép `.env`, khóa Gemini/VNPay, Redis queue hay tài khoản PostgreSQL
  cấp hệ thống. Cần chuẩn bị lại dịch vụ/tài khoản ứng dụng nếu chuyển máy.

Mỗi ảnh tối đa8MiB; bộ file tối đa10000 và tổng archive được kiểm tra tối đa1GiB.
Lệnh thất bại khi vượt giới hạn, không công bố bản sao thiếu là thành công.
Bản sao chứa dữ liệu khách hàng và password hash: ACL Windows chỉ cấp current user
và SYSTEM. Không đưa vào Git, gửi chat hay chia sẻ công khai. Đó là kiểm soát truy
cập trên máy, không phải mã hóa archive hoặc chứng nhận backup ngoài máy.

## Phục hồi riêng để kiểm tra

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\recovery.ps1 restore -Archive 'DUONG_DAN_THU_MUC_BACKUP_COMPLETE'
```

Thay đường dẫn bằng thư mục do lệnh backup tạo cho cùng workspace. Công cụ xác
minh toàn bộ file/hash trước khi tạo đích. Cấu hình hiện tại phải chỉ đúng nguồn
database/bucket ghi trong manifest; không nhất thiết database nguồn còn hoạt động
để thực hiện restore. Nếu thay máy, cần bố trí lại archive trong workspace và
chuẩn bị cấu hình/role đúng trước khi sử dụng.

Quyền CREATE DATABASE lấy từ file riêng `.tools/postgres-admin.json` đã có trên
máy này. Không gửi file đó cho người khác. Admin chỉ tạo database mới và thu hồi
quyền CONNECT của PUBLIC; `pg_restore` dùng role ứng dụng không có quyền superuser,
CREATEDB hoặc CREATEROLE. Không có `DROP`, `--clean`, restore đè hay tự xóa đích lỗi.
Bucket mới private và không versioning; tên được tạo ngẫu nhiên, không cho chọn
lại bucket đang có.

Kết quả nằm trong thư mục `restore-...`:

- `result.json`: đích mới, giai đoạn, so sánh schema/từng bảng và ảnh, kết quả khóa
  dữ liệu nhạy cảm. `status: complete`, `stage: QUARANTINED` mới là thành công.
- `inspection.env`: cấu hình riêng với DB/bucket/queue mới và JWT secrets mới;
  Gemini, VNPay, email đều tắt. Đây là file bí mật, không copy đè `.env` đang dùng.
- Bản gốc, bản sao và đích phục hồi đều được giữ lại.

Trước khi khóa dữ liệu, công cụ chứng minh dữ liệu/schema phục hồi trùng snapshot.
Phép so sánh chỉ chuẩn hóa cách PostgreSQL biểu diễn phép chuyển mảng varchar sang
text tương đương; giá trị và kiểu dữ liệu vẫn được kiểm tra. Sau đó một giao dịch
áp dụng và kiểm tra chính xác các thay đổi sau:

| Dữ liệu | Trạng thái sau phục hồi |
|---|---|
| Tài khoản | Giữ thông tin/lịch sử/quyền nhưng `active=false` |
| Phiên đăng nhập | Thu hồi toàn bộ phiên cửa hàng/quản trị |
| Token quên mật khẩu | Đánh dấu đã dùng, không dùng lại link cũ |
| Ảnh riêng tư và kết quả Try-On | Hết hạn/tombstone; không có bản sao bytes |
| AI đang chờ/chạy | Job thất bại; usage chưa rõ kết quả chuyển UNKNOWN, giữ chi phí ước tính |
| AI outbox chưa phát | Đánh dấu đã xử lý để không tự gửi lại |
| Email đang chờ/chạy | FAILED với lý do LOCAL_RECOVERY_REVIEW, bỏ lease |
| Đơn hàng, thanh toán, đối soát, hoàn tiền | Giữ nguyên lịch sử và số tiền |

Vì vậy tài khoản cũ **không đăng nhập được** vào bản phục hồi. Đây là chủ đích:
backup cũ có thể chứa mật khẩu hoặc quyền đã bị thu hồi sau thời điểm chụp.
Không chỉ bật lại `active` để bỏ qua bước này. Trước một lần chuyển đổi thực sự,
người vận hành cần xác minh chủ tài khoản, đặt mật khẩu mới, rà lại quyền nhân viên,
đối soát giao dịch chưa rõ kết quả và quyết định những việc nào cần thực hiện lại.
Chưa có thao tác tự kích hoạt hàng loạt hoặc chuyển database trong công cụ này.

Có thể xem dữ liệu đích bằng pgAdmin với đúng tên database được in ra. Kiểm tra
`workspaceAssetsMatch`: nếu false, phải dùng đúng code/ảnh của phiên bản backup
trước khi coi giao diện đã phục hồi. Không chạy worker với bản phục hồi đang điều
tra và không sửa cấu hình cửa hàng hiện tại chỉ để thử archive.

## Khi lệnh lỗi

Giữ nguyên thư mục và xem `status`, `stage`, `error` trong manifest/report. Archive
`incomplete` hoặc `failed` không được restore. Đích lỗi có thể chưa được khóa phiên
và vẫn chứa tài khoản/tác vụ cũ: không khởi động ứng dụng trên đích đó. Chỉ report
`QUARANTINED` hoàn tất mới có cấu hình kiểm tra được tạo sau các bước xác minh.

Khắc phục dịch vụ/ảnh thiếu/dung lượng rồi tạo lượt mới; không sửa hash hoặc trạng
thái trong manifest để ép chạy. Mỗi lượt tạo đích mới và không dọn đích cũ tự động.
Xóa archive/DB/bucket cũ là quyết định bảo trì riêng sau khi xác minh tên và bản
sao còn giữ; công cụ không có lệnh xóa hàng loạt.

Backup thủ công chỉ phục hồi đến thời điểm snapshot. Cần chạy trước khi nâng cấp
và định kỳ theo mức mất dữ liệu chấp nhận được. Các bản trên cùng ổ đĩa không bảo
vệ khi mất/hỏng cả máy; sao lưu ngoài máy và môi trường production nằm ngoài phạm
vi local đã chọn.

## Bằng chứng kiểm tra22/10/2026

`node tools/verify-native-recovery.cjs` dùng database `_test`, bucket `-test`,
fixture UUID và advisory lock; giữ archive/đích, chỉ dọn chính fixture nguồn.
Kiểm tra snapshot khi có thay đổi đồng thời, ảnh thiếu, đích tồn tại, ảnh private,
phiên/token cũ, AI/mail đang chờ và API thực. Không gọi Gemini/VNPay hay gửi thư.
`--backup-only` chỉ chạy phần sao lưu.

Đã diễn tập với nguồn native `wearly`:42 bảng public,7 ảnh đi kèm; nguồn hiện
không có managed CatalogAsset nên việc chép object được chứng minh bằng fixture
riêng. Dữ liệu/schema phục hồi trùng snapshot trước các thay đổi được chỉ rõ ở
trên; API readiness/catalog/content đạt; dữ liệu nguồn và `.env` giữ nguyên.
Bằng chứng riêng tại `.tools/recovery/<mã-workspace>/restore-.../business-acceptance.json`.
Chưa chứng nhận phục hồi ngoài máy hoặc tự động đưa bản phục hồi vào sử dụng.

Tham khảo chính thức: [pg_dump](https://www.postgresql.org/docs/17/app-pgdump.html),
[pg_restore](https://www.postgresql.org/docs/17/app-pgrestore.html),
[snapshot synchronization](https://www.postgresql.org/docs/17/functions-admin.html#FUNCTIONS-SNAPSHOT-SYNCHRONIZATION).
