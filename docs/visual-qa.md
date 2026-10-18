# Visual QA — Wearly

**Đợt cập nhật mới:** xem [refinement16/10/2026](refinement-2026-10-16.md). Gallery hỗ trợ metadata nhiều ảnh/màu, filter mobile có draft/Apply, Admin mobile dùng cards; ảnh reference được chụp lại sau thay đổi. Nhận xét về giới hạn tài sản ảnh và kiểm thử thiết bị dưới đây vẫn áp dụng.

Ngày16/10/2026, release Flutter Web trên Chrome Windows tại localhost:4173. Áp dụng **Tủ đồ đương đại** từ [Design System](../design-system/fashion-ai-commerce/MASTER.md). Đây là tự đánh giá demo, không phải chứng nhận accessibility hoặc nghiên cứu người dùng.

## Phương pháp

Chụp7 routes (Home, Catalog, Detail, Stylist, Try-On, Admin, Admin products) tại375/768/1024/1440px: **28 ảnh**. Rà trực quan ảnh đại diện desktop/mobile và trạng thái checkout/AI/account. Widget tests kiểm tra overflow trên15 routes ×6 widths từ320 đến1920px;150% text tại375px trên5 routes và search dialog.

Browser desktop/mobile/account: **22 checks pass**, không exception hoặc request ngoài origin. Kết quả không đại diện mọi tổ hợp nội dung/viewport. Screenshot lấy từ release Chrome, không phải mockup dựng riêng.

## Tự đánh giá

Thang5:3 = dùng được nhưng cần chỉnh;4 = nhất quán, đã kiểm tra trong demo;5 = xác nhận sâu với nội dung/điều kiện thực tế. Không chấm5 khi chưa có bằng chứng.

| Tiêu chí | Điểm | Nhận xét |
|---|---:|---|
| Bản sắc |4| Plum gắn với trang phục hero, wordmark và nhịp trắng; storefront không dùng gradient/KPI trang trí |
| Phân cấp |4| Headline/CTA rõ; trang giao dịch ưu tiên dữ liệu/summary |
| Typography |4| Manrope + Be Vietnam Pro local; tiếng Việt đúng; search150% đã kiểm tra |
| Màu / contrast |4|10 cặp chữ≥4.5:1; biên input3.39:1 |
| Grid / spacing |4| Catalog2 cột mobile/sidebar desktop; form theo tokens |
| Ảnh |3| Hero giữ đầu người mẫu; fixture còn lặp, chưa có ảnh riêng màu/góc |
| Components |4| Buttons/fields/cards/states chung; tonal colors theo palette |
| Mua hàng |4| SKU/giá/kho xuyên suốt, error/summary rõ, browser checkout pass |
| AI / feedback |4| Consent/pending/error/retry và nhãn mô phỏng rõ |
| Responsive / accessibility baseline |4| Viewport/text150%/semantics/keyboard; chưa screen reader/thiết bị thật |

## Các chỉnh sửa qua audit

| Phát hiện | Chỉnh sửa / kiểm chứng |
|---|---|
| Hero cao cố định, size row tràn mobile | Layout thích ứng/wrap; widget tests + ảnh375 |
| Wordmark rộng sau đổi tên | Giới hạn width/scaleDown;320px tests |
| Crop hero cắt đầu | topCenter; ảnh1440 |
| Search heading tràn150% text | Heading co giãn trong Row; regression test |
| Input border quá nhạt | controlLine riêng; contrast.json |
| Tonal button lệch palette | secondaryContainer/onSecondaryContainer dùng tokens |
| Nút đóng announcement nhỏ | Vùng bấm44×44 |
| Header/sidebar bị che trong semantics của Navigator | Semantics container; Chrome roles/menu/search |
| Admin menu không cuộn ở màn thấp | Expanded ListView; mobile640px flow |
| Loading nhiều spinner | Skeleton tĩnh dùng chung |
| Account thiếu async feedback | Pending/error/retry và generation guards; tests + Chrome |
| Hủy đơn hiển thị trạng thái mới dù từ chối | Dropdown controlled/mounted guard; regression tests |

## Ảnh review

| Màn hình | Desktop | Mobile |
|---|---|---|
| Home |[1440](qa/screenshots/home-1440.png)|[375](qa/screenshots/home-375.png)|
| Catalog |[1440](qa/screenshots/catalog-1440.png)|[375](qa/screenshots/catalog-375.png)|
| Detail |[1440](qa/screenshots/product-1440.png)|[375](qa/screenshots/product-375.png)|
| Stylist |[1440](qa/screenshots/stylist-1440.png)|[375](qa/screenshots/stylist-375.png)|
| Try-On |[1440](qa/screenshots/tryon-1440.png)|[375](qa/screenshots/tryon-375.png)|
| Admin |[1440](qa/screenshots/admin-1440.png)|[375](qa/screenshots/admin-375.png)|
| Admin products |[1440](qa/screenshots/admin-products-1440.png)|[375](qa/screenshots/admin-products-375.png)|

Trạng thái: [checkout success](qa/screenshots/checkout-success-1440.png), [Stylist result](qa/screenshots/stylist-result-1440.png), [Try-On result](qa/screenshots/tryon-result-1440.png), [account error](qa/screenshots/account-error-375.png), [profile](qa/screenshots/account-profile-375.png), [mobile filter](qa/screenshots/catalog-filtered-375.png).

## Giới hạn

Điểm yếu trực quan lớn nhất là bộ ảnh: nhiều edition chung ảnh, chọn màu chưa thay ảnh thực. Cần bộ ảnh thương hiệu cùng ánh sáng/tỷ lệ và ảnh riêng từng màu/góc trước mở bán. Gallery hiện chỉ zoom ảnh đang có, không dựng thumbnail giả.

Bảng Admin cuộn ngang dùng được trên mobile nhưng tốn thao tác; giữ vì cần so sánh nhiều cột. Nếu mobile trở thành kênh quản trị chính, cần nghiên cứu card view theo tác vụ với người dùng.

Chưa kiểm tra NVDA/VoiceOver, Safari/Firefox, thiết bị thật, Core Web Vitals hoặc memory dài hạn. Palette/semantics không thay thế audit WCAG. Xem [nghiệm thu](frontend-acceptance.md) và [SEO](seo-strategy.md) để phân biệt demo hoàn thành với công việc production.
