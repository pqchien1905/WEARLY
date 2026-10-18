# Chuyển mock sang API

Giữ Flutter, Riverpod, go_router và bố cục hiện có. `USE_REMOTE_API=true` bật catalog + tài khoản + luồng mua hàng thật. Mặc định vẫn dùng mock; `USE_REMOTE_CATALOG=true` giữ chế độ catalog-only cũ. Lệnh ngắn: `.\tools\frontend.ps1 api` từ root.

| Repository/method hiện có | Endpoint hoặc ranh giới backend | Trạng thái |
|---|---|---|
| ProductRepository.list / bySlug | GET /products, /products/:slug | Remote adapter có test và live smoke |
| ProductRepository.availableColors | GET /products/facets | Facets toàn catalog active |
| ProductRepository.save / delete | Admin PATCH /products/:id; ẩn bằng active=false | API có; Flutter admin chưa nối |
| ProductRepository.consumeStock | Không có public endpoint trừ kho | Chỉ POST /orders được trừ kho; remote adapter từ chối |
| CartRepository.items / subtotal | GET /cart | Cache remote, loading/error/retry, tách theo tài khoản |
| CartRepository.add / update / remove / clear | POST /cart/items, PATCH/DELETE /cart/items/:id | Mutations async tuần tự, dùng UUID dòng giỏ; clear xóa từng dòng |
| OrderRepository.checkout | POST /orders, Idempotency-Key, addressId, expectedSubtotal, cartVersion | Remote COD; retry sau lỗi mạng giữ nguyên key/body; không gọi consumeStock |
| OrderRepository.orders / setStatus | GET /orders, GET /orders/:id, POST /orders/:id/cancel | Lịch sử phân trang, chi tiết và hủy đơn chờ xác nhận; admin chưa nối |
| AccountRepository.signIn(register), save, signOut | POST /auth/register, /auth/login, PATCH /users/me, POST /auth/logout | Remote auth/refresh, hồ sơ name/phone, logout xóa cache ngay |
| AccountRepository.requestPasswordReset | Chưa có endpoint | Cần mail provider/token có hạn, response không lộ tài khoản |
| AccountDetailsRepository.read/saveAddress/deleteAddress/setDefault | GET/POST/PATCH/DELETE /users/me/addresses; isDefault | Remote CRUD/default; checkout chọn UUID đã lưu |
| AccountDetailsRepository.saveStyle | Chưa có model/API sở thích | Giai đoạn sau |
| wishlistProvider.toggle/clear | WishlistItem schema | Chưa có API hoặc remote adapter |
| StylistRepository.reply | Future /ai/stylist/messages | Chưa có API/provider/retrieval |
| TryOnRepository.create/cancel | POST/GET /ai/try-on/jobs; POST/GET/DELETE /uploads/images | Upload/delete/retention/quota có; provider Disabled, Flutter chưa nối; hủy qua xóa ảnh, chưa cancel riêng job |
| Admin state promotions/content/audit | Coupon schema, các endpoint admin có trong api.md | Nội dung, promotions, audit workflow chưa có backend |

## Contract mapping

Flutter query `max` → maxPrice; `stock` → inStock=true. Bộ lọc size/color/price/stock cùng áp dụng trên một variant. Sort newest/price-asc/price-desc/name. images chuyển ProductMedia; categoryId trên catalog JSON là slug legacy để UI dùng đúng nhãn. Variant.id là UUID, SKU giữ mã WRL. Giá `{amount:"490000",currency:"VND"}` → int 490000, không làm tròn số thập phân.

Ảnh seed vẫn trỏ asset bundled để giữ thiết kế. FashionImage hỗ trợ URL HTTP/HTTPS khi có ảnh sản phẩm từ storage/CDN. Ảnh người dùng không dùng đường dẫn công khai đó.

## Phiên đăng nhập và đặt hàng

Token access/refresh chỉ ở RAM, refresh đồng thời được gộp thành một yêu cầu. Logout hoặc đổi tài khoản loại cache cá nhân và kết quả request cũ. Tải lại trang cần đăng nhập lại; dữ liệu trên DB được đọc lại. Chưa triển khai keychain native hoặc cookie HttpOnly/CSRF.

Giá VND được đọc từ chuỗi số nguyên, không làm tròn. Checkout gửi địa chỉ UUID, số phiên bản giỏ và subtotal dự kiến; máy chủ tính tiền/tồn kho. Khi không nhận được kết quả rõ ràng, giỏ bị khóa và nút kiểm tra lại gửi đúng key/body cũ. Key chỉ giữ trong RAM: nếu đã tải lại/đăng xuất sau lỗi mạng, xem lịch sử đơn trước khi đặt tiếp. Thành công chỉ xóa cache giỏ tại máy, không gọi DELETE giỏ trên server. COD hiển thị chưa thu tiền, không giả lập thanh toán thành công.

## Các bước còn lại

1. Flutter quản trị có quyền ADMIN và mutations thật; hiện các route admin bị chặn trong chế độ API.
2. Wishlist/reviews/promotions/style preferences, khôi phục mật khẩu và email provider.
3. Nối private upload hiện có → AI adapter thật → polling/cancel riêng job; đưa consent/delete/quota vào UI hiện tại.
4. Payment provider, webhook và hạ tầng triển khai production. Chưa có cam kết production-ready.

Ở chế độ remote catalog, catalog đọc dữ liệu DB; các luồng khác vẫn là demo. Remote write/checkout bị từ chối rõ ràng, không tạo đơn giả trên DB. Để xem lại toàn bộ demo hiện có, bỏ USE_REMOTE_CATALOG. Không tự fallback sang mock khi API lỗi vì sẽ che giấu sự cố và làm sai giá/tồn.
