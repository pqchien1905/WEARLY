# Contracts cho giai đoạn NestJS

**Thiết kế tích hợp, chưa có server hoặc request API trong ứng dụng hiện tại.** Contracts dưới đây là ranh giới mong đợi để thay mock. UI không được làm nguồn thẩm quyền về giá, tồn kho, quyền hoặc trạng thái thanh toán.

## Quy ước chung

- Base path `/v1`, JSON UTF-8. IDs/SKU opaque strings; timestamps ISO-8601 UTC. Giá `{amount: 490000, currency: "VND"}`, amount là integer, không float.
- Pagination `page` (1-based), `limit` (1–100), response `{items, page, limit, total}`. Query lọc kết hợp AND; đa lựa chọn tương lai phải version hóa rõ.
- Lỗi `{error:{code,message,fieldErrors?,retryable,requestId}}`; fieldErrors map field→message. Adapter ánh xạ sang copy UI tiếng Việt, không hiển thị stack/provider errors.
- `400 VALIDATION_ERROR`, `401 AUTH_REQUIRED`, `403 FORBIDDEN`, `404 NOT_FOUND`, `409 STOCK_CHANGED / PRICE_CHANGED / VERSION_CONFLICT`, `413 IMAGE_TOO_LARGE`, `415 UNSUPPORTED_MEDIA`, `429 RATE_LIMITED`, `503 SERVICE_UNAVAILABLE`. Tôn trọng Retry-After.
- Session cookie Secure/HttpOnly, CSRF cho mutations, authorization và ownership kiểm tra tại NestJS. Admin không được bảo vệ chỉ bằng route guard Flutter.
- Mutations có nguy cơ trùng dùng `Idempotency-Key`; admin cập nhật dùng version/ETag để tránh ghi đè dữ liệu đồng thời. Logs không chứa ảnh, token, signed URL hoặc prompt nhạy cảm.

## Catalog

`GET /v1/products?q=&category=&size=&color=&style=&maxPrice=&inStock=&sort=&page=1&limit=12`

Flutter URL dùng `max`, `stock=true`; adapter đổi thành `maxPrice`, `inStock=true`. Thiếu `max` nghĩa là không giới hạn (`ProductQuery.maxPrice == null`); không dùng một số tiền cố định để đại diện “tất cả”. Sort `newest|price-asc|price-desc|name`. Filters size, color, price, stock phải cùng thỏa trên một biến thể. Server chỉ trả active products cho khách. `ProductRepository.availableColors()` cần map tới facets của toàn bộ catalog active, không chỉ trang12 kết quả hiện tại; mock đã hỗ trợ phương thức này.

```json
{
  "items": [{
    "id": "p1", "slug": "nep-1", "name": "Áo cotton không tay Essential",
    "categoryId": "ao", "style": "Tối giản", "active": true,
    "description": "...", "material": "Cotton", "tryOnSupported": true,
    "images": [{"id":"image-1","url":"https://cdn.example/product.jpg","alt":"Áo trắng, mặt trước","width":700,"height":1050}],
    "priceFrom": {"amount":490000,"currency":"VND"},
    "variants": [{"sku":"WRL-1-MAIN-M","size":"M","color":"Trắng","colorHex":"#E8E7E2","price":{"amount":490000,"currency":"VND"},"available":12}],
    "version": 1
  }],
  "page": 1, "limit": 12, "total": 32
}
```

`GET /v1/products/:slug`: chi tiết cùng schema, 404 nếu ẩn/không tồn tại. Adapter chuyển images thành `ProductMedia(path, label, color)`; FashionImage hiện dùng local asset, cần hỗ trợ network image/error/loading tại component chung. Gallery đã hỗ trợ thumbnails, keyboard và lightbox cho nhiều ảnh; bộ fixture hiện chỉ có một ảnh nguồn/kiểu. Không có ảnh đúng màu thì hiển thị ảnh tham khảo với thông báo, không giả góc hoặc màu khác.

`GET /v1/recommendations?productId=&size=&maxPrice=&limit=4`: sản phẩm thật, giá/tồn hiện hành; không trả ID do LLM tự tạo.

## Cart và checkout

`GET /v1/cart` → `{id, version, items, subtotal, shippingQuote?, total}`. Mỗi item chứa SKU, productId/slug, name, image, color, size, unitPrice, quantity, availability. Snapshot từ server, không tin giá client.

`POST /v1/cart/items` body `{sku,quantity}`; `PATCH /v1/cart/items/:sku` body `{quantity,cartVersion}`; `DELETE /v1/cart/items/:sku`. Trả toàn bộ cart chuẩn hóa. Adapter cập nhật cache rồi notify controller. Không cập nhật theo index của list vì thứ tự có thể thay đổi.

`POST /v1/orders/checkout`, Idempotency-Key bắt buộc:

```json
{
  "cartId":"cart-1", "cartVersion":3,
  "contact":{"name":"Nguyễn An","email":"an@example.com","phone":"0901234567"},
  "address":{"line1":"12 Nguyễn Huệ","district":"Quận 1","city":"TP.HCM","country":"VN"},
  "shippingMethodId":"standard", "paymentMethodId":"cod"
}
```

Response `201 {order:{id,status,itemsSnapshot,contactSnapshot,addressSnapshot,subtotal,shipping,total,createdAt}, payment:{status,nextAction?}}`. Snapshot không đổi khi sửa catalog. Backend reprice + kiểm tra/reserve stock + tạo đơn trong transaction; nếu giá đổi trả409 và cart mới để khách xác nhận. Duplicate key trả cùng kết quả; không tạo đơn thứ hai. Frontend khóa thao tác giỏ trong request và mở khóa khi thất bại. Thanh toán pending không hiển thị “đã thanh toán”.

Hiện mock: CheckoutDraft có địa chỉ dạng chuỗi, `express` boolean và payment label; remote adapter cần form địa chỉ cấu trúc + lựa chọn từ `GET /shipping-methods`, `GET /payment-methods`. Phí demo30k/50k, miễn tiêu chuẩn từ1.5 triệu nằm trong BrandConfig. Không có coupon tính tiền ở giai đoạn hiện tại.

`GET /v1/me/orders`, `GET /v1/me/orders/:id`: ownership bắt buộc. `GET /v1/admin/orders` có query/status/sort/page; `PATCH /v1/admin/orders/:id/status` body `{status,version,reason?}` xác minh chuyển trạng thái hợp lệ và audit. Hủy đơn phải giải phóng kho/hoàn tiền theo backend; mock hiện chỉ đổi nhãn, không hoàn kho.

## Auth, profile và wishlist

`POST /auth/register`, `/auth/login`, `/auth/logout`, `/auth/password-reset`; `GET/PATCH /me`; `GET/POST/DELETE /me/wishlist`. Login response không đưa secrets vào URL hoặc storage không phù hợp. Forgot-password trả thông điệp không tiết lộ tài khoản tồn tại. Frontend hiện chỉ giữ UserProfile trong phiên, không kiểm chứng mật khẩu. AccountRepository đã có mock async và pending/error/retry. Thay binding bằng remote adapter, ánh xạ fieldErrors/session expiry khi tích hợp.

## Stylist

`POST /v1/ai/stylist/messages` body `{sessionId?, clientMessageId, text, preferences:{budget,size,color,style,occasion?}}`.

Response `{sessionId,message:{id,role,text,createdAt},recommendations:[{productId,sku,reason}],outfitTotal,disclosure}`. IDs/giá phải được backend đối chiếu catalog; adapter fetch/cache sản phẩm để tái dùng ProductCard. Không để LLM đặt giá/tồn kho. Streaming là tùy chọn; UI hiện chờ một reply với loading và retry. Retry dùng clientMessageId để tránh lặp tin trong server history. Timeout/cancel không suy ra AI đã dừng tính phí.

## Upload và Virtual Try-On

Sau khi có consent: `POST /v1/uploads/presign` body `{mimeType,byteSize,width,height,purpose:"tryon",consentVersion}` → `{imageAssetId,uploadUrl,requiredHeaders,expiresAt}`. Signed URL ngắn hạn, private object, allowlist MIME/size; backend xác minh bytes thật, pixel count, EXIF và quyền sở hữu sau upload. Bản demo không gọi endpoint này.

`POST /v1/ai/tryons` body `{imageAssetId,sku,consent:{accepted:true,policyVersion},clientJobId}` → `202 {id,status:"queued",createdAt}`.

`GET /v1/ai/tryons/:id` → `{id,status,queuedAt,startedAt?,finishedAt?,resultImage?:{id,url,expiresAt},error?:{code,message,retryable},retryAfterMs?}`. Lifecycle: queued → processing → succeeded/failed/cancelled. UI không đoán phần trăm; hiển thị tên giai đoạn. Poll có backoff, dừng khi terminal/rời route; hoặc SSE theo cùng event schema.

`POST /v1/ai/tryons/:id/cancel` là best-effort; `DELETE /v1/images/:id` thu hồi input, result và job liên quan theo chính sách đã chốt. `POST /v1/ai/tryons/:id/retry` có idempotency và quota server. Không cho job bị xóa sinh lại ảnh. Người dùng chỉ truy cập ảnh/job của mình; result URL không ghi log, không lưu dài hạn ở client. Backend trả hết hạn/xóa/không được phép bằng state rõ ràng.

Hiện mock chỉ có job id/status/error và placeholder result, giới hạn3 lần thử trong phiên. Khi nối thật cần thêm image-reference và async deletion state ở controller; không giữ nguyên lời hứa “rời trang sẽ xóa ảnh” nếu backend chưa xác nhận deletion/retention.

## Admin và nội dung

`GET/POST/PATCH/DELETE /v1/admin/products`, `PATCH /admin/inventory/:sku`, `GET /admin/customers`, CRUD `/admin/promotions`, `/admin/content`, read-only `/admin/ai/metrics`. Admin quyền riêng theo thao tác, mỗi thay đổi giá/kho/status có audit. Publish content là explicit mutation; bản nháp không tự đẩy lên storefront. Promotion phải có thời gian, điều kiện và server-calculated discount trước khi thêm ô mã giảm giá vào checkout.

## Mapping và kiểm thử tích hợp tiếp theo

| Contract Flutter hiện tại | Điểm nối |
|---|---|
| ProductRepository | catalog + admin CRUD; mock consumeStock không expose remote |
| CartRepository | cart cache + async mutations |
| OrderRepository | atomic checkout + order cache |
| StylistRepository | validated response → catalog cards |
| TryOnRepository | stream từ polling/SSE; thêm upload/deletion service |
| AccountRepository | login/register/profile/password-reset/logout async |
| AccountDetailsRepository | read/saveAddress/deleteAddress/setDefault/saveStyle async, trả AccountDetails snapshot |
| AdminState | thêm remote repository cho content/promotions |

Contract tests cần fixture success/empty/field error/401/403/409/429/timeout; checkout stale price/stock, duplicate key và navigation-in-flight; image deletion-in-flight và ownership; invalid recommendation IDs. Chưa có kiểm thử giao dịch, bảo mật hoặc provider API thật trong frontend demo này.

## Sổ địa chỉ và sở thích tự chọn

`domain/account_details.dart` bổ sung DeliveryAddress, StylePreferences, AccountDetails và AccountDetailsRepository. Mock giới hạn 5 địa chỉ, địa chỉ đầu là mặc định; xóa mặc định chuyển sang địa chỉ còn lại. Các mutation trả snapshot mới, lỗi không làm mất dữ liệu cũ. Adapter NestJS sau này có thể ánh xạ GET /me/preferences, CRUD /me/addresses, PATCH /me/addresses/:id/default và PATCH /me/preferences; đây chỉ là đề xuất contract, chưa có endpoint thật.

Provider hiện tạo repository mới khi đổi email tài khoản/signout; generation và identity guard từ chối completion cũ. Dữ liệu không dùng localStorage. Remote adapter cần ownership do server xác nhận, atomic default-address update, server validation và async error mapping. Checkout sao chép địa chỉ đã chọn vào draft/đơn, không giữ liên kết mutable với sổ địa chỉ. Sở thích chỉ do người dùng tự chọn, không suy đoán từ ảnh.
