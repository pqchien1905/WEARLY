# Component contracts

| Component | Nội dung / tương tác | States |
|---|---|---|
| StoreShell | announcement, header, search, drawer, footer | wide/compact, cart count, active nav/selected semantics |
| AppButton | label + optional icon + callback | primary/outline, disabled, loading, focus |
| AppField | label, controller, validator | empty/filled/error |
| ProductCard | Product, favorite toggle, open, select variant | normal, saved, missing image; bounded hover zoom + keyboard focus |
| ProductGrid | collection + adaptive columns | loading/error/empty/data |
| SizeSelector | values, selected, availability | unselected/selected/sold out |
| QuantitySelector | value/min/max callbacks | limits disabled |
| ProductGallery | ProductMedia theo màu, thumbnails, keyboard, zoom/lightbox | loaded/fallback, thông báo thiếu ảnh màu; asset nhiều góc còn thiếu |
| QuickAddSheet | chọn màu/size, giá/kho mới, thêm qua commerce | loading/error/pending/sold out/success |
| CatalogFilterSheet | draft nhiều điều kiện, Apply một lần, đóng để bỏ | draft/applied/cancelled, facets loading/error |
| CartSummary | subtotal/shipping/total | empty/ready |
| StatePanel | title, message, action | empty/error |
| LoadingPanel | skeleton ảnh + hai dòng chữ, semantics thông báo tải | loading, không shimmer tự động |
| DemoNotice | disclosure | informational |
| TryOnStatus | typed job status, cancel/retry | queued/processing/succeeded/failed/cancelled |
| AdminShell | nav + content + session marker | desktop sidebar/mobile menu |
| TableViewport | shared table width and horizontal scroll | fills wide panel, retains narrow-screen access |
| InteractivePhoto | InkWell keyboard/click + clipped image motion | normal/hover/focus/reduced motion |
| PageReveal | finite route-content fade, no outgoing route retained | entrance/interrupted/reduced motion |

Internal gallery `/design-system` exposes real components, keyboard focus and state specimens. Product, AI and admin share tokens and controls; no per-page hex palette.

Visual polish16/10/2026: controls use6px radius,160ms state transitions, readable disabled styling and explicit focus. Table headers use canvas/muted typography. Cart panel enters from the right over220ms; CartSummary uses canvas, subtle border and shared radius. Auth desktop has an editorial image panel; form remains max480px and becomes a single column below950px available width.

Admin product/inventory dưới700px dùng cards với giá/kho/thao tác trực tiếp; màn rộng dùng bảng, phân trang và tìm kiếm. Dropdown trạng thái đơn là controlled input: từ chối xác nhận hoặc rời trang không đổi trạng thái. Account forms dùng cùng AppField/AppButton/DemoNotice, có pending/error/retry qua AccountRepository. Try-On mobile có tóm tắt trang phục và bước hiện tại; result route chỉ giữ metadata phiên, không ảnh cá nhân.
