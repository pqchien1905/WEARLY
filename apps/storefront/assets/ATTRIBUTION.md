# Demo assets

Ảnh tải từ Unsplash và đóng gói local, không gọi ảnh từ CDN khi người dùng duyệt demo. Dùng để minh họa phom dáng, không đại diện cho hàng hóa do Wearly sản xuất hoặc chứng thực của người mẫu. Màu của ảnh không đổi khi chọn biến thể. Tám kiểu sản phẩm dùng bảy ảnh, lặp lại trong bốn edition để thử pagination.

| Asset | Nguồn tải chính xác |
|---|---|
| shirt.jpg | https://images.unsplash.com/photo-1598554747436-c9293d6a588f?w=700&q=85&fit=crop |
| black-dress.jpg | https://images.unsplash.com/photo-1585487000160-6ebcfceb0d03?w=700&q=85&fit=crop |
| trousers.jpg | https://images.unsplash.com/photo-1594633312681-425c7b97ccd1?w=700&q=85&fit=crop |
| outerwear.jpg | https://images.unsplash.com/photo-1591047139829-d91aecb6caea?w=700&q=85&fit=crop |
| jacket.jpg | https://images.unsplash.com/photo-1551803091-e20673f15770?w=700&q=85&fit=crop |
| dress.jpg | https://images.unsplash.com/photo-1595777457583-95e059d581b8?w=700&q=85&fit=crop |
| campaign.jpg | https://images.unsplash.com/photo-1539109136881-3be0616acf4b?w=1400&q=85&fit=crop |

Tên file `black-dress` và `jacket` là tên kỹ thuật lúc thu thập; nội dung thực tế lần lượt là đầm mận và đầm ren tím. Fixture đã được điều chỉnh theo ảnh đã xem. Các ảnh phụ không dùng đã được loại khỏi bundle.

[Unsplash License](https://unsplash.com/license) cho phép sử dụng ảnh theo điều kiện trên trang nguồn; không mặc định rằng quyền về người mẫu, thương hiệu hoặc hàng hóa của cửa hàng đã được xác lập. Trước mở bán, thay bằng bộ ảnh sản phẩm thuộc quyền sử dụng của thương hiệu, đúng SKU, màu và góc chụp. Tác giả từng ảnh chưa được xác minh, không gán credit suy đoán.

Fonts: [Be Vietnam Pro](https://github.com/google/fonts/tree/main/ofl/bevietnampro) và [Manrope](https://github.com/google/fonts/tree/main/ofl/manrope), SIL Open Font License, bản license nằm trong `fonts/*-OFL.txt`. Family `Roboto` được alias sang file Be Vietnam Pro local để đáp ứng fallback mặc định của web engine; không phải một font thiết kế thứ ba.

Wordmark chữ, favicon SVG: tạo cho placeholder Wearly trong dự án. Icon UI: Material Icons của Flutter và Cupertino Icons (dependency license kèm package). Không có ảnh AI được sinh để giả làm kết quả Try-On.
