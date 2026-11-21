# Bộ sưu tập dùng PostgreSQL — 23/10/2026

Trang `http://localhost:8080/#/collections` và từng trang chi tiết hiện đọc API
`/api/v1/collections`. Đã bỏ ba bộ sưu tập viết cố định, các ID sản phẩm mẫu và
giới hạn chỉ xem được 12 sản phẩm đầu. Không tự thay dữ liệu lỗi/rỗng bằng demo.

## Dữ liệu đã áp dụng

| Đường dẫn | Phong cách | Sản phẩm công khai |
| --- | --- | ---: |
| `/collections/everyday` | Tối giản | 7 |
| `/collections/weekend` | Thư giãn | 8 |
| `/collections/occasion` | Thanh lịch | 13 |
| `/collections/statement` | Cá tính | 2 |

30 ID sản phẩm khác nhau, không lặp giữa các trang hoặc các bộ sưu tập. Sản phẩm
được liên kết theo trường `Product.style`, không sao chép bản ghi. Mỗi phong cách
chỉ có một `StoreCollection` nhờ ràng buộc unique trong PostgreSQL. Thay đổi
phong cách sản phẩm sẽ tự thay đổi bộ sưu tập chứa sản phẩm đó.

Sản phẩm công khai phải đang mở bán, có biến thể hoạt động và ảnh không rỗng.
Ẩn bộ sưu tập không ẩn sản phẩm tại cửa hàng; ẩn sản phẩm sẽ cập nhật số lượng
và danh sách của bộ sưu tập. Bộ sưu tập trống không xuất hiện ở danh sách công khai.
Ảnh bìa chỉ chọn từ sản phẩm công khai cùng phong cách; nếu sản phẩm đó bị ẩn,
API tự chọn một sản phẩm khác trong cùng nhóm. Không thêm ảnh minh họa thay thế.

Theo lựa chọn của chủ dự án, tiếp tục sử dụng danh mục PostgreSQL đã lọc ở đợt
22/10. Dữ liệu gốc có nguồn từ seed và DummyJSON/Fake Store; kết nối PostgreSQL
thật không tự xác nhận đây là hàng tồn thực tế, giá thương mại hoặc ảnh riêng của
chủ cửa hàng. Đợt này không nhập thêm hàng, bịa tồn kho hay đổi nguồn gốc ảnh.

Migration `20261023010000_collections` đã áp dụng cho `wearly` và `wearly_test`.
Bản sao đầy đủ trước migration được tạo bằng `pg_dump`, xác minh đọc được bằng
`pg_restore --list`, lưu riêng tại
`.tools/collections/before-1792688583975.private.dump` (ignored, có dữ liệu riêng tư).
Không reset DB; tài khoản, giao dịch, giá và số lượng tồn kho giữ nguyên.

`node tools/sync-store-collections.cjs` chỉ xem kế hoạch. `--apply` tạo metadata
còn thiếu dựa vào sản phẩm hiện có, ghi nhật ký và giữ nguyên mọi bộ sưu tập đã
chỉnh sửa. Chạy lại hiện trả `collections: []`, `preserved: 4`.

## Giao diện và quản trị

- Thẻ bộ sưu tập có ảnh, mô tả, số sản phẩm và nút khám phá; hai cột desktop,
  một cột điện thoại. Font, màu và khoảng cách dùng design system hiện có.
- Trang chi tiết có ảnh bìa, grid sản phẩm thật, 12 món/trang, sắp xếp tên/giá/
  mới nhất, lọc hàng còn sẵn, xem sản phẩm và chọn size nhanh.
- Số trang/lọc/sắp xếp nằm trong URL. Đổi bộ lọc về trang đầu; trang vượt giới
  hạn có đường quay lại. Có trạng thái đang tải, thử lại, rỗng và không tìm thấy.
- Quản trị tại `/#/admin/collections`: thêm/sửa tiêu đề, mô tả, phong cách,
  thứ tự, trạng thái và sản phẩm làm ảnh bìa. URL cố định sau khi tạo.
- ADMIN/MANAGER có quyền `content.manage`; khách hàng, kho và hỗ trợ không được
  truy cập API quản lý. Thay đổi lưu bền vững, ghi nhật ký trong cùng transaction.
- Phiên bản `expectedVersion` bảo vệ lưu đồng thời. Khi xung đột hoặc mất phản
  hồi ghi, form yêu cầu tải lại; không báo thành công hoặc tự gửi lặp.

Muốn tạo nhóm phong cách mới, trước hết gán phong cách đó cho sản phẩm có ảnh
và biến thể hoạt động trong trang quản lý sản phẩm, rồi tạo bộ sưu tập tương ứng.
Tên, ảnh, số lượng sản phẩm trên cửa hàng sẽ lấy từ dữ liệu vừa lưu.

## Kiểm chứng

- Flutter: **452 passed**, 2 bài tích hợp chọn chạy riêng được bỏ qua; analyze sạch.
- Backend: **228 E2E passed** trong 31 suite, gồm worker/storage trên DB `_test`;
  **88 unit passed** trong 21 suite; TypeScript và ESLint sạch.
- 8 E2E mới kiểm tra quyền, publication, ảnh bìa, dữ liệu rỗng/ẩn, phân trang,
  filter, chống trùng, rollback, phiên bản đồng thời và bảo toàn sản phẩm/kho.
- UI tests kiểm tra dữ liệu API, không có fallback demo, lỗi/thử lại/404,
  phân trang/lọc, sửa trên điện thoại và chặn lưu tiếp sau xung đột.
- `node tools/verify-store-catalog.cjs`: 30 sản phẩm, 30 ảnh bìa có SHA-256 riêng,
  48 ảnh giải mã được, 6 danh mục và 14 size thực tế trong DB.
- `node tools/verify-collections-browser.cjs`: Chrome thật trên cổng 8080,
  màn hình 1440/768/375 px, không chặn/thay response API. Kiểm tra index, chi
  tiết, trang 2, chọn size nhanh, URL bộ lọc, hồi phục trang rỗng và 404.
  15 ảnh chụp, không có lỗi Flutter/tràn bố cục/ảnh lỗi, lưu trong
  `.tools/collections-acceptance/` (ignored).

Bản build web release dùng API `http://localhost:3000/api/v1`. Dev server đang
chạy trên 8080 được biên dịch lại qua Flutter Tools, giữ nguyên tiến trình/cổng.
Tải lại trình duyệt để nhận giao diện mới.
