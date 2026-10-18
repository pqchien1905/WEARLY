# Báo cáo P0–P4 — Wearly

**Cập nhật sau review:** [Đợt hoàn thiện16/10/2026](refinement-2026-10-16.md) sửa lỗi catalog và bổ sung UX/routes. Các số liệu bên dưới là mốc nghiệm thu trước đợt này; không có nghĩa toàn bộ chi tiết Master Prompt hoặc nội dung ảnh thương mại đã hoàn tất.

Nghiệm thu frontend demo ngày 16/10/2026. Flutter Web + Dart; dữ liệu trong bộ nhớ. Không backend, database, xác thực, thanh toán hoặc AI thật. Đã đọc và áp dụng [frontend-design](../.agents/skills/frontend-design/SKILL.md) và [dev-flow](../.agents/skills/dev-flow/SKILL.md).

## P0 — Creative Direction & Design System

- So sánh **Tủ đồ đương đại** và **Urban Utility**. Chọn hướng đầu: ảnh thời trang làm trọng tâm, nhịp trắng thoáng, AI hỗ trợ việc mua sắm. Đổi thương hiệu thành Wearly theo yêu cầu sau đó.
- Xây dựng BRIEF, CONCEPTS, MASTER, DECISIONS, COMPONENTS và page rules trong `design-system/fashion-ai-commerce`; sitemap, kiến trúc Flutter/Riverpod/GoRouter.
- Tokens chung: nền trắng, plum accent, Manrope + Be Vietnam Pro, responsive grid, spacing, fields, buttons, cards, selectors và states. Component gallery: `/#/design-system`.
- Home, Catalog, Product Detail được dựng và kiểm tra trước khi mở rộng. Catalog mock:32 sản phẩm/256 SKU ban đầu; repository interfaces tách khỏi widget.
- Kiểm thử tại mốc:13/13 pass, release build thành công ([test](qa/p0-test.log), [build](qa/p0-build.log)). Sửa hero cao cố định và size row tràn màn hẹp.
- Ảnh cuối: [Home](qa/screenshots/home-1440.png), [Catalog](qa/screenshots/catalog-375.png), [Detail](qa/screenshots/product-375.png).
- Giới hạn: ảnh fixture có lặp, một ảnh nguồn/kiểu và zoom; chưa có ảnh riêng từng màu/góc.

## P1 — Storefront

- Hoàn thiện search/filter/sort/pagination/query URL, wishlist, chọn SKU, cart drawer/full page, checkout/shipping/validation/success và snapshot đơn hàng.
- Repository/controller commerce dùng chung; giá/tồn kho được kiểm tra lại khi checkout. Regression tests bảo vệ race khi đổi SKU và thay đổi giá. Mobile có lối tắt tới vùng chọn size/mua.
- Kiểm thử cuối: shopping/commerce/regression tests pass; Chrome thêm giỏ, checkout, wishlist, deep link và Back. [Checkout success](qa/screenshots/checkout-success-1440.png).
- Giới hạn: không payment gateway; refresh mất dữ liệu; phí ship/chính sách là demo.

## P2 — AI Experience

- Stylist nhận yêu cầu, ngân sách, size, phong cách, màu và trả sản phẩm catalog theo variant phù hợp; có pending/empty/error/timeout/retry.
- Try-On có chọn sản phẩm/size, file chooser JPEG/PNG, kiểm tra file/kích thước ảnh, consent, queued/processing/result/error/cancel. Xóa ảnh hoặc rời trang hủy tác vụ chờ và giải phóng tham chiếu/cache.
- Contracts/mock repositories độc lập. Result placeholder ghi rõ mô phỏng, không giả ảnh AI biến đổi.
- Kiểm thử cuối: AI/privacy/lifecycle tests pass; release Chrome chọn file thật, chạy và xóa ảnh. Đã sửa giải mã ảnh khác biệt trên Web; CanvasKit/font local, browser logs không có request ngoài origin.
- Ảnh: [Stylist](qa/screenshots/stylist-1440.png), [Stylist result](qa/screenshots/stylist-result-1440.png), [Try-On result](qa/screenshots/tryon-result-1440.png).
- Giới hạn: gợi ý deterministic, không LLM; không upload/inference/thử đồ thật.

## P3 — Account & Admin

- AccountRepository async; login/register/reset password mô phỏng, profile, đơn hàng, wishlist/logout; có pending/error/retry.
- Admin: dashboard từ dữ liệu phiên; CRUD sản phẩm/biến thể màu–size; kho/giá; đơn hàng/khách hàng; cấu hình khuyến mãi; bản nháp nội dung; activity monitoring; offline/reset demo.
- Catalog cập nhật phản ánh sang storefront, đơn giữ snapshot. Bảng tìm kiếm/phân trang/cuộn ngang mobile; sidebar cuộn được ở màn thấp.
- Kiểm thử cuối: admin/account tests pass;7 Chrome account checks. Sửa hủy đơn khi từ chối xác nhận hoặc rời trang, và phản hồi đăng nhập cũ sau reset/logout.
- Ảnh: [Dashboard](qa/screenshots/admin-dashboard-1440.png), [Products mobile](qa/screenshots/admin-products-375.png), [Profile](qa/screenshots/account-profile-375.png).
- Giới hạn: auth/RBAC không thật; hủy đơn chưa hoàn kho/tiền; content/promotions chưa publish hoặc áp vào checkout. UI ghi rõ.

## P4 — Visual Quality Audit & bàn giao

- Release preview: http://127.0.0.1:4173. Chụp7 routes ×4 widths (375/768/1024/1440):28 ảnh reference, cộng ảnh trạng thái tương tác.
- Chỉnh crop hero, wordmark mobile, search150% text, tonal button, contrast input, hit target announcement, skeleton và semantics header/sidebar.
- **123/123 Flutter tests pass**, gồm15 routes ×6 widths và regression tests. **Analyzer không có issues**, **release build thành công**. Logs: [test](qa/final-test.log), [analyze](qa/final-analyze.log), [build](qa/final-build.log).
- **22 browser checks pass**: [desktop9](qa/browser-flow.json), [mobile6](qa/browser-mobile.json), [account7](qa/browser-account.json). Không browser errors/external requests trong các lượt chạy này; [screenshot errors](qa/screenshots/browser-errors.json) rỗng.
- [Contrast](qa/contrast.json):10 cặp chữ đạt4.5:1; biên input3.39:1 đạt3:1. Đây là kiểm tra palette, không chứng nhận WCAG toàn ứng dụng.
- Bàn giao [README](../README_FRONTEND.md), [visual QA](visual-qa.md), [nghiệm thu](frontend-acceptance.md), [kiến trúc](frontend-architecture.md), [API contracts](api-contracts-frontend.md), [SEO](seo-strategy.md), [review](code-review.md), [asset attribution](../apps/storefront/assets/ATTRIBUTION.md).
- Trước production: cần ảnh từng SKU, adapters NestJS/dịch vụ thật, screen reader/thiết bị thật/cross-browser/performance và quyết định SEO. Workspace không có Git repository; không tạo commit/PR.
