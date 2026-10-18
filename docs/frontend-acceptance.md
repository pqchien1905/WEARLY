# Nghiệm thu frontend Wearly

**Cập nhật16/10/2026:**174 tests pass, analyzer sạch, release build thành công;59 Chrome checks. Đã bổ sung sổ địa chỉ dùng ở checkout, hồ sơ phong cách, order search/status/progress, lịch sử thử đồ và CTA sản phẩm→Stylist. Xem [báo cáo mới](account-journeys-2026-10-16.md) và [visual polish](visual-polish-2026-10-16.md). Bộ ảnh sản phẩm thật còn thiếu; không coi mọi hạng mục Master Prompt đã hoàn tất.

Phạm vi: **bản trình diễn Flutter Web có tương tác**, dữ liệu trong bộ nhớ, không backend/AI/thanh toán thật. Ngày kiểm tra: 16/10/2026. Pass dưới đây chỉ áp dụng phạm vi demo; không phải chứng nhận production.

## Kết quả và chứng cứ

| Tiêu chí | Trạng thái | Chứng cứ / giới hạn |
|---|---|---|
| Flutter Web + Dart, không thay stack | Pass | `apps/storefront`, release build log |
| Đọc và áp dụng frontend-design | Pass | BRIEF, CONCEPTS, MASTER, DECISIONS, COMPONENTS; skill trong `.agents/skills/frontend-design` |
| So sánh hai concept trước triển khai | Pass | Tủ đồ đương đại / Urban Utility; chọn concept A, đổi tên Wearly theo yêu cầu |
| Home/Catalog/Detail làm chuẩn trước mở rộng | Pass | Báo cáo P0 và ảnh reference; tokens dùng chung |
| Palette/type/grid/CTA nhất quán | Pass | Visual QA desktop/mobile, Manrope + Be Vietnam Pro local |
| 32 sản phẩm, SKU/giá/tồn kho đồng nhất | Pass | Fixture 256 SKU ban đầu; catalog, commerce và regression tests |
| Tìm kiếm/lọc/sort/pagination/query URL | Pass | Repository tests, Chrome search/filter/back/deep-link |
| Wishlist, chọn màu/size, size hết hàng | Pass | Widget + Chrome flow; chưa có ảnh riêng từng màu |
| Cart drawer/full page/quantity/remove | Pass | Cùng commerce controller; stock cap, async SKU race regression |
| Checkout validation/shipping/summary/success | Pass | Desktop/mobile shopping tests; snapshot và giá được kiểm tra lại |
| Giá hoặc kho đổi khi checkout | Pass | Regression tests; atomic trong một mock isolate, không phải transaction server |
| Account login/register/reset/profile/logout | Pass | AccountRepository, async UI, validation, password visibility; không xác thực thật |
| Reset/logout không khôi phục profile cũ | Pass | In-flight generation regression tests |
| Stylist dùng đúng catalog/budget/size/color | Pass | Deterministic mock, selected-variant price tests |
| Stylist pending/empty/error/timeout/retry | Pass | Repository scenarios, UI error/retry; nhãn mô phỏng |
| Try-On chọn file thật và consent | Pass | Release Chrome file chooser, JPEG/PNG/size validation |
| Try-On lifecycle/cancel/retry/error | Pass | Repository lifecycle tests, UI retry state, Chrome success flow |
| Xóa/rời trang giải phóng ảnh | Pass | Cache eviction test, cancellation guard, Chrome delete flow |
| Demo không gửi ảnh cá nhân ra mạng | Pass | Browser request logs: không có external requests hoặc API upload |
| Admin sản phẩm/biến thể/kho | Pass | CRUD, preview, add/remove size-color, paging/search; storefront đồng bộ |
| Admin đơn hàng/khách hàng | Pass | Dữ liệu từ checkout trong phiên; giữ trạng thái khi từ chối/rời confirmation |
| Admin promotions/content/monitoring | Pass trong phạm vi mock | CRUD cấu hình và bản nháp, activity status; chưa áp promotion hoặc publish content |
| Responsive320–1920 | Pass trong ma trận đã test | 15 routes ×6 widths; 375/768/1024/1440 screenshots; không suy ra mọi tổ hợp nội dung |
| Cỡ chữ lớn | Pass trong phạm vi đã test | 150% tại375px: Home, Shop, Detail, Stylist, Login và search dialog |
| Tương phản chữ và biên input | Pass | 10 cặp chữ≥4.5; control border3.39; contrast.json |
| Nhãn truy cập/menu/bàn phím | Pass baseline | Chrome roles, keyboard Enter/Escape, semantics header/sidebar fix |
| NVDA/VoiceOver, WCAG toàn sản phẩm | Not tested | Chưa thực hiện audit bằng người dùng screen reader |
| Safari/Firefox/thiết bị thật | Not tested | Chrome Windows/headless và widget viewport tests |
| Mạng chậm/Core Web Vitals/memory dài hạn | Not tested | Không dùng latency mock như benchmark |
| Nhiều góc ảnh/SKU có ảnh đúng màu | Chưa có asset | Một ảnh thật/kiểu + zoom; không giả ảnh detail hoặc trước/sau |
| Ảnh và fonts có nguồn | Pass cho demo | assets/ATTRIBUTION.md, fonts/OFL; thay bộ ảnh thương hiệu trước mở bán |
| HTTP DTO adapters và API thật | Ngoài phạm vi | Contracts đã viết; remote adapters chưa triển khai |
| Auth/RBAC/payment/AI/storage thật | Ngoài phạm vi | Không API key; không tuyên bố hoạt động production |
| SEO ecommerce riêng từng sản phẩm | Chưa triển khai | Hash routes và noindex demo; quyết định tiếp theo trong seo-strategy.md |

## Các giới hạn đã chốt

1. Refresh xóa giỏ hàng, profile, đơn, wishlist và sửa catalog. Admin có reset; không có lưu bền.
2. Gallery chỉ có ảnh nguồn hiện có; fixtures lặp ảnh theo edition. Không review/rating giả. Try-On dùng result placeholder, không tạo ảnh biến đổi.
3. Admin hủy đơn chỉ đổi trạng thái demo, chưa hoàn kho/hoàn tiền. Quy tắc chuyển trạng thái thật thuộc backend.
4. Content/promotions là bản nháp/cấu hình, không làm thay đổi storefront/checkout. UI ghi rõ ranh giới này.
5. Catalog, cart, order, account, Stylist, Try-On có interfaces. Content/promotions cần adapter; media đa ảnh, địa chỉ cấu trúc và lỗi typed cần bổ sung khi nối API, đã mô tả contracts.

## Lệnh tái kiểm tra

`tools/frontend.ps1 check`, `tools/frontend.ps1 build`, rồi chạy `browser-flow.cjs`, `browser-mobile.cjs`, `browser-account.cjs`, `screenshots.cjs`, `contrast.cjs` với preview ở4173. Logs mới nhất: `qa/final-analyze.log`, `qa/final-test.log`, `qa/final-build.log`, các `qa/browser-*.json`. Xem [báo cáo milestone](milestones.md) và [visual QA](visual-qa.md).
