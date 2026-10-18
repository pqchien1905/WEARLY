# Wearly Design System

Nguồn chuẩn thiết kế. Dart tokens: `apps/storefront/lib/core/design/tokens.dart`.

## Color

| Token | HEX | Vai trò |
|---|---|---|
| canvas | #F7F8F7 | Nền lạnh |
| surface | #FFFFFF | Mặt nền form/ảnh |
| ink | #252329 | Chữ/CTA |
| muted | #67636A | Chữ phụ |
| line | #DFDCE0 | Phân cách |
| accent | #65394D | Mận, CTA chọn lọc |

Tints: accentSoft #ECE5E9, photo #E9EAE7. Semantic success #286047, danger #AD303B, warning #805A16; focus #65394D. Không dùng line làm màu chữ. Tính contrast bằng script QA và lưu kết quả; không tự nhận WCAG trước audit.

Audit 16/10/2026: 10 cặp text/background vượt 4.5:1 (`docs/qa/contrast.json`). Thêm `controlLine #8E8A91` cho biên input: 3.39:1 trên trắng. `line` chỉ dùng divider/border phụ. Tonal buttons dùng accentSoft, không lấy màu hồng tự sinh của Material. Không suy từ kiểm tra màu ra chứng nhận WCAG toàn sản phẩm.

## Type

Be Vietnam Pro 400/500/600/700 cho body, controls, giá. Manrope 400/500/600/700 cho display. Hai font có Vietnamese, đóng gói local + OFL. Mẫu: “Tủ đồ đương đại. Chọn sắc màu, vừa vặn với bạn.”

Hero display desktop thay đổi theo chiều rộng nội dung, giới hạn60–94px; mobile50px, line-height1.12. Các heading dùng Manrope28–52px theo cấp và breakpoint; body14/1.65; caption12/1.5. Không uppercase toàn bộ nhãn. Các đoạn dài và form có giới hạn chiều rộng riêng để dễ đọc.

## Layout

Khung trang và header mở rộng theo toàn bộ viewport, không giới hạn1440px (yêu cầu người dùng16/10/2026). Outer gutter56 desktop,32 tablet,20 mobile; header giữ gutter riêng48/12. Giới hạn chiều rộng đọc/form/modal nằm tại component tương ứng. Spacing4/8/12/16/24/32/48/64/80/112. Section gap80 desktop,48 mobile. Layout breakpoint600/1024; grid breakpoint phụ theo chiều rộng thực của nội dung. Grid4/3/2/1;320px có thể1 cột. Cards ảnh3:4, gallery4:5, hero theo khung campaign. Mobile không chồng chữ lên ảnh.

Radii:6 cho button/input/dialog/panel,16 ở hai góc trên bottom sheet,12 cho chat bubble, pill cho chip/swatches. Ảnh sản phẩm giữ góc vuông và không shadow. Header sticky không che focus; focus outline đủ nhìn. Touch target >=44, nút chính >=48.

Hero dùng ảnh contain trong khung nền photo để giữ phom trang phục ở1920px; chiều cao desktop600–760px, nội dung vẫn được phép tăng khi phóng chữ. Product gallery giữ tỉ lệ4:5 đến chiều cao tối đa820px, ảnh contain. Preview trang phục Try-On tối đa420px để lựa chọn size dễ tiếp cận. Checkout form tối đa760px, summary480px; thông tin sản phẩm600px, auth form480px. Footer phân bố ba cột theo chiều rộng desktop, xếp lại trên mobile. Bảng Admin mở rộng theo panel và cuộn ngang khi cần.

## Components / states

AppButton primary/outline/text/destructive, busy/disabled/focus. AppField label/required/error/help. ProductCard image/name/price/swatches/wishlist/quick select. SizeSelector selected/unavailable, không tự chọn size. QuantitySelector clamp inventory. Empty/Error có CTA khôi phục. Skeleton giữ geometry ảnh. Modal có close/Escape/focus traversal. Toast xác nhận kết quả; errors ở gần field. Status luôn có chữ, không chỉ màu.

## Photography

Campaign: phom dáng đầy đủ, ánh sáng tự nhiên, ít đạo cụ, màu trầm. Catalog ảnh 3:4, crop center, không crop mất trang phục chính. Demo ảnh minh họa rõ nguồn trong assets/ATTRIBUTION.md; không khẳng định là hàng bán thật. Không bịa ảnh detail vải từ ảnh toàn thân. Nếu thiếu góc chụp, cho phóng to ảnh hiện có thay vì gán góc giả.

## Motion / accessibility

Phản hồi tương tác 160–220ms; không autoplay, không entrance animation lặp. Giảm về 0 khi disableAnimations/accessibilityFeatures yêu cầu. Bàn phím Tab/Enter/Escape, semantics ảnh/giỏ/yêu thích, focus rõ, text scaling không cắt nội dung. Semantic status live regions cho job/error. Screen reader audit cần trình duyệt thực.

Motion tokens tại `lib/core/design/motion.dart`: easeOutCubic; route fade160ms, image hover/cart panel220ms. Product hover chỉ scale ảnh1.025 trong ClipRect, không dịch layout. Reduced motion: ảnh giữ scale1, route hiện đầy đủ ngay, cart bỏ transition, button theme bỏ tween. Focus ảnh/gallery có viền accent3px. Trang cũ không được giữ cùng trang mới trong route fade để tránh trùng GlobalKey/form. Không thêm animation khi cuộn hoặc shimmer liên tục.

## Writing

Tiếng Việt tự nhiên, CTA “Thêm vào giỏ”, “Xem bảng size”, “Thử đồ (bản demo)”. Demo AI: “Trải nghiệm mô phỏng – chưa kết nối AI”. Checkout: “Đơn hàng mô phỏng – chưa thanh toán thật”. Try-on result: “Ảnh minh họa giao diện – không phải kết quả AI thực tế”. Không rating giả, cam kết fit hoặc banner khuyến mãi không áp dụng.

## Quality gate

Xem ảnh Home/Catalog/Detail 375/768/1440 trước mở rộng. Kiểm tra crop, hierarchy, typography có dấu, CTA, consistency. Không thay palette cho trang khó; sửa component/token nếu nguyên nhân thuộc hệ thống.
