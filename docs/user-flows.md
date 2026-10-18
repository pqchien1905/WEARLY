# Sitemap và luồng

```
/ Home
/shop?category=&q=&size=&color=&style=&max=&stock=&sort=&page=
/search?q= (cùng catalog)
/collections → shop biên tập
/products/:slug
/cart → /checkout → /checkout/success/:id
/ai-stylist
/virtual-try-on?product=slug
/login /register /forgot-password
/account /account/orders /account/orders/:id /wishlist
/about /shipping-returns /size-guide /privacy
/admin → products /inventory /orders /customers /promotions /content /ai-monitoring /settings
/design-system (nội bộ)
unmatched → 404
```

Mua: Home → Catalog → filter URL → Detail → màu + size → cart → shipping + địa chỉ → xác nhận demo. Add-to-cart không ép rời trang, có drawer xem giỏ.

AI: prompt hoặc nhập câu hỏi → pending → sản phẩm từ catalog → Detail/try-on. Error có retry.

Try-on: garment + variant → ảnh local → consent → queued → processing → mock result. Xóa/cancel luôn hủy tác vụ đang chờ, không có upload. Ảnh giữ RAM đến khi rời trang.

Admin: danh sách → form → validate → save mock → storefront đồng bộ. Đơn đã tạo giữ snapshot.

## Reference wireframes

Catalog desktop:
```
Breadcrumb
Tủ đồ của bạn                       kết quả / sort
┌ filters 220 ┐ [ảnh 3:4] [ảnh 3:4] [ảnh 3:4]
│ category   │ tên / giá / màu
│ price      │ [ảnh]     [ảnh]     [ảnh]
│ size/color │       pagination
└ clear ─────┘
```
Mobile: title → search → filter button + sort → active chips → 2-column grid; drawer giữ draft nhiều điều kiện, “Xem kết quả” áp dụng một lần, đóng drawer bỏ draft. Quick add mở sheet màu/size rồi thêm đúng SKU vào giỏ mà không rời catalog.

Product Detail desktop:
```
Breadcrumb
┌ ảnh lớn 4:5 ──────────┐ tên / mô tả ngắn / giá
│                      │ màu / size / bảng size
│                      │ kho / số lượng
│                      │ [Thêm vào giỏ]
└ zoom ảnh hiện có ────┘ [Thử đồ demo] / yêu thích
                        chất liệu / giao hàng accordion
Sản phẩm phối cùng từ cùng catalog
```
Mobile: ảnh → tên/giá → variants → CTA, thanh mua phía dưới không che nội dung (padding dành riêng). Home: text/CTA trước ảnh, giữ ảnh hoàn chỉnh; không ép layout desktop vào màn hẹp.
