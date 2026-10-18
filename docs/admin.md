# Quản trị trực tuyến

Chạy backend bằng `npm run start:dev` trong `backend`. Từ thư mục gốc chạy `.\tools\frontend.ps1 api`; nếu đang đứng trong `frontend`, dùng `..\tools\frontend.ps1 api`.

Đăng nhập tài khoản ADMIN rồi mở `http://localhost:8080/#/admin` hoặc liên kết **Quản trị** cuối trang. Khách hàng và người chưa đăng nhập không đọc được dữ liệu quản trị; backend kiểm tra quyền trên từng yêu cầu. Phiên đăng nhập chỉ ở RAM, vì vậy reload trình duyệt cần đăng nhập lại.

Tại máy phát triển, cấp quyền cho email đã đăng ký bằng:

```powershell
node tools/grant-admin.cjs email-cua-ban@example.com
```

Chạy từ root. Script dùng cấu hình PostgreSQL của backend, chỉ cập nhật tài khoản hiện có và thu hồi các phiên cũ khi đổi quyền. Không tạo tài khoản/mật khẩu mặc định. Không sửa `.env` hoặc dùng script này cho người chưa được chủ cửa hàng cho phép.

## Các thao tác đã nối

- Tổng quan: số sản phẩm, đơn, đơn chờ xác nhận, khách hàng và tổng số lượng kho từ toàn database.
- Sản phẩm: danh sách phân trang, thêm/sửa metadata, chọn danh mục/thương hiệu có sẵn, bộ ảnh tối đa 20 ảnh và ẩn/hiện. Ảnh dùng URL HTTPS công khai hoặc asset bundled; chưa có trình tải ảnh catalog.
- Biến thể: tạo SKU với size/màu/giá; sửa giá và trạng thái bán. SKU/size/màu đã tạo không đổi định danh. SKU mới có tồn kho 0; nhập kho ở thao tác riêng.
- Tồn kho: tăng/giảm bằng số nguyên và lý do; gửi phiên bản đã đọc. Khi xung đột hoặc không xác định kết quả, tải lại trước khi thao tác tiếp; không tự gửi lặp lệnh tăng kho.
- Đơn: xem người nhận, sản phẩm, phí giao và tổng tiền đã chốt; chuyển PENDING → CONFIRMED → SHIPPED → DELIVERED, kiểm tra version. Giao xong không đồng nghĩa COD đã thu tiền.
- Khách hàng: danh sách tài khoản chỉ đọc, không gửi hash mật khẩu/token tới Flutter.

Các thao tác lưu metadata, SKU và tồn kho tách biệt; không trình bày một chuỗi nhiều request như một giao dịch nguyên tử. Sản phẩm mới mặc định ẩn. Cần có biến thể đang bán để xuất hiện trên cửa hàng. Ẩn sản phẩm/biến thể giữ nguyên lịch sử đơn.

Khi sửa sản phẩm, Flutter chỉ PATCH các trường đã đổi. Sửa tên/chất liệu không gửi lại bộ ảnh cũ; bộ ảnh chỉ được thay thế khi bạn sửa ảnh. Hai người cùng sửa chính một trường metadata vẫn áp dụng lần lưu sau cùng; kiểm tra lại sản phẩm trước khi chỉnh sửa đồng thời. Kho và trạng thái đơn dùng expectedVersion để từ chối dữ liệu cũ.

Khuyến mãi, nội dung, AI monitoring, đối soát COD và audit quản trị đầy đủ chưa triển khai. Các trang demo vẫn có trong chế độ `run`; API mode không dùng dữ liệu demo cho các mục này. Chưa kiểm chứng native Android/iOS hoặc môi trường production.

## Kiểm chứng

`powershell -NoProfile -File tools/test-backend.ps1` chạy E2E PostgreSQL riêng `_test`. `node tools/test-frontend-api.cjs --admin` tạo tài khoản/sản phẩm/đơn kiểm thử riêng, build Flutter release rồi chạy Chrome thật. Helper chỉ dọn các ID/email/slug của chính lượt chạy, không reset database phát triển. Ảnh/log ở `.tools/api-admin-verification/` (ignored). Sau kiểm thử, chạy `.\tools\frontend.ps1 build-api` để build lại với API mặc định `localhost:3000`.
