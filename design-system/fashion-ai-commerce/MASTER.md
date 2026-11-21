# Wearly Design System

Nguồn chuẩn thiết kế. Dart tokens: `frontend/lib/core/design/tokens.dart`.

## Color

| Token | HEX | Vai trò |
|---|---|---|
| canvas | #F8F6F8 | Nền lạnh |
| surface | #FFFFFF | Mặt nền form/ảnh |
| ink | #29232A | Chữ chính |
| muted | #706670 | Chữ phụ |
| line | #E3DDE2 | Phân cách |
| accent | #65394D | Mận, hành động chính |

Tints: accentSoft #F1E9EE, photo #F0EEF0. Semantic success #286047, danger #AD303B, warning #805A16; focus #65394D. Không dùng line làm màu chữ. Tính contrast bằng script QA và lưu kết quả; không tự nhận WCAG trước audit.

Audit 16/10/2026: 10 cặp text/background vượt 4.5:1 (`docs/qa/contrast.json`). Thêm `controlLine #8E8A91` cho biên input: 3.39:1 trên trắng. `line` chỉ dùng divider/border phụ. Tonal buttons dùng accentSoft, không lấy màu hồng tự sinh của Material. Không suy từ kiểm tra màu ra chứng nhận WCAG toàn sản phẩm.

Audit palette mới 09/11/2026: 12 cặp token đạt ngưỡng tương ứng trong
`docs/qa/ui-refinement-contrast.json`; chữ phụ trên nền canvas5.11:1, chữ trắng
trên nút mận9.35:1. Đây là kiểm tra token màu, không phải chứng nhận toàn bộ UI.

## Type

Be Vietnam Pro 400/500/600/700 cho body, controls, giá. Manrope 400/500/600/700 cho display. Hai font có Vietnamese, đóng gói local + OFL. Mẫu: “Tủ đồ đương đại. Chọn sắc màu, vừa vặn với bạn.”

Hero display desktop thay đổi theo chiều rộng nội dung, giới hạn52–80px; mobile46px, line-height1.18. Các heading dùng Manrope28–52px theo cấp và breakpoint; body14/1.65; caption12/1.5. Không uppercase toàn bộ nhãn. Các đoạn dài và form có giới hạn chiều rộng riêng để dễ đọc.

## Layout

Khung trang và header mở rộng theo toàn bộ viewport, không giới hạn1440px (yêu cầu người dùng16/10/2026). Outer gutter56 desktop,32 tablet,20 mobile; header giữ gutter riêng48/12. Giới hạn chiều rộng đọc/form/modal nằm tại component tương ứng. Spacing4/8/12/16/24/32/48/64/80/112. Section gap80 desktop,48 mobile. Layout breakpoint600/1024; grid breakpoint phụ theo chiều rộng thực của nội dung. Grid4/3/2/1;320px có thể1 cột. Cards ảnh3:4, gallery4:5, hero theo khung campaign. Mobile không chồng chữ lên ảnh.

Radii:10 cho button/input,12 cho ảnh,16 cho panel,24 cho hero/dialog và hai góc trên bottom sheet, pill cho chip/swatches. Ảnh sản phẩm không shadow. Header sticky không che focus; focus outline đủ nhìn. Touch target >=44, nút chính >=48.

Hero dùng ảnh contain trong khung nền photo để giữ phom trang phục ở1920px; chiều cao desktop560–700px, nội dung vẫn được phép tăng khi phóng chữ. Product gallery giữ tỉ lệ4:5 đến chiều cao tối đa820px, ảnh contain. Preview trang phục Try-On tối đa420px để lựa chọn size dễ tiếp cận. Checkout form tối đa760px, summary480px; thông tin sản phẩm600px, auth form480px. Footer phân bố ba cột theo chiều rộng desktop, xếp lại trên mobile. Bảng Admin mở rộng theo panel và cuộn ngang khi cần.

## Components / states

AppButton primary/outline/text/destructive, busy/disabled/focus. AppField label/required/error/help. ProductCard image/name/price/swatches/wishlist/quick select. SizeSelector selected/unavailable, không tự chọn size. QuantitySelector clamp inventory. Empty/Error có CTA khôi phục. Skeleton giữ geometry ảnh. Modal có close/Escape/focus traversal. Toast xác nhận kết quả; errors ở gần field. Status luôn có chữ, không chỉ màu.

## Photography

Campaign: phom dáng đầy đủ, ánh sáng tự nhiên, ít đạo cụ, màu trầm. Catalog ảnh 3:4, crop center, không crop mất trang phục chính. Demo ảnh minh họa rõ nguồn trong assets/ATTRIBUTION.md; không khẳng định là hàng bán thật. Không bịa ảnh detail vải từ ảnh toàn thân. Nếu thiếu góc chụp, cho phóng to ảnh hiện có thay vì gán góc giả.

## Motion / accessibility

Phản hồi tương tác 160–240ms; không autoplay, không entrance animation lặp. Giảm về 0 khi disableAnimations/accessibilityFeatures yêu cầu. Bàn phím Tab/Enter/Escape, semantics ảnh/giỏ/yêu thích, focus rõ, text scaling không cắt nội dung. Semantic status live regions cho job/error. Screen reader audit cần trình duyệt thực.

Motion tokens tại `lib/core/design/motion.dart`: easeOutCubic; route fade160ms, image hover320ms, gallery/cart panel240ms. Product hover chỉ scale ảnh1.035 trong khung bo12px, không dịch layout. Reduced motion: ảnh giữ scale1, route hiện đầy đủ ngay, cart bỏ transition, button theme bỏ tween. Focus ảnh/gallery có viền accent3px. Trang cũ không được giữ cùng trang mới trong route fade để tránh trùng GlobalKey/form. Không thêm animation khi cuộn hoặc shimmer liên tục.

## Writing

Tiếng Việt tự nhiên, CTA “Thêm vào giỏ”, “Xem bảng size”, “Thử đồ (bản demo)”. Demo AI: “Trải nghiệm mô phỏng – chưa kết nối AI”. Checkout: “Đơn hàng mô phỏng – chưa thanh toán thật”. Try-on result: “Ảnh minh họa giao diện – không phải kết quả AI thực tế”. Không rating giả, cam kết fit hoặc banner khuyến mãi không áp dụng.

## Quality gate

Xem ảnh Home/Catalog/Detail 375/768/1440 trước mở rộng. Kiểm tra crop, hierarchy, typography có dấu, CTA, consistency. Không thay palette cho trang khó; sửa component/token nếu nguyên nhân thuộc hệ thống.

## Refinement 09/11/2026

Người dùng chọn giữ tông mận, nâng cấp tinh tế và cao cấp. Xem `REFINEMENT.md`
cho quyết định bố cục và phạm vi. Palette → semantic T → component tokens:
primary mận, hover/pressed mận sâu #452333; button focus có viền; điều khiển
visualDensity.standard. AppButton nhấn scale.98, giữ nhãn khi busy và khóa
submit lặp; reduced motion dùng biểu tượng tĩnh thay spinner ở AppButton.
Header điện thoại dùng tìm kiếm dạng nút mở dialog, giữ yêu thích/giỏ luôn thấy;
không có hàng tìm kiếm thứ hai. Tìm gợi ý debounce250ms và hủy timer khi đóng.
LoadingPanel cùng tỉ lệ3:4/cột/gutter với grid, không shimmer. Gallery fade chỉ
ảnh, không nhân đôi biểu mẫu. Checkout hiển thị bước hiện tại, không biến bước
chưa tới thành nút. Panel tài khoản/quản trị và công cụ AI dùng cùng token.
