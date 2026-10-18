# Chuyển mock sang API

Không đổi Riverpod, go_router hoặc tên feature. Mặc định vẫn dùng mock; opt-in riêng catalog bằng dart defines.

| Repository/method hiện có | Endpoint hoặc ranh giới backend | Trạng thái |
|---|---|---|
| ProductRepository.list / bySlug | GET /products, /products/:slug | Remote adapter có test và live smoke |
| ProductRepository.availableColors | GET /products/facets | Facets toàn catalog active |
| ProductRepository.save / delete | Admin PATCH /products/:id; ẩn bằng active=false | API có; Flutter admin chưa nối |
| ProductRepository.consumeStock | Không có public endpoint trừ kho | Chỉ POST /orders được trừ kho; remote adapter từ chối |
| CartRepository.items / subtotal | GET /cart | API có; cache adapter Flutter chưa viết |
| CartRepository.add / update / remove / clear | POST /cart/items, PATCH/DELETE /cart/items/:id | API có add/update/delete; clear và async controller là bước sau |
| OrderRepository.checkout | POST /orders, Idempotency-Key, addressId, expectedSubtotal, cartVersion | API đã test; Flutter CheckoutDraft cần adapter/địa chỉ thật |
| OrderRepository.orders / setStatus | GET /orders, GET /orders/:id; admin PATCH status | API có; Flutter còn demo |
| AccountRepository.signIn(register), save, signOut | POST /auth/register, /auth/login, PATCH /users/me, POST /auth/logout | API có; Flutter còn demo |
| AccountRepository.requestPasswordReset | Chưa có endpoint | Cần mail provider/token có hạn, response không lộ tài khoản |
| AccountDetailsRepository.read/saveAddress/deleteAddress/setDefault | GET/POST/PATCH/DELETE /users/me/addresses; isDefault | API địa chỉ có; Flutter còn demo |
| AccountDetailsRepository.saveStyle | Chưa có model/API sở thích | Giai đoạn sau |
| wishlistProvider.toggle/clear | WishlistItem schema | Chưa có API hoặc remote adapter |
| StylistRepository.reply | Future /ai/stylist/messages | Chưa có API/provider/retrieval |
| TryOnRepository.create/cancel | POST/GET /ai/try-on/jobs | Foundation có, provider Disabled; cancel/upload/delete chưa triển khai |
| Admin state promotions/content/audit | Coupon schema, các endpoint admin có trong api.md | Nội dung, promotions, audit workflow chưa có backend |

## Contract mapping

Flutter query `max` → maxPrice; `stock` → inStock=true. Bộ lọc size/color/price/stock cùng áp dụng trên một variant. Sort newest/price-asc/price-desc/name. images chuyển ProductMedia; categoryId trên catalog JSON là slug legacy để UI dùng đúng nhãn. Variant.id là UUID, SKU giữ mã WRL. Giá `{amount:"490000",currency:"VND"}` → int 490000, không làm tròn số thập phân.

Ảnh seed vẫn trỏ asset bundled để giữ thiết kế. FashionImage hỗ trợ URL HTTP/HTTPS khi có ảnh sản phẩm từ storage/CDN. Ảnh người dùng không dùng đường dẫn công khai đó.

## Các bước tiếp theo

1. Auth remote + secure native keychain; với Web chọn cookie HttpOnly/SameSite và CSRF hoặc session-memory có login lại. SessionTokens hiện chỉ RAM, không ghi localStorage.
2. Địa chỉ thật + profile, ánh xạ lỗi DTO và hết phiên.
3. Cart adapter cache có async mutations; chuyển remove/clear sang Future và trạng thái pending/error.
4. Checkout dùng cartVersion + expectedSubtotal + idempotency key lưu cho một lần retry; không gọi consumeStock. Chuyển OrderRepository, history và admin có auth cùng đợt.
5. Wishlist/reviews/promotions/style preferences.
6. Private upload → AI adapter thật → polling/cancel/delete/retention/quota.

Ở chế độ remote catalog, catalog đọc dữ liệu DB; các luồng khác vẫn là demo. Remote write/checkout bị từ chối rõ ràng, không tạo đơn giả trên DB. Để xem lại toàn bộ demo hiện có, bỏ USE_REMOTE_CATALOG. Không tự fallback sang mock khi API lỗi vì sẽ che giấu sự cố và làm sai giá/tồn.
