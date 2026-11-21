# WEARLY — tinh chỉnh giao diện 2026-11

Giữ nhận diện mận theo lựa chọn của người dùng. Áp dụng cho cửa hàng,
tài khoản, các công cụ AI và quản trị qua cùng một hệ thống thành phần.

## Hướng thiết kế trước triển khai

So sánh hai bố cục trang chủ:

```
A: [ lời giới thiệu / CTA mận  |  ảnh thiết kế lớn ]
   [ danh mục ] [ bộ sản phẩm ] [ stylist ] [ phòng thử ]
B: [ ảnh toàn màn hình + chữ phủ lên ảnh ]
   [ danh mục và sản phẩm ]
```

Chọn A: vùng chữ độc lập giữ độ tương phản khi quản trị viên đổi ảnh/banner;
ảnh vẫn là điểm nhấn. Mobile xếp chữ và ảnh theo chiều dọc. Các trang làm việc
căn trái, khoảng cách rõ, bảng chuyển thành các hàng có nhãn trên điện thoại.

Sau khi rà soát: bỏ ý tưởng glass/gradient và các thẻ trang trí giống nhau.
Chỉ dùng một mảng mận lớn ở hero; hình sản phẩm, chức năng và dữ liệu là nội dung
chính. Giữ font Việt cục bộ thay cho tải thêm font mới.

## Token và thành phần

- Primitive: mận #65394D, mận sâu #452333, trắng #FFFFFF, nền #F8F6F8,
  chữ #29232A, chữ phụ #706670. Semantic aliases nằm trong `T`.
- Manrope cho tiêu đề, Be Vietnam Pro cho nội dung và điều khiển. Tiêu đề
  co theo viewport; chữ biểu mẫu không bị ép vào chiều cao cố định.
- Điều khiển bo 10px; ảnh 12px; panel 16px; hero/dialog 24px. Không đổ bóng
  lên mọi thẻ. Chỉ menu, dialog và các lớp nổi cần cảm giác độ cao.
- Button chính màu mận; hover mận sâu, focus có viền, disabled khác rõ;
  trạng thái chờ khóa thao tác và vẫn giữ nhãn.
- Header mobile gọn; tìm kiếm, yêu thích và giỏ hàng vẫn trực tiếp truy cập.
- Chuyển trạng thái 160–240ms, ảnh hover 320ms; nút nhấn co nhẹ trong khung,
  gallery đổi ảnh bằng fade; không dịch chuyển bố cục. Giảm chuyển động tắt
  transform và rút thời lượng về 0. Không thêm hoạt ảnh lặp vô hạn.
- Dùng hit target tối thiểu 44px, focus bàn phím, nhãn semantics và màu trạng
  thái kèm chữ. Không giấu thao tác quan trọng sau hover.

## Kiểm chứng

Phân tích Dart, toàn bộ Flutter tests, build release; kiểm tra trực quan các
luồng cửa hàng, sản phẩm, giỏ hàng, tài khoản và quản trị trên desktop/mobile.
Chỉ đổi phần trình bày, giữ nguyên dữ liệu, quyền và quy tắc giao dịch.

Kết quả triển khai: `flutter analyze` sạch; 766 test thành công, 2 test bỏ qua
theo suite hiện có; build web release thành công. Browser kiểm tra cửa hàng tại
320/375/768/1440/2560px, tài khoản/giỏ/checkout/AI tại320/375/768/1440px và bốn
trang vận hành tại320/375/768/1440px. Kiểm tra tìm kiếm, bộ lọc, phóng ảnh,
Escape, menu, phân trang, trạng thái rỗng/lỗi và thử lại không ghi nhận lỗi JS.
Các kiểm thử tài khoản/quản trị dùng API fixture trong browser, không ghi dữ liệu
thật. Ảnh/report nằm trong `.tools/ui-refinement`, `.tools/ui-refinement-account`
và `.tools/operations-ui`; audit màu lưu tại `docs/qa/ui-refinement-contrast.json`.

Regression đã xử lý: WidgetStatesController có thể thông báo trong build khi
button bị khóa, nên chỉ cập nhật press state ngoài build; panel có ListTile cần
Material trong nền để giữ hover/focus nhìn thấy; nhóm icon mobile giữ target44px
để không tràn khi phóng chữ. Test checkout cuộn đến địa chỉ trước khi thao tác.
