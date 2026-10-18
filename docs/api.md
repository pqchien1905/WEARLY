# API đã triển khai

Base URL: `http://localhost:3000/api/v1`. Swagger: `http://localhost:3000/api/docs`; OpenAPI JSON `/api/docs-json`. Swagger tự tắt trong production. HTTP JSON UTF-8, UUID, dates ISO UTC. Bearer JWT cho mọi route trừ route công khai.

| Method | Path (sau /api/v1) | Quyền / trạng thái |
|---|---|---|
| POST | /auth/register, /auth/login, /auth/refresh | Public, rate limited |
| POST | /auth/admin/login | Public, rate limited; xác thực mật khẩu và yêu cầu role ADMIN trước khi cấp phiên |
| POST | /auth/logout | Bearer; revoke session family |
| GET | /auth/me | Bearer |
| GET, PATCH | /users/me | Bearer |
| GET, POST | /users/me/addresses | Owner |
| PATCH, DELETE | /users/me/addresses/:id | Owner |
| GET | /products | Public; active products |
| GET | /products/facets | Public; colors toàn catalog |
| GET | /products/:slug | Public; active SKU |
| GET | /categories, /brands | Public |
| GET | /cart | Bearer |
| POST | /cart/items | Bearer; {sku,quantity} |
| PATCH, DELETE | /cart/items/:id | Owner; id là CartItem UUID |
| GET | /wishlist | Owner; toàn bộ danh sách tối đa200 sản phẩm |
| PUT, DELETE | /wishlist/:productId | Owner; UUID sản phẩm; lưu/bỏ idempotent |
| GET | /products/:productId/reviews | Public; phân trang, điểm trung bình, chỉ đánh giá có đơn đã giao; không thông tin tài khoản |
| POST | /products/:productId/reviews | Bearer; đơn đã giao chứa sản phẩm, {rating,comment}, một đánh giá/tài khoản/sản phẩm |
| GET, PATCH, DELETE | /products/:productId/reviews/me | Owner; PATCH/DELETE yêu cầu expectedUpdatedAt; chi tiết tại reviews.md |
| POST | /orders | Bearer; bắt buộc Idempotency-Key |
| GET | /orders, /orders/:id | Owner, phân trang list |
| POST | /orders/:id/cancel | Owner; chỉ PENDING |
| GET, POST | /admin/products | ADMIN |
| GET, PATCH | /admin/products/:id | ADMIN; chi tiết gồm cả SKU đã ẩn |
| GET | /admin/summary | ADMIN; products, inventoryUnits, orders, pendingOrders, customers |
| POST | /admin/skus | ADMIN; inventory ban đầu 0 |
| PATCH | /admin/skus/:id | ADMIN; price/active |
| GET, POST | /admin/categories, /admin/brands | ADMIN; list phân trang kèm _count.products; tạo {name,slug} |
| PATCH | /admin/categories/:id, /admin/brands/:id | ADMIN; đổi tên {name,expectedName}; giữ nguyên slug, xung đột 409 |
| GET | /admin/inventory | ADMIN |
| POST | /admin/inventory/:id/adjust | ADMIN; delta,expectedVersion,reason |
| GET | /admin/orders, /admin/orders/:id | ADMIN; gồm snapshots, version, payment và user.email/name |
| PATCH | /admin/orders/:id/status | ADMIN; status,expectedVersion |
| GET | /admin/users | ADMIN; không passwordHash |
| POST, GET | /ai/try-on/jobs, /ai/try-on/jobs/:id | Owner; create trả503 khi provider Disabled |
| POST, GET | /uploads/images | Bearer; multipart upload với consent=true / list ảnh của mình |
| GET, DELETE | /uploads/images/:id | Owner; signed URL60s / 202 lên lịch purge |
| GET | /health | Public liveness |
| GET | /health/ready | Public; DB+Redis; 503 khi dependency chưa ready |

Không có API reset password, reviews, promotions, AI Stylist hoặc online payments ở foundation này. Admin là các endpoint kể trên, chưa có toàn bộ workflow quản trị/audit.

## Auth

Register `{name,email,password}`; password 12..128 ký tự, email normalize lowercase. Gửi role/price hoặc field không có trong DTO trả400. Response register/login/refresh:

```json
{"user":{"id":"uuid","email":"customer@example.com","name":"An","phone":"","role":"CUSTOMER"},"accessToken":"JWT","refreshToken":"JWT","expiresIn":900}
```

POST refresh `{refreshToken}` xoay token và vô hiệu hóa session cũ. Replay token cũ revoke toàn family. Logout cần access token, revoke family. Tokens không được log hoặc lưu vào URL. Flutter đã tích hợp bearer auth khi bật `USE_REMOTE_API=true`; access/refresh token chỉ ở RAM, refresh đồng thời được gộp, logout/đổi tài khoản loại cache cá nhân. Sau reload cần đăng nhập lại, dữ liệu trên PostgreSQL vẫn được giữ.

`POST /auth/admin/login` nhận `{email,password}` và trả cùng shape login. Sai thông tin trả401; tài khoản đúng mật khẩu nhưng không có quyền ADMIN trả403, không tạo refresh token. Flutter sử dụng client/token/account riêng cho quản trị; logout hoặc refresh thất bại không ảnh hưởng phiên mua sắm. `/auth/login` vẫn chấp nhận ADMIN để họ mua sắm bằng một phiên độc lập. Đây là tách luồng sử dụng và phiên; quyền endpoint vẫn xác minh theo role hiện tại trên máy chủ.

## Wishlist

`GET /wishlist` và `PUT/DELETE /wishlist/:productId` trả `{items:[{productId,product}],limit:200}`; `product` dùng đúng shape catalog, hoặc `null` nếu đã ẩn/không còn biến thể hoạt động. Không trả thông tin sản phẩm chưa công khai trong placeholder. Danh sách sắp xếp mới lưu trước, tie-break ID; Flutter hiển thị12 mục mỗi trang. API lấy user từ bearer token, không nhận userId làm chủ sở hữu.

PUT lưu sản phẩm đang mở bán, cho phép hết tồn kho. Lưu lại sản phẩm đã có và bỏ sản phẩm chưa có không tạo lỗi hay bản ghi trùng. Giới hạn200 mục được kiểm tra trong transaction có khóa theo user; vượt giới hạn trả409 `WISHLIST_LIMIT`. Bỏ mục vẫn được khi sản phẩm đã ẩn. Dữ liệu thuộc phiên khách hàng của Flutter; ADMIN muốn lưu yêu thích phải đăng nhập riêng ở cửa hàng. Mất phản hồi ghi thì UI yêu cầu tải lại trước khi đảo trạng thái tiếp, không tự giả định lưu thành công.

## Catalog

`GET /products?q=cotton&category=ao&size=M&color=Trắng&minPrice=100000&maxPrice=600000&inStock=true&sort=price-asc&page=1&limit=12`

Sort newest/price-asc/price-desc/name; limit1..100; page1..10000. Filter price/size/color/stock áp dụng cùng một variant. Response:

```json
{"items":[{"id":"uuid","slug":"nep-1","name":"Áo cotton không tay Essential","categoryId":"ao","style":"Tối giản","description":"...","material":"Cotton","active":true,"tryOnSupported":true,"images":[{"url":"assets/images/shirt.jpg","alt":"Ảnh minh họa","color":"Trắng"}],"priceFrom":{"amount":"490000","currency":"VND"},"variants":[{"id":"uuid","sku":"WRL-1-MAIN-M","size":"M","color":"Trắng","colorHex":"#E8E7E2","price":{"amount":"490000","currency":"VND"},"available":12}]}],"total":32,"page":1,"limit":12}
```

categoryId trên catalog JSON là slug tương thích Flutter; category.id bên trong object category là UUID cho admin. Mọi giá là chuỗi Decimal, không phải floating point. Giá priceFrom là min toàn bộ active variants, sort theo cùng giá hiển thị.

## Cart và order

POST cart/items `{"sku":"WRL-1-MAIN-M","quantity":1}` trả cart{id,version,items,subtotal,currency}. PATCH item `{quantity}` dùng UUID item. Server không nhận giá client.

POST orders có header `Idempotency-Key: checkout-unique-key`:

```json
{"addressId":"owned-address-uuid","shippingMethod":"standard","expectedSubtotal":"490000","cartVersion":1}
```

Response là order trực tiếp, có items và payment. subtotal/shipping/total là decimal strings. Standard30.000, miễn từ1.500.000; express50.000. Tất cả tính ở backend, thống nhất BrandConfig demo. expectedSubtotal bắt buộc, cartVersion nên luôn gửi từ adapter thật. COD Payment vẫn PENDING.

List orders/admin dùng page/limit. Hủy đơn hoặc sửa inventory có kiểm tra trạng thái/phiên bản. Luồng admin: PENDING→CONFIRMED→SHIPPED→DELIVERED, không nhảy bước.

Admin list sắp xếp createdAt/id giảm dần. Admin products trả categoryId/brandId UUID, variants gồm active, price dạng chuỗi và inventory {id,quantity,version}; không dùng shape giá public `{amount,currency}`. POST/PATCH product nhận thêm `images:[{url,alt,color?}]` tối đa20; bỏ field images giữ nguyên bộ ảnh, gửi mảng thay thế bộ ảnh theo thứ tự mảng trong cùng transaction. URL chấp nhận HTTPS hoặc `assets/images/`; không tải file hoặc tạo public URL cho ảnh người dùng. Summary đếm toàn database, customers chỉ role CUSTOMER; danh sách users có cả ADMIN.

## AI foundation

POST jobs `{imageId,sku,consent:true}` được thiết kế trả `{id,status:"pending"}` sau transaction tạo AIJob+outbox. Hiện DisabledTryOnProvider trả503 AI_PROVIDER_NOT_CONFIGURED. GET job kiểm tra owner, trả status/errorCode và signed result URL có TTL60s khi có kết quả còn hạn. Không có ảnh giả.

Worker process riêng dispatch outbox tới BullMQ jobId ổn định, retry3 lần, backoff exponential từ2s, provider timeout60s, concurrency2. Tối đa20 job/ảnh; provider thật chưa cấu hình. Xóa ảnh hủy job chưa hoàn tất; chưa có endpoint hủy riêng một job.

## Ảnh riêng tư

POST `/uploads/images` nhận multipart `file` (JPEG/PNG tối đa8MiB) và `consent=true`, trả metadata sau khi giải mã/làm sạch và ghi S3. GET list/read chỉ trả ảnh còn hạn thuộc user. DELETE trả202 sau thu hồi quyền đọc; worker purge ảnh/kết quả và retry nếu storage lỗi. Retention24h, URL60s,20 ảnh chưa purge và100 uploads/24h/user. Chi tiết contract, giới hạn pixels, tính nhất quán và cách chạy tại [private-images.md](private-images.md).

## Lỗi và bảo mật

```json
{"error":{"code":"STOCK_CHANGED","message":"Insufficient stock","retryable":false,"requestId":"uuid"},"path":"/api/v1/orders"}
```

400 validation, 401 auth, 403 role, 404 missing/không thuộc owner, 409 stock/price/version/idempotency/state, 413 file quá lớn, 429 throttling/quota, 503 disabled provider/dependency. 500 không trả stack, SQL hoặc secrets. X-Request-Id được tạo tại server. POST201; GET/PATCH/DELETE200, riêng DELETE ảnh202.
