# Quản trị trực tuyến

Chạy backend bằng `npm run start:dev` trong `backend`. Từ thư mục gốc chạy `.\tools\frontend.ps1 api`; nếu đang đứng trong `frontend`, dùng `..\tools\frontend.ps1 api`.

Mở `http://localhost:8080/#/admin/login` để đăng nhập quản trị. Trang này có giao diện riêng, không có menu mua sắm, giỏ hàng hay đăng ký công khai. Truy cập trực tiếp một trang quản trị khi chưa đăng nhập sẽ chuyển tới form này, rồi trở lại đúng trang sau khi xác thực. Liên kết **Quản trị** cuối cửa hàng cũng mở form quản trị.

Khách hàng dùng `http://localhost:8080/#/login`. Hai khu vực giữ phiên độc lập: đăng nhập, hết phiên hoặc đăng xuất ở một khu vực không thay đổi phiên còn lại. ADMIN vẫn có thể đăng nhập riêng ở cửa hàng để mua sắm. Tài khoản CUSTOMER bị từ chối ngay tại API đăng nhập quản trị; backend tiếp tục kiểm tra quyền trên mọi yêu cầu quản trị.

Các phiên chỉ ở RAM, vì vậy reload trình duyệt cần đăng nhập lại. Dữ liệu vẫn được giữ trên PostgreSQL. Chế độ demo (`run`) hiển thị rõ dữ liệu minh họa và không yêu cầu tài khoản quản trị thật.

Tại máy phát triển, cấp quyền cho email đã đăng ký bằng:

```powershell
node tools/grant-admin.cjs email-cua-ban@example.com
```

Chạy từ root. Script dùng cấu hình PostgreSQL của backend, chỉ cập nhật tài khoản hiện có và thu hồi các phiên cũ khi đổi quyền. Không tạo tài khoản/mật khẩu mặc định. Không sửa `.env` hoặc dùng script này cho người chưa được chủ cửa hàng cho phép.

## Các thao tác đã nối

- Tổng quan: số sản phẩm, đơn, đơn chờ xác nhận, khách hàng và tổng số lượng kho từ toàn database.
- Danh mục (`/#/admin/categories`) và thương hiệu (`/#/admin/brands`): danh sách phân trang 20 mục, số sản phẩm liên quan, thêm mới và đổi tên. Tên tối đa 100 ký tự; đường dẫn gồm chữ thường không dấu, số và dấu gạch nối, không trùng trong cùng loại. Đường dẫn được giữ cố định sau khi tạo, chưa có thao tác xóa. Khi người khác đã đổi tên, tải lại trước khi sửa tiếp. Danh mục mới xuất hiện ở cửa hàng và cả hai loại đều chọn được khi thêm/sửa sản phẩm.
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
