# Wearly — hoàn thiện giao diện và chuyển động

## Đã triển khai

Giữ nhận diện Wearly, Flutter Web/Dart, font/ảnh local và giao diện toàn chiều rộng. Áp dụng skill `frontend-design` trong workspace; tiếp tục hướng thời trang tối giản với màu mận, khoảng trắng và typography rõ cấp bậc.

- **Home:** hero display60–94px desktop; ảnh contain giữ phom trang phục; section AI giới hạn ảnh/nội dung; action căn cuối hàng tiêu đề; câu chuyện bộ sưu tập hai cột desktop, một cột mobile.
- **Catalog/Detail:** lưới tối đa4 cột theo chiều rộng thực; hover ảnh trong khung; gallery contain tối đa820px; thông tin sản phẩm600px; focus có viền rõ và hỗ trợ bàn phím.
- **Shell:** menu thể hiện trang hiện tại, selected semantics; footer phân bố theo chiều ngang; giữ header/trang toàn viewport.
- **Cart/Checkout:** drawer trượt/fade220ms; summary có biên nhẹ; nhóm form/summary checkout tối đa1320px để không cách quá xa ở1920px. Đây là giới hạn đọc tại checkout, không giới hạn toàn website.
- **Account:** panel ảnh/nội dung riêng trên desktop; form480px và một cột trên mobile.
- **AI/Admin:** dùng chung theme input/button/table; preview Try-On tối đa420px giúp tiếp cận chọn size; checkbox đồng ý nằm cạnh nội dung; bảng sản phẩm/kho/biến thể Admin phủ hết panel, giữ cuộn ngang.
- **Motion:** tokens160/220ms, easeOutCubic; route fade hữu hạn, không giữ hai route cùng lúc; hover scale1.025 không dịch layout. Reduced motion bỏ zoom, tween nút, transition drawer và hiển thị route ngay. Không thêm animation chạy nền hay shimmer liên tục.

Không thêm dependencies, API, database, thanh toán hoặc AI thật.

## Kiểm chứng

- **151/151 Flutter tests**, gồm4 test mới về reduced motion, ngắt animation, hover liên tục không dịch khung và kích hoạt bằng bàn phím. Suite hiện có kiểm tra responsive320–1920px và150% text scaling.
- Analyzer không có issues; release web build dùng CanvasKit/font local thành công.
- **44 Chrome checks** trong5 scripts: `browser-flow`, `browser-mobile`, `browser-account`, `browser-refinement`, `browser-polish`. Báo cáo không có browser errors/external requests.
- **52 ảnh reference**:13 route ×375/768/1440/1920px, prefix `polish-`; thêm ảnh populated cart/checkout, mobile summary, drawer và footer. Log `docs/qa/polish-{test,analyze,build}.log`, browser reports `docs/qa/browser-*.json`.
- 11 cặp màu đạt ngưỡng được đo: 10 cặp chữ ≥4.5:1, biên control 3.39:1. Không coi đây là chứng nhận WCAG toàn bộ sản phẩm.
- Review độc lập source và ảnh không phát hiện lỗi chặn; follow-up kiểm tra gallery focus, section alignment, TableViewport và Try-On preview cũng không có finding.

Một test FAQ từng đọc semantics trước khi expansion cập nhật. Snapshot và ảnh xác nhận câu trả lời hiển thị đúng; assertion đã chuyển sang chờ kết quả tối đa3s, vẫn kiểm tra nội dung kỳ vọng.

## Ảnh tiêu biểu

- [Home1920](qa/screenshots/polish-home-1920.png)
- [Catalog1920](qa/screenshots/polish-catalog-1920.png)
- [Product1440](qa/screenshots/polish-product-1440.png)
- [Account1440](qa/screenshots/polish-login-1440.png)
- [Try-On1920](qa/screenshots/polish-tryon-1920.png)
- [Admin1440](qa/screenshots/polish-admin-products-1440.png)
- [Checkout1920](qa/screenshots/polish-checkout-1920.png)
- [Checkout mobile](qa/screenshots/polish-checkout-summary-375.png)
- [Footer1920](qa/screenshots/polish-footer-1920.png)

## Giới hạn

Catalog vẫn dùng7 ảnh minh họa lặp trong fixture32 sản phẩm, chưa đủ ảnh riêng cho mỗi màu/góc. Mock repositories giữ dữ liệu trong phiên; auth/payment/AI chưa thật. Chưa benchmark frame-time trên thiết bị yếu, kiểm thử Safari/iOS hay screen reader toàn luồng. Không khẳng định production-ready từ kết quả Chrome/widget tests.

Preview: http://127.0.0.1:4173. Nếu server đã tắt, chạy `tools/frontend.ps1 preview` theo README.
