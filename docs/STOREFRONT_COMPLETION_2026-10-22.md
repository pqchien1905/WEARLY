# Hoàn thiện cửa hàng PostgreSQL — 22/10/2026

Phạm vi được xác nhận: hoàn thiện chức năng hiện có; dùng danh mục PostgreSQL
hiện tại, lọc trùng và đủ ảnh. Đây không phải nhập một danh mục hàng kinh doanh
mới: nguồn ảnh/giá/tồn kho ban đầu vẫn được ghi tại
[manifest đợt nhập](data/wearly-demo-products-2026-10-22.json).

## Dữ liệu và API

- 85 sản phẩm đang mở bán → 30 sản phẩm. 26 bản lặp từ seed và 29 bản kiểm thử
  thiếu ảnh được chuyển `active=false`; không xóa sản phẩm hoặc quan hệ lịch sử.
- Đã đối chiếu 13 bảng được bảo vệ trong transaction: tài khoản, địa chỉ, đơn,
  thanh toán, hoàn tiền, kho, biến thể, ảnh và giỏ hàng giữ nguyên.
- 30 tên/slug/ID khác nhau, 30 ảnh bìa có SHA-256 khác nhau; 48 ảnh đọc/giải mã
  thành công. API có 6 danh mục, 14 size (gồm 36–44/Freesize), 4 phong cách.
- Public catalog và sitemap loại sản phẩm thiếu ảnh. Category/brand công khai
  chỉ gồm nhóm có sản phẩm xuất hiện trong cửa hàng; Admin vẫn đọc toàn bộ qua
  API riêng có phân trang, nên danh mục vừa tạo vẫn chọn được khi thêm hàng.
- `POST /api/v1/content/newsletter`: email + `consent:true`, chuẩn hóa email,
  giới hạn tần suất, lưu PostgreSQL. Gửi lại hoặc gửi đồng thời không tạo bản
  trùng; trả cùng xác nhận, không tiết lộ danh sách email. Chưa gửi marketing.
- Migration additive `20261022170000_newsletter` đã áp dụng cho development/test.
  Có pg_dump và bản sao sản phẩm/nội dung trước thao tác trong thư mục riêng
  `.tools/catalog-curation`; không chứa trong Git.

## Giao diện

- Khởi động/build mặc định dùng API. Dữ liệu mẫu cần `demo`/`build-demo` rõ ràng.
- Size/phong cách lấy từ API, bộ sưu tập lọc theo phong cách thay danh sách
  `nep-*` cố định. Trang chủ lấy sản phẩm và đường dẫn hiện có từ database.
- Giữ ảnh trọn vẹn trong thẻ sản phẩm; nút Freesize rộng đủ nhãn. Footer nhận
  tin lưu thật, có đồng ý, loading, lỗi và retry. Không giả lập thành công.
- Bỏ nhãn tồn kho/try-on/catalog demo trong giao diện API. Cập nhật phần giới
  thiệu mặc định, giữ thông tin cấu hình VNPay/vận chuyển trong điều khoản.
- Đăng nhập hỗ trợ autofill/Enter, giữ `next` khi chuyển đăng ký/đăng nhập;
  tiêu đề form phù hợp điện thoại. Admin và khách hàng tiếp tục tách riêng.

## Kiểm chứng

- Flutter analyze sạch; 443 kiểm thử đạt, 2 kiểm thử opt-in bỏ qua. Kiểm thử chỉ
  đọc `live_catalog_test.dart` chạy riêng với API hiện tại cũng đạt.
- Backend: 220 E2E với PostgreSQL/Redis/storage và 88 unit đạt; lint/TypeScript đạt.
- 53 kiểm thử công cụ đạt; build web release dùng API thật thành công.
- Chrome với database kiểm thử: đăng ký, địa chỉ, giỏ hàng, COD, hủy đơn và khôi phục
  phiên; Admin tạo danh mục/sản phẩm, upload/đổi ảnh bìa, chỉnh kho, xử lý đơn và
  xuất bản nội dung đều đạt. Fixture được dọn sau kiểm thử.
- Bản release với API development: 9 trang ở 375/768/1440px (27 lượt), không có
  lỗi JavaScript, overflow hay tải API/ảnh. Đã xem ảnh chụp trang chủ, cửa hàng,
  bộ sưu tập, chi tiết và khôi phục mật khẩu. Kết quả/ảnh tại `.tools/completion-final`.
- Regression mới cho danh mục thiếu ảnh, facet size giày, newsletter đồng thời,
  consent/retry, bộ sưu tập không phụ thuộc seed và danh mục riêng của Admin.
- Jest E2E xác định `*_test` **trước khi import AppModule**, từ chối database
  nghiệp vụ và cô lập SMTP thử nghiệm khỏi cấu hình Gmail.
- `node tools/verify-store-catalog.cjs` kiểm tra chỉ đọc toàn bộ trang, ảnh,
  chi tiết và bộ lọc trên API đang chạy. Kết quả lưu `.tools/catalog-curation`.

## Vận hành và giới hạn

Đợt kiểm tra tiếp theo phát hiện cổng 8080 vẫn đang phục vụ bản Flutter cũ.
Đã yêu cầu Flutter Tools đang chạy biên dịch lại qua dịch vụ debug của chính nó,
giữ nguyên process/cổng. Bản đang phục vụ đã được cập nhật; tải lại trình duyệt
để nhận mã mới. Không cần chạy thêm server hoặc nhấn `R` cho đợt cập nhật này.

Đã bổ sung tìm kiếm ngay trong cửa hàng, tìm tiếng Việt không dấu, thông báo
hết hàng/giá từ, trở về trang đầu khi trang cũ không còn dữ liệu, và chặn tạo/
đổi tên/mở bán lại sản phẩm trùng tên trong cùng thương hiệu. Sửa màn hình khôi
phục phiên để mở trực tiếp `/shop` hoặc trang riêng tư không phát sinh lỗi route.
`node tools/verify-shop-browser.cjs` kiểm tra trực tiếp server 8080 (không thay thế
API/asset): phân trang, tìm kiếm, lọc size, chọn nhanh ở 1440/768/375px. Ảnh và
kết quả lưu tại `.tools/shop-acceptance`.

Chạy `./tools/frontend.ps1 api`. Với những lần sửa mã sau, nếu Flutter dev server đang chạy, nhấn `R`
trong terminal đó để nạp mã mới; không chạy thêm server thứ hai trên 8080.
`node tools/curate-store-catalog.cjs` xem kế hoạch, `--apply` áp dụng có bản sao
và transaction; chạy lại sau đợt này không đổi dữ liệu.

Gmail khôi phục đã cấu hình ở đợt trước. Gemini cần khóa hoạt động; VNPay
đang bị phía merchant từ chối và chưa bật; vận chuyển chưa kết nối hãng thật.
Các kết quả ở đây không chứng nhận thanh toán/giao hàng bên ngoài hoặc production.
