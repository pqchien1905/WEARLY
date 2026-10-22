# WEARLY — Fashion AI Commerce

Ứng dụng Flutter hiện có và backend NestJS/PostgreSQL cho thương mại thời trang.

- [Cài đặt và chạy trên Windows](docs/setup.md)
- [Vận hành local, giám sát và kiểm thử tự động](docs/LOCAL_OPERATIONS.md)
- [Tiến độ hoàn thiện local hiện tại](docs/LOCAL_COMPLETION_PROGRESS.md)
- [Audit và sửa lỗi hệ thống hiện tại](docs/SYSTEM_AUDIT.md)
- [Tiến độ goal và phần còn thiếu](docs/IMPLEMENTATION_PROGRESS.md)
- [Bàn giao đợt hoàn thiện hệ thống](docs/SYSTEM_HANDOFF.md)
- [Kiến trúc và quyết định thay đổi](docs/architecture.md)
- [Database, migrations và tồn kho](docs/database.md)
- [API thực tế và Swagger](docs/api.md)
- [Upload ảnh riêng tư, quyền truy cập và cleanup](docs/private-images.md)
- [Ánh xạ mock → API](docs/migration-plan.md)
- [Bàn giao hiện tại: kết quả kiểm thử và phần còn thiếu](docs/handoff.md)
- [Tiến độ công việc](PROGRESS.md)
- [Đối chiếu yêu cầu và bằng chứng nghiệm thu local](docs/acceptance.md)
- [Lịch sử frontend](README_FRONTEND.md)

```text
frontend/       Flutter, Riverpod, go_router; giữ UI và mock demo
backend/        NestJS 11, Prisma 7, REST API và AI worker riêng
docs/           Tài liệu, sơ đồ Mermaid, kiểm thử
design-system/  Thiết kế và tài sản tham chiếu hiện có
tools/          Script phát triển PowerShell/Node
docker-compose.yml  PostgreSQL, Redis; profile storage và app
```

Bắt đầu trên máy Windows đã cấu hình PostgreSQL và Memurai:

```powershell
Get-Service postgresql-x64-17,Memurai
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\start-storage.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\local.ps1 build
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\local.ps1 start
```

Lệnh trên dùng dependencies và schema đã chuẩn bị, khởi động API, worker và web riêng. Nếu bật email, khởi động Mailpit trước theo [hướng dẫn vận hành](docs/LOCAL_OPERATIONS.md). Dùng `local.ps1 status` để xem, `local.ps1 stop` để dừng đúng tiến trình đã tạo; các dịch vụ dữ liệu vẫn chạy. Máy mới hoặc chạy bằng Docker: làm theo [setup.md](docs/setup.md); không ghi đè `.env` hoặc seed lại database nghiệp vụ.

Swagger: http://localhost:3000/api/docs. Catalog API: http://localhost:3000/api/v1/products.

Nếu phát triển giao diện bằng hot reload, dùng API dev và chạy Flutter thay cho web runtime:

```powershell
.\tools\frontend.ps1 api
```

Nếu terminal đang ở `D:\Fashion Shop\frontend`, chạy `..\tools\frontend.ps1 api`.

Mở Chrome tại `http://localhost:8080`: đăng ký/đăng nhập, hồ sơ, địa chỉ, giỏ hàng, đặt COD, lịch sử và hủy đơn dùng dữ liệu PostgreSQL.

- Khách hàng: `http://localhost:8080/#/login`.
- Quản trị: nhập trực tiếp `http://localhost:8080/#/admin`; nếu chưa có phiên quản trị sẽ chuyển đến `/admin/login`. Dành cho tài khoản ADMIN để quản lý sản phẩm, danh mục, thương hiệu, biến thể, tồn kho, đơn hàng và xem khách hàng. Giao diện cửa hàng không có liên kết đăng nhập quản trị.

Trong quản trị, mở **Danh mục** hoặc **Thương hiệu** để thêm mới và đổi tên. Sau đó chọn chúng trong biểu mẫu sản phẩm. Danh mục ở trang chủ/cửa hàng lấy từ API; đổi tên giữ nguyên đường dẫn và sản phẩm đã liên kết.

Khách có đơn **đã giao** có thể chọn **Xem đánh giá** trên trang sản phẩm để gửi 1–5 sao và nội dung. Đánh giá hiển thị ngay; vào **Tài khoản → Đánh giá của tôi** để xem, sửa hoặc xóa, kể cả xóa đánh giá của sản phẩm ngừng bán. [Hướng dẫn đánh giá](docs/reviews.md).

**Tài khoản → Phong cách của tôi** lưu size, phong cách, màu ưu tiên và ngân sách vào PostgreSQL, giữ qua lần đăng nhập sau. [Hướng dẫn hồ sơ phong cách](docs/style-preferences.md).

Hai khu vực có giao diện và phiên đăng nhập riêng; đăng xuất một bên giữ nguyên phiên bên kia. ADMIN có thể đăng nhập riêng ở cửa hàng để mua sắm. Phiên giữ qua tải lại trang bằng cookie HttpOnly, JWT chỉ ở bộ nhớ. Yêu thích lưu theo tài khoản trên PostgreSQL: bấm trái tim ở sản phẩm hoặc **Lưu yêu thích** trong giỏ; mở `http://localhost:8080/#/wishlist` để xem/bỏ. Danh sách tối đa200 mục, sản phẩm không còn mở bán được báo rõ và vẫn bỏ được.

Chạy `.\tools\frontend.ps1 run` để xem demo độc lập. Khôi phục mật khẩu đã có API/worker/SMTP, cần bật và cấu hình gửi thư; xem [hướng dẫn](docs/password-recovery.md). Gemini Stylist/Try-On, VNPay sandbox, giao hàng mô phỏng và đối soát COD đã có luồng local. Kết nối provider thật còn cần khóa và nghiệm thu riêng; xem [tiến độ hiện tại](docs/LOCAL_COMPLETION_PROGRESS.md).

Cấp ADMIN cho một tài khoản đã đăng ký, từ thư mục gốc: `node tools/grant-admin.cjs email-cua-ban@example.com`. Công cụ chỉ đổi quyền tài khoản hiện có và thu hồi các phiên cũ; không tạo mật khẩu mặc định. Đăng nhập lại sau khi được cấp quyền. Chi tiết: [Quản trị trực tuyến](docs/admin.md).
