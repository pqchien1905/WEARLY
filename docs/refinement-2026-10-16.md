# Wearly — đợt hoàn thiện sau review

Phạm vi được người dùng đồng ý: sửa lỗi catalog, giảm thao tác mobile, cải thiện gallery/Try-On/Admin và bổ sung trang hỗ trợ. Giữ Flutter Web, Design System và mock repositories. Không triển khai backend hoặc dịch vụ thật.

## Đã thay đổi

- **Giá không giới hạn đúng nghĩa:** `ProductQuery.maxPrice` nullable; thiếu `max` không đặt trần. Query giá cụ thể trên3 triệu được giữ nguyên, sản phẩm giá cao không mất khỏi catalog mặc định.
- **Màu từ dữ liệu:** `ProductRepository.availableColors()` lấy màu từ toàn bộ sản phẩm active, không phụ thuộc trang phân trang đang xem. Cập nhật Admin làm mới facets. Màu đang lọc vẫn có thể bỏ ngay cả khi dữ liệu đã đổi.
- **Mobile filter:** chọn nhiều điều kiện trong draft, Apply cập nhật URL một lần/reset page; đóng sheet bỏ draft. Mức giá dùng radio và ngôn ngữ “Đến” đúng với phép so sánh bao gồm giá biên.
- **Quick add:** dấu cộng trên product card mở sheet chọn màu/size; tải giá/kho mới từ repository, thêm SKU qua commerce controller và mở giỏ. Có pending/error/size hết hàng. Không rời catalog.
- **Gallery:** `ProductMedia(path,label,color)`, ảnh theo màu khi có, thumbnails, phím trái/phải, zoom/lightbox; reset ảnh khi đổi màu. Thiếu ảnh đúng màu có thông báo ngay cạnh ảnh. Admin giữ media khi sửa nội dung/giá và không đổi ảnh nguồn.
- **Try-On mobile:** thumbnail trang phục nhỏ, chỉ rõ bước hiện tại, vùng chọn ảnh gần hơn. Tạo kết quả có route riêng; chỉ giữ job/slug/SKU trong RAM (tối đa20 kết quả), không ảnh hoặc tên file. Xóa/reset/refresh làm kết quả mất; đường dẫn không tồn tại có hướng dẫn bắt đầu lại.
- **Try-On race:** không cho chạy/retry khi đang đọc ảnh thay thế; generation guard loại callback cũ, hủy tác vụ khi clear/cancel/dispose. Có test picker đọc chậm tái hiện lỗi trước khi sửa.
- **Trang mới:** Contact có validation và success mô phỏng, không gửi email; FAQ; collection index và3 collection detail theo phong cách; unknown slug có fallback. Footer dẫn tới Contact/FAQ.
- **Admin mobile:** products/inventory dưới700px dùng card có giá, kho, edit/delete/điều chỉnh ngay trong chiều rộng màn hình. Desktop giữ bảng và phân trang.
- **Nhiều màu:** product card preview tối đa3 swatches, hiển thị tổng số màu, tự wrap để không tràn cột mobile khi Admin thêm nhiều biến thể.

## Route bổ sung

`/contact`, `/faq`, `/collections/everyday`, `/collections/weekend`, `/collections/occasion`, `/virtual-try-on/:jobId`.

Collection detail chọn4 sản phẩm active được biên tập theo slug, tránh lặp cùng ảnh do nhiều edition; CTA cuối dẫn tới catalog có bộ lọc phong cách tương ứng. Danh sách biên tập hiện là fixture, cần chuyển thành collection DTO khi nối API. Kết quả Try-On chỉ mở lại được trong tab hiện tại, không phải đường dẫn chia sẻ bền vững.

## Kiểm chứng

**Bản cuối:**147/147 Flutter tests, analyzer sạch, release build thành công. **33 Chrome checks** đạt (desktop9 + mobile6 + account7 + refinement11), không browser errors hoặc external requests. Có48 ảnh reference (12 màn hình ×4 widths), cộng ảnh trạng thái sheet/filter/result. Preview được cập nhật tại http://127.0.0.1:4173.

147 Flutter tests pass trong `qa/refinement-test.log`; analyzer sạch trong `qa/refinement-analyze.log`. Regression red/green: `refinement-red.log`, `quick-add-red.log`, `media-red.log`, `admin-mobile-red.log`, `refinement-review-red.log`, `tryon-replacement-red.log` và các log green liên quan. Bản build/browser được ghi trong `qa/refinement-build.log`, `qa/browser-refinement.json` cùng các browser suites cũ.

Reviewer độc lập phát hiện race khi đổi ảnh; đã sửa bằng test đọc ảnh chậm. Rà soát cũng dẫn đến kiểm thử và sửa overflow8 màu. Gallery keyboard, result delete và12 kiểm tra route mới ở375/1440 với cỡ chữ150% đã chạy.

Visual review tiếp tục chỉnh nền bottom sheet/dialog về trắng theo Design System và bỏ ảnh edition lặp trong collection detail. Quick-add screenshot chờ transition hoàn tất trước khi chụp, tránh nhầm màu trung gian với trạng thái cuối.

Ảnh mới: [filter draft](qa/screenshots/filter-draft-375.png), [quick add](qa/screenshots/quick-add-375.png), [Admin mobile](qa/screenshots/admin-products-375.png), [Try-On mobile](qa/screenshots/tryon-375.png), [collection desktop](qa/screenshots/collection-detail-1440.png), [Contact](qa/screenshots/contact-1440.png), [Try-On result route](qa/screenshots/tryon-session-result-375.png).

## Phần vẫn cần tài sản / dịch vụ thật

**Chưa có bộ ảnh mới cho mọi biến thể/góc chụp.** Bộ ảnh gốc vẫn chỉ có7 ảnh và có lặp theo edition; gallery đã hỗ trợ nhiều ảnh nhưng không dựng góc chụp hay màu giả từ ảnh khác. Cần bổ sung ảnh đúng từng sản phẩm để hoàn thành tiêu chí nội dung thương mại. Đây là giới hạn tài sản còn tồn tại, không đánh dấu đã giải quyết.

Promotions/content vẫn là cấu hình/bản nháp; không áp dụng storefront/checkout. Auth, AI, payment, giao hàng và dữ liệu bền vững chưa triển khai. Screen reader, Safari/Firefox, thiết bị thật và performance dài hạn vẫn chưa kiểm thử. Không coi bản demo là đáp ứng100% Master Prompt hoặc sẵn sàng mở bán.
