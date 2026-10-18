# PostgreSQL và Prisma

CLI, client, PostgreSQL adapter đều khóa **7.10.1**. Schema ở `backend/prisma/schema.prisma`; client generate vào `backend/src/generated/prisma`; PrismaService quản lý pool/connection/shutdown.

```mermaid
erDiagram
  User ||--o{ RefreshToken : sessions
  User ||--o{ Address : owns
  User ||--o| Cart : owns
  User ||--o{ Order : places
  User ||--o{ WishlistItem : saves
  User ||--o{ Review : writes
  User ||--o{ ImageAsset : owns
  User ||--o{ AIJob : requests
  Category ||--o{ Product : groups
  Brand ||--o{ Product : supplies
  Product ||--o{ ProductVariant : variants
  Product ||--o{ ProductImage : images
  Product ||--o{ WishlistItem : saved
  Product ||--o{ Review : reviewed
  ProductVariant ||--o| Inventory : stock
  ProductVariant ||--o{ CartItem : selected
  ProductVariant ||--o{ OrderItem : purchased
  ProductVariant ||--o{ AIJob : garment
  Inventory ||--o{ InventoryMovement : history
  Order ||--o{ InventoryMovement : changes
  Cart ||--o{ CartItem : contains
  Order ||--|{ OrderItem : snapshots
  Order ||--o| Payment : payment
  ImageAsset ||--o{ AIJob : input
  AIJob ||--o| TryOnResult : output
  AIJob ||--o| OutboxEvent : enqueue
  User { uuid id PK
    string email UK
    string passwordHash
    Role role
  }
  Product { uuid id PK
    string slug UK
    uuid categoryId FK
    uuid brandId FK
  }
  ProductVariant { uuid id PK
    uuid productId FK
    string sku UK
    decimal price
  }
  Inventory { uuid id PK
    uuid variantId FK,UK
    int quantity
    int version
  }
  Order { uuid id PK
    uuid userId FK
    string idempotencyKey
    decimal subtotal
    decimal shipping
    decimal total
    OrderStatus status
  }
  OrderItem { uuid id PK
    uuid orderId FK
    uuid variantId FK
    string sku
    decimal unitPrice
    int quantity
  }
  Coupon { uuid id PK
    string code UK
    decimal amount
    boolean active
  }
```

## Các bảng

| Nhóm | Bảng | Quy tắc |
|---|---|---|
| Tài khoản | User, RefreshToken, Address | UUID PK; email unique lowercase ở DTO; token chỉ SHA-256; partial unique index chỉ một địa chỉ mặc định/user |
| Catalog | Category, Brand, Product, ProductVariant, ProductImage | slug/SKU unique; unique (productId,size,color); ảnh unique (productId,position) |
| Kho | Inventory, InventoryMovement | 1 inventory/SKU; quantity>=0; version tăng sau mutation; movement delta/reason/order |
| Giỏ | Cart, CartItem | 1 cart/user; unique (cartId,variantId); quantity 1..99 |
| Đơn | Order, OrderItem, Payment | unique (userId,idempotencyKey); immutable item/address snapshot; 1 payment/order |
| Chuẩn bị mở rộng | Coupon, WishlistItem, Review | Chưa có service public; unique code, unique user/product; rating 1..5 |
| AI | ImageAsset, AIJob, TryOnResult, OutboxEvent | object keys private; verified/deleted/expiry; 1 result và 1 outbox/job |

Tổng cộng 22 model. Quan hệ n-n user/product qua WishlistItem và Review; cart/variant qua CartItem; order/variant qua OrderItem. Các foreign key đều có trong migration, không dùng chuỗi ID tự phát cho quan hệ.

Enum: Role(CUSTOMER,ADMIN), OrderStatus(PENDING,CONFIRMED,SHIPPED,DELIVERED,CANCELLED), PaymentStatus(PENDING,PAID,FAILED,REFUNDED,CANCELLED), AIJobStatus(PENDING,PROCESSING,COMPLETED,FAILED).

Tiền Decimal(14,0), VND nguyên; API truyền chuỗi chính xác. Timestamp UTC, createdAt/updatedAt trên thực thể thay đổi; log/snapshot chỉ có createdAt. Không chứa bytes ảnh, password/access/refresh token thô hay API key.

Indexes: email/SKU/slugs, product(active,createdAt,id), category/brand, variant(size,color,price), user/order chronology, order status, inventory movement chronology, AI status và outbox unpublished.

## Migrations và seed

- `20261018000000_init`: tạo 22 bảng, enum, PK/FK/unique/index.
- `20261018000100_constraints`: số lượng/giá/tổng đơn/rating và default address.
- `npm run prisma:deploy`: áp dụng migration đã commit, không reset.
- `npm run prisma:migrate -- --name descriptive_change`: tạo migration mới trong development.
- `npm run prisma:generate`: generate client riêng; Prisma 7 không tự chạy generate/seed sau migrate.
- `npm run prisma:seed`: 4 danh mục, Wearly brand, 32 sản phẩm và 256 SKU từ fixture Flutter; upsert với update rỗng, không đặt lại giá/tồn/tài khoản đã sửa.
- `npm run prisma:studio`: giao diện DB local. Không phơi Studio ra Internet.

Seed không tạo admin với mật khẩu mặc định. Tạo tài khoản qua API, sau đó developer có quyền database đổi role trong Prisma Studio khi cần kiểm thử quản trị.

## Tồn kho và đơn hàng

Cart chỉ kiểm tra tồn, chưa giữ hàng. Checkout dùng SERIALIZABLE, khóa transaction theo user/cart, đọc giá từ DB và so expectedSubtotal; cartVersion được hỗ trợ. Trừ inventory bằng update có điều kiện quantity>=requested, theo thứ tự UUID để giảm deadlock. Tất cả món, snapshot, payment PENDING, movements và xóa giỏ nằm chung transaction. Serialization conflict được retry giới hạn 5 lần.

Hủy chỉ nhận đơn PENDING thuộc user; thay trạng thái/version và hoàn stock+movement+payment CANCELLED trong một transaction. Request hủy lặp trả cùng đơn đã hủy; không hoàn lần thứ hai.

Idempotency key thuộc user, so request hash; key giống/request khác trả409. Retry giống trả snapshot ban đầu kể cả catalog đã sửa.

OrderItem giữ name,sku,slug,size,color,image,unitPrice,quantity. Xóa mềm catalog bằng active=false; không xóa SKU đã tham gia đơn. COD chưa có xác nhận thu tiền: giao hàng DELIVERED không tự đổi Payment thành PAID.

Đặc tả giữ hàng có thời hạn dành cho online payment chưa triển khai; cần Reservation, payment webhook signature/idempotency và expiry worker trước khi bật cổng thanh toán.
