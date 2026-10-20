# Chuyển mock sang API

Giữ Flutter, Riverpod, go_router và bố cục hiện có. `USE_REMOTE_API=true` bật catalog + tài khoản + luồng mua hàng thật. Mặc định vẫn dùng mock; `USE_REMOTE_CATALOG=true` giữ chế độ catalog-only cũ. Lệnh ngắn: `.\tools\frontend.ps1 api` từ root.

| Repository/method hiện có | Endpoint hoặc ranh giới backend | Trạng thái |
|---|---|---|
| ProductRepository.list / bySlug | GET /products, /products/:slug | Remote adapter có test và live smoke |
| ProductRepository.availableColors | GET /products/facets | Facets toàn catalog active |
| ProductRepository.save / delete | Admin POST/PATCH /products, /skus; ẩn bằng active=false | Remote admin riêng: metadata/bộ ảnh, SKU, giá/trạng thái; giữ adapter public độc lập |
| ProductRepository.consumeStock | Không có public endpoint trừ kho | Chỉ POST /orders được trừ kho; remote adapter từ chối |
| CartRepository.items / subtotal | GET /cart | Cache remote, loading/error/retry, tách theo tài khoản |
| CartRepository.add / update / remove / clear | POST /cart/items, PATCH/DELETE /cart/items/:id | Mutations async tuần tự, dùng UUID dòng giỏ; clear xóa từng dòng |
| OrderRepository.checkout | POST /orders, Idempotency-Key, addressId, expectedSubtotal, cartVersion | Remote COD; retry sau lỗi mạng giữ nguyên key/body; không gọi consumeStock |
| OrderRepository.orders / setStatus | GET /orders, GET /orders/:id, POST /orders/:id/cancel; admin PATCH /orders/:id/status | Khách xem/hủy đơn chờ; ADMIN chuyển trạng thái theo bước và expectedVersion |
| AccountRepository.signIn(register), save, signOut | POST /auth/register, /auth/login, PATCH /users/me, POST /auth/logout | Remote auth/refresh, hồ sơ name/phone, logout xóa cache ngay |
| AccountRepository.requestPasswordReset / reset | POST /auth/forgot-password, /auth/reset-password | SMTP/worker/token có hạn và Flutter đã nối; external delivery chờ cấu hình, xem password-recovery.md |
| AccountDetailsRepository.read/saveAddress/deleteAddress/setDefault | GET/POST/PATCH/DELETE /users/me/addresses; isDefault | Remote CRUD/default; checkout chọn UUID đã lưu |
| AccountDetailsRepository.read/saveStyle | GET/PUT /users/me/style | Đã nối hồ sơ phong cách thật; snapshot version, ngân sách VND string, xung đột/lỗi chưa rõ yêu cầu tải lại |
| wishlistProvider demo / remoteWishlistProvider | GET /wishlist; PUT/DELETE /wishlist/:productId | Lưu thật theo tài khoản, snapshot tối đa200 mục; card/detail/cart và trang danh sách đã nối; không bulk-clear |
| StylistRepository.reply | Future /ai/stylist/messages | Chưa có API/provider/retrieval |
| TryOnRepository.create/cancel | POST/GET /ai/try-on/jobs; POST/GET/DELETE /uploads/images | Upload/delete/retention/quota có; provider Disabled, Flutter chưa nối; hủy qua xóa ảnh, chưa cancel riêng job |
| Admin state content/audit | GET/PUT /admin/content, POST /admin/content/publish, GET /admin/activity | Nháp/xuất bản và lịch sử13 loại thao tác đã lưu thật, có RBAC và kiểm thử |
| Admin state promotions | Coupon schema | BLOCKED: cần thống nhất UI phần trăm với schema số tiền VND trước khi áp dụng vào đơn |

## Contract mapping

Flutter query `max` → maxPrice; `stock` → inStock=true. Bộ lọc size/color/price/stock cùng áp dụng trên một variant. Sort newest/price-asc/price-desc/name. images chuyển ProductMedia; categoryId trên catalog JSON là slug legacy để UI dùng đúng nhãn. Variant.id là UUID, SKU giữ mã WRL. Giá `{amount:"490000",currency:"VND"}` → int 490000, không làm tròn số thập phân.

Ảnh seed vẫn trỏ asset bundled để giữ thiết kế. FashionImage hỗ trợ URL HTTP/HTTPS và `catalog/images/<UUID>` giải theo base API. Admin upload file vào sản phẩm đã lưu; public route chỉ phục vụ CatalogAsset đã xác minh. Ảnh người dùng không dùng đường dẫn công khai đó.

## Phiên đăng nhập và đặt hàng

Token access/refresh chỉ ở RAM, refresh đồng thời được gộp thành một yêu cầu. Logout hoặc đổi tài khoản loại cache cá nhân và kết quả request cũ. Tải lại trang cần đăng nhập lại; dữ liệu trên DB được đọc lại. Chưa triển khai keychain native hoặc cookie HttpOnly/CSRF.

Giá VND được đọc từ chuỗi số nguyên, không làm tròn. Checkout gửi địa chỉ UUID, số phiên bản giỏ và subtotal dự kiến; máy chủ tính tiền/tồn kho. Khi không nhận được kết quả rõ ràng, giỏ bị khóa và nút kiểm tra lại gửi đúng key/body cũ. Key chỉ giữ trong RAM: nếu đã tải lại/đăng xuất sau lỗi mạng, xem lịch sử đơn trước khi đặt tiếp. Thành công chỉ xóa cache giỏ tại máy, không gọi DELETE giỏ trên server. COD hiển thị chưa thu tiền, không giả lập thanh toán thành công.

## Các bước còn lại

1. Quản trị sản phẩm/SKU/kho/đơn/khách hàng và danh mục/thương hiệu đã nối API với quyền ADMIN. Danh mục công khai lấy từ API; đổi tên giữ đường dẫn. Audit13 loại thao tác, upload catalog và nội dung nháp/xuất bản đã nối. Đối soát COD còn chờ quy tắc xác nhận.
2. Wishlist, đánh giá sản phẩm (gồm Đánh giá của tôi), hồ sơ phong cách và khôi phục mật khẩu đã nối API. Promotions và email provider ngoài Internet còn chờ; mở rộng đánh giá (ảnh, phản hồi cửa hàng, moderation) chưa có.
3. Nối private upload hiện có → AI adapter thật → polling/cancel riêng job; đưa consent/delete/quota vào UI hiện tại.
4. Payment provider, webhook và hạ tầng triển khai production. Chưa có cam kết production-ready.

Ở chế độ remote catalog, catalog đọc dữ liệu DB; các luồng khác vẫn là demo. Remote write/checkout bị từ chối rõ ràng, không tạo đơn giả trên DB. Để xem lại toàn bộ demo hiện có, bỏ USE_REMOTE_CATALOG. Không tự fallback sang mock khi API lỗi vì sẽ che giấu sự cố và làm sai giá/tồn.
