# API đã triển khai

Base URL: `http://localhost:3000/api/v1`. Swagger: `http://localhost:3000/api/docs`; OpenAPI JSON `/api/docs-json`. Swagger tự tắt trong production. HTTP JSON UTF-8, UUID, dates ISO UTC. Bearer JWT cho mọi route trừ route công khai.

| Method | Path (sau /api/v1) | Quyền / trạng thái |
|---|---|---|
| POST | /auth/register, /auth/login, /auth/refresh | Public, rate limited; đăng ký/đăng nhập bằng email chỉ dành cho CUSTOMER |
| POST | /auth/admin/login | Public, rate limited; `{username,password}`, yêu cầu tài khoản nhân viên trước khi cấp phiên |
| POST | /auth/forgot-password | Public; `{email}` →202 generic; SMTP/worker phải bật; xem [khôi phục](password-recovery.md) |
| POST | /auth/verify-reset-code | Public; `{email,code}` →200 `{resetToken,expiresIn}`; mã 6 số, 10 phút, tối đa 5 lần sai |
| POST | /auth/reset-password | Public; `{token,password}` →200; token xác nhận một lần, 10 phút, thu hồi mọi phiên |
| POST | /auth/change-password | Bearer (mọi vai trò); `{currentPassword,newPassword}` →200 `{changed:true}`; sai mật khẩu hiện tại →400 `CURRENT_PASSWORD_INVALID`, trùng →400 `PASSWORD_UNCHANGED`; giữ phiên hiện tại, thu hồi phiên khác |
| POST | /auth/logout | Bearer; revoke session family |
| GET | /auth/me | Bearer |
| GET, PATCH | /users/me | Bearer |
| GET, PUT | /users/me/style | Bearer; size, phong cách, màu, ngân sách; PUT yêu cầu expectedVersion; xem style-preferences.md |
| GET, POST | /users/me/addresses | Owner; POST hỗ trợ Idempotency-Key để thử lại an toàn, xem [địa chỉ](address-retries.md) |
| PATCH, DELETE | /users/me/addresses/:id | Owner; xóa mặc định tự chọn địa chỉ còn lại trong cùng transaction |
| GET | /products | Public; sản phẩm active, có ảnh và biến thể active |
| GET | /products/facets | Public; colors, sizes, styles của toàn catalog công khai |
| GET | /products/:slug | Public; cùng điều kiện công khai như danh sách |
| GET | /categories, /brands | Public; chỉ nhóm có sản phẩm công khai |
| GET | /cart | Bearer |
| POST | /cart/items | Bearer; {sku,quantity} |
| PATCH, DELETE | /cart/items/:id | Owner; id là CartItem UUID |
| GET | /wishlist | Owner; toàn bộ danh sách tối đa200 sản phẩm |
| PUT, DELETE | /wishlist/:productId | Owner; UUID sản phẩm; lưu/bỏ idempotent |
| GET | /products/:productId/reviews | Public; phân trang, điểm trung bình, chỉ đánh giá có đơn đã giao; không thông tin tài khoản |
| POST | /products/:productId/reviews | Bearer; đơn đã giao chứa sản phẩm, {rating,comment}, một đánh giá/tài khoản/sản phẩm |
| GET, PATCH, DELETE | /products/:productId/reviews/me | Owner; PATCH/DELETE yêu cầu expectedUpdatedAt; chi tiết tại reviews.md |
| GET | /users/me/reviews | Bearer; lịch sử của mình, page/limit, q (tối đa 100 ký tự), rating (1–5); product gồm name, slug, image, hoặc null khi ngừng bán; canEdit theo điều kiện mua hàng |
| POST | /orders | Bearer; bắt buộc Idempotency-Key |
| GET | /orders, /orders/:id | Owner, phân trang list |
| POST | /orders/:id/cancel | Owner; chỉ PENDING |
| GET, POST | /admin/products | ADMIN/MANAGER |
| GET, PATCH | /admin/products/:id | ADMIN/MANAGER; chi tiết gồm cả SKU đã ẩn |
| DELETE | /admin/products/:id | ADMIN/MANAGER; body `expectedUpdatedAt` bắt buộc. Xóa vĩnh viễn sản phẩm chưa có đơn hàng/lịch sử kho/đánh giá/lượt thử đồ/mục giỏ hàng; 409 `PRODUCT_IN_USE` nếu có liên kết, 409 `PRODUCT_CONFLICT` nếu phiên bản cũ. Thành công trả `{id, deleted: true}` và ghi `PRODUCT_DELETED`. |
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
| GET | /admin/audit | ADMIN; page1..10000, limit1..100; mới nhất trước, tie-break ID |
| GET | /content | Public; chỉ nội dung đã xuất bản hoặc `{content:null}` |
| POST | /content/newsletter | Public; `{email,consent:true}`, lưu PostgreSQL, 10 yêu cầu/phút |
| GET, PUT | /admin/content | ADMIN; đọc/lưu bản nháp `{banner,policy,expectedVersion}` |
| POST | /admin/content/publish | ADMIN; `{expectedVersion}`; xuất bản đúng bản đã lưu |
| POST, GET | /ai/try-on/jobs, /ai/try-on/jobs/:id | Owner; create trả503 khi provider Disabled |
| POST, GET | /uploads/images | Bearer; multipart upload với consent=true / list ảnh của mình |
| GET, DELETE | /uploads/images/:id | Owner; signed URL60s / 202 lên lịch purge |
| GET | /health | Public liveness |
| GET | /health/ready | Public; DB+Redis; 503 khi dependency chưa ready |

Khả năng tích hợp bên ngoài phụ thuộc cấu hình provider. Trạng thái kiểm chứng và giới hạn hiện tại nằm trong [báo cáo hoàn thiện cửa hàng](STOREFRONT_COMPLETION_2026-10-22.md). Reviews được mô tả tại [reviews.md](reviews.md).

`GET /admin/audit` trả `{items:[{id,actorId,action,targetId,createdAt}],total,page,limit}`.
Action gồm PRODUCT_CREATED/UPDATED, SKU_CREATED/UPDATED, CATEGORY_CREATED/RENAMED,
BRAND_CREATED/RENAMED, INVENTORY_ADJUSTED, ORDER_STATUS_CHANGED. Actor lấy từ
bearer session; không có endpoint sửa/xóa lịch sử. Event và thay đổi nghiệp vụ
ghi nguyên tử; chỉ ghi thao tác thành công, không sao chép request body.

## Nội dung cửa hàng

GET draft trả `{id,banner,policy,version,published}`; chưa lưu trả id null,
version0, policy rỗng. PUT yêu cầu banner1..120/policy1..5000 ký tự sau trim.
POST publish chỉ nhận expectedVersion và chụp bản nháp đã lưu; lưu nháp tiếp
không thay publication. Mỗi mutation tăng version, stale/concurrent/replay
trả409; publication đã hiện hành trả409 ALREADY_PUBLISHED.
Public GET trả `{content:{banner,policy,version,publishedAt}}` hoặc null;
không trả draft/actor. Hai thao tác ghi audit CONTENT_DRAFT_SAVED và
CONTENT_PUBLISHED cùng transaction. Không render HTML hoặc thay đổi phí đơn.

## Auth

Register `{name,email,password}`; password 12..128 ký tự, email normalize lowercase. Gửi role/price hoặc field không có trong DTO trả400. Response register/login/refresh:

```json
{"user":{"id":"uuid","email":"customer@example.com","name":"An","phone":"","role":"CUSTOMER"},"accessToken":"JWT","refreshToken":"JWT","expiresIn":900}
```

API token `POST /auth/refresh` nhận `{refreshToken}`, xoay token và vô hiệu hóa session cũ. Replay token cũ revoke toàn family. Logout cần access token, revoke family. Tokens không được log hoặc lưu vào URL.

Flutter Web dùng `/auth/browser/customer/{register,login,refresh,logout}` và `/auth/browser/admin/{login,refresh,logout}`. Access token chỉ ở RAM; cookie phiên HttpOnly, SameSite=Strict có scope riêng, giữ phiên khách hàng tối đa 7 ngày và nhân viên 8 giờ. Sau reload, ứng dụng khôi phục phiên qua cookie; logout/đổi tài khoản loại cache cá nhân. Các route browser yêu cầu Origin được phép và `X-Wearly-Browser: 1`; production yêu cầu HTTPS.

`POST /auth/admin/login` nhận `{username,password}` và trả cùng shape login. Sai thông tin trả401; tài khoản đúng mật khẩu nhưng không phải nhân viên trả403, không tạo refresh token. Flutter sử dụng client/token/account riêng cho quản trị; logout hoặc refresh thất bại không ảnh hưởng phiên mua sắm. `/auth/login` chỉ chấp nhận CUSTOMER; nhân viên cần tài khoản khách hàng riêng để mua sắm.

## Wishlist

`GET /wishlist` và `PUT/DELETE /wishlist/:productId` trả `{items:[{productId,product}],limit:200}`; `product` dùng đúng shape catalog, hoặc `null` nếu đã ẩn/không còn biến thể hoạt động. Không trả thông tin sản phẩm chưa công khai trong placeholder. Danh sách sắp xếp mới lưu trước, tie-break ID; Flutter hiển thị12 mục mỗi trang. API lấy user từ bearer token, không nhận userId làm chủ sở hữu.

Trang `/wishlist` tìm không dấu, lọc tồn kho và sắp xếp giá trên toàn bộ snapshot
tối đa 200 mục; `q`, `stock`, `sort`, `page` trong URL là bộ lọc giao diện, không
phải tham số API. Khi tải lại/ghi lỗi, giao diện giữ snapshot cũ và yêu cầu đọc
lại trước khi thay đổi tiếp. Không đảo thao tác yêu thích để thử lại một phản hồi
bị mất; phản hồi đến muộn kích hoạt đọc lại trong đúng phiên đăng nhập.

PUT lưu sản phẩm đang mở bán, cho phép hết tồn kho. Lưu lại sản phẩm đã có và bỏ sản phẩm chưa có không tạo lỗi hay bản ghi trùng. Giới hạn200 mục được kiểm tra trong transaction có khóa theo user; vượt giới hạn trả409 `WISHLIST_LIMIT`. Bỏ mục vẫn được khi sản phẩm đã ẩn. Dữ liệu thuộc phiên khách hàng của Flutter; ADMIN muốn lưu yêu thích phải đăng nhập riêng ở cửa hàng. Mất phản hồi ghi thì UI yêu cầu tải lại trước khi đảo trạng thái tiếp, không tự giả định lưu thành công.

## Catalog

`GET /products?q=cotton&category=ao&size=M&color=Trắng&minPrice=100000&maxPrice=600000&inStock=true&sort=price-asc&page=1&limit=12`

Sort newest/price-asc/price-desc/name; limit1..100; page1..10000. Filter price/size/color/stock áp dụng cùng một variant.

Tìm kiếm tên hỗ trợ tiếng Việt có/không dấu và Unicode ghép/tách dấu; khoảng trắng
thừa được chuẩn hóa. `%`, `_` và `\` trong từ khóa được tìm như ký tự bình thường,
không phải wildcard SQL. Từ khóa nhiều từ cũng khớp slug nối bằng dấu gạch ngang.

Response:

```json
{"items":[{"id":"uuid","slug":"nep-1","name":"Áo cotton không tay Essential","categoryId":"ao","style":"Tối giản","description":"...","material":"Cotton","active":true,"tryOnSupported":true,"images":[{"url":"assets/images/shirt.jpg","alt":"Ảnh minh họa","color":"Trắng"}],"priceFrom":{"amount":"490000","currency":"VND"},"variants":[{"id":"uuid","sku":"WRL-1-MAIN-M","size":"M","color":"Trắng","colorHex":"#E8E7E2","price":{"amount":"490000","currency":"VND"},"available":12}]}],"total":32,"page":1,"limit":12}
```

categoryId trên catalog JSON là slug tương thích Flutter; category.id bên trong object category là UUID cho admin. Mọi giá là chuỗi Decimal, không phải floating point. Giá priceFrom là min toàn bộ active variants, sort theo cùng giá hiển thị.

`GET /products/facets` trả `{colors:[...],sizes:[...],styles:[...]}` gồm các chuỗi lấy từ toàn bộ sản phẩm công khai, không chỉ trang hiện tại. Size gồm cả số giày và Freesize khi có trong dữ liệu. Danh mục/nhãn hiệu trống vẫn được quản lý qua `/admin/categories` và `/admin/brands` có phân trang.

`POST /content/newsletter` nhận `{"email":"customer@example.com","consent":true}`. Email được trim/lowercase, tối đa 254 ký tự; thiếu đồng ý hoặc email sai trả400. Phản hồi201 `{"accepted":true}` giống nhau cho email mới và đã đăng ký. Unique email ngăn trùng ngay cả khi gửi đồng thời; giữ thời điểm đồng ý đầu tiên. Endpoint chỉ lưu đăng ký, chưa gửi email marketing.

## Bộ sưu tập

`GET /collections?page=1&limit=12` trả `{items,total,page,limit}` từ
`StoreCollection`. Mỗi mục có `id,slug,title,description,style,productCount`
và `cover:{productId,productSlug,url,alt}`. Chỉ liệt kê bộ đang mở và có sản phẩm
công khai; sắp xếp `position,id` ổn định. Không trả version/cấu hình riêng của admin.

`GET /collections/:slug?page=1&limit=12&sort=price-asc&inStock=true` trả
`{collection,items,total,page,limit}`; sản phẩm dùng cùng contract `/products`.
`productCount` là toàn bộ nhóm, `total` là số sau lọc. Phong cách luôn lấy từ bộ
sưu tập, client không thể ghi đè bằng query `style`. Slug không tồn tại hoặc bị
ẩn trả404; nhóm hoạt động nhưng hết sản phẩm trả200 với danh sách rỗng.

`GET/POST /admin/collections`, `PATCH /admin/collections/:id` yêu cầu
`content.manage` (ADMIN/MANAGER). POST nhận `slug,title,description,style` và
`active?,position?,coverProductId?`. PATCH không đổi slug, bắt buộc
`expectedVersion`. Slug và phong cách unique; ảnh bìa phải là sản phẩm công khai
cùng phong cách; `coverProductId:null` chọn tự động. Thiếu ảnh/biến thể hoặc
sản phẩm ẩn không được dùng làm ảnh bìa mới.

Mã lỗi: 400 `INVALID_COLLECTION_COVER`, 409 `DUPLICATE_COLLECTION`,
409 `COLLECTION_CHANGED`. Transaction Serializable và version chống ghi đè;
nhật ký `COLLECTION_CREATED`/`COLLECTION_UPDATED` ghi cùng thay đổi. Ẩn bộ sưu tập
không thay đổi trạng thái sản phẩm, kho hay đơn hàng.

## Cart và order

POST cart/items `{"sku":"WRL-1-MAIN-M","quantity":1}` trả cart{id,version,items,subtotal,currency}. PATCH item `{quantity}` dùng UUID item. Server không nhận giá client.

POST orders có header `Idempotency-Key: checkout-unique-key`:

```json
{"addressId":"owned-address-uuid","shippingMethod":"standard","expectedSubtotal":"490000","cartVersion":1}
```

Response là order trực tiếp, có items và payment. subtotal/shipping/total là decimal strings. Standard30.000, miễn từ1.500.000; express50.000. Tất cả tính ở backend, thống nhất BrandConfig demo. expectedSubtotal bắt buộc, cartVersion nên luôn gửi từ adapter thật. COD Payment vẫn PENDING.

List orders/admin dùng page/limit. Hủy đơn hoặc sửa inventory có kiểm tra trạng thái/phiên bản. Luồng admin: PENDING→CONFIRMED→SHIPPED→DELIVERED, không nhảy bước.

Admin list sắp xếp createdAt/id giảm dần. Admin products trả categoryId/brandId UUID, variants gồm active, price dạng chuỗi và inventory {id,quantity,version}; không dùng shape giá public `{amount,currency}`. POST/PATCH product nhận thêm `images:[{url,alt,color?}]` tối đa20; bỏ field images giữ nguyên bộ ảnh, gửi mảng thay thế bộ ảnh theo thứ tự mảng trong cùng transaction. URL chấp nhận HTTPS, `assets/images/` hoặc managed reference của đúng sản phẩm đã xác minh. Summary đếm toàn database, customers chỉ role CUSTOMER; danh sách users có cả ADMIN.

POST/PATCH sản phẩm chuẩn hóa tên Unicode và khoảng trắng, từ chối tên rỗng.
Tạo mới, đổi tên/thương hiệu hoặc mở bán lại cùng tên trong cùng thương hiệu với
một sản phẩm active trả409 `DUPLICATE_PRODUCT`. Kiểm tra nằm trong transaction
Serializable có retry, nên hai yêu cầu đồng thời không cùng tạo sản phẩm trùng.
Bản lưu trữ `active=false` vẫn giữ được để bảo toàn lịch sử.

`POST /admin/products/:id/images` nhận file JPEG/PNG bằng multipart, bắt buộc
ADMIN và Idempotency-Key UUIDv4. Upload tự thêm vào gallery, trả reference
`catalog/images/<UUID>`. `GET /catalog/images/:id` phục vụ bytes công khai
chỉ khi asset đã xác minh. Ảnh cá nhân vẫn riêng tư. Xem
[giới hạn, replay và vòng đời](catalog-images.md).

## AI foundation

POST jobs `{imageId,sku,consent:true}` được thiết kế trả `{id,status:"pending"}` sau transaction tạo AIJob+outbox. Hiện DisabledTryOnProvider trả503 AI_PROVIDER_NOT_CONFIGURED. GET job kiểm tra owner, trả status/errorCode và signed result URL có TTL60s khi có kết quả còn hạn. Không có ảnh giả.

Worker process riêng dispatch outbox tới BullMQ jobId ổn định, retry3 lần, backoff exponential từ2s, provider timeout60s, concurrency2. Tối đa20 job/ảnh; provider thật chưa cấu hình. Xóa ảnh hủy job chưa hoàn tất; chưa có endpoint hủy riêng một job.

## Khuyến mãi tự động theo sản phẩm

Admin `POST /admin/promotions` và `PATCH /admin/promotions/:id` nhận thêm `application: CODE|AUTOMATIC`, `name`, `scope: ALL|PRODUCTS`, `productIds: UUID[]`. Dữ liệu cũ mặc định `CODE/ALL`. `AUTOMATIC` yêu cầu tên, không cần `code`; `PRODUCTS` yêu cầu ít nhất một ID hợp lệ, `ALL` dùng danh sách rỗng. Loại tự động không có điều kiện đơn tối thiểu/giới hạn lượt (`minSubtotal: "0"`, `usageLimit: null`, `perUserLimit: 1`). Giữ các trường loại giảm, số tiền, trần giảm, lịch, active và kiểm tra phiên bản hiện có. Không đổi `application` sau tạo.

Danh sách admin hỗ trợ lọc `application`, `scope`, tìm `q` theo tên/mã; trả `productIds`, `products` (ID/tên), lịch sử và thống kê theo đúng cách áp dụng. Giá giảm tự động là giá tốt nhất trong các chương trình đang bật, đến thời điểm bắt đầu và chưa hết hạn; giảm trên từng đơn vị, làm tròn xuống đồng và không âm. `products`/wishlist trả từng variant với `price` thực trả, `originalPrice`, `promotion: {id,name,expiresAt}|null`. Cart/order items bổ sung `originalUnitPrice`, `promotionName`; order items lưu liên kết `automaticPromotionId` để bảo toàn lịch sử.

Preview mã và checkout tính khuyến mãi tự động trước, mã nhập tay sau trên các sản phẩm đủ phạm vi. `expectedSubtotal` là tổng sau giảm tự động, trước giảm mã và phí giao hàng; server tính lại trong giao dịch tạo đơn. Các API danh mục lọc/sắp xếp theo giá thực trả. Tắt chương trình chỉ ảnh hưởng các giao dịch mới; không viết lại giá đơn đã tạo.

## Ảnh riêng tư

POST `/uploads/images` nhận multipart `file` (JPEG/PNG tối đa8MiB) và `consent=true`, trả metadata sau khi giải mã/làm sạch và ghi S3. GET list/read chỉ trả ảnh còn hạn thuộc user. DELETE trả202 sau thu hồi quyền đọc; worker purge ảnh/kết quả và retry nếu storage lỗi. Retention24h, URL60s,20 ảnh chưa purge và100 uploads/24h/user. Chi tiết contract, giới hạn pixels, tính nhất quán và cách chạy tại [private-images.md](private-images.md).

## Lỗi và bảo mật

```json
{"error":{"code":"STOCK_CHANGED","message":"Insufficient stock","retryable":false,"requestId":"uuid"},"path":"/api/v1/orders"}
```

400 validation, 401 auth, 403 role, 404 missing/không thuộc owner, 409 stock/price/version/idempotency/state, 413 file quá lớn, 429 throttling/quota, 503 disabled provider/dependency. 500 không trả stack, SQL hoặc secrets. X-Request-Id được tạo tại server. POST201; GET/PATCH/DELETE200, riêng DELETE ảnh202.
