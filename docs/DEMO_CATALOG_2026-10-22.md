# Đợt bổ sung 24 sản phẩm mẫu WEARLY

Ngày 22/10/2026, theo lựa chọn “Thêm 24 sản phẩm đa dạng hơn”, đã nhập dữ liệu
vào database local `wearly`. Đây là dữ liệu mẫu để thử mua hàng và quản trị.
Mô tả từng sản phẩm ghi rõ giá, chất liệu và tồn kho là thông tin mô phỏng.

| Nhóm | Sản phẩm | Biến thể |
| --- | ---: | ---: |
| Áo sơ mi | 4 | 16 |
| Váy & đầm | 5 | 20 |
| Áo khoác | 3 | 12 |
| Quần | 2 | 8 |
| Túi & balo | 4 | 4 |
| Giày | 6 | 30 |
| **Tổng** | **24** | **90** |

Giá từ 399.000 đến 1.490.000 VNĐ, tổng tồn kho khởi tạo 872 đơn vị. Mỗi sản phẩm
có một màu khớp ảnh; quần áo có size S–XL, giày có size 36–40 hoặc 40–44,
túi dùng Freesize. SKU có tiền tố `WRL-DEMO26-`. Không tạo đánh giá giả.

42 ảnh được nhập vào kho MinIO local và phục vụ qua endpoint catalog đã kiểm
tra hash. Giao diện dùng `catalog/images/<UUID>`, không tải ảnh từ nguồn ngoài
khi xem sản phẩm. Ảnh nguồn dùng dữ liệu minh họa từ
[DummyJSON](https://dummyjson.com/docs/products), [Fake Store API](https://fakestoreapi.com/)
và hai ảnh demo đã có trong dự án. Tên thương hiệu của dữ liệu nguồn được giữ
khi có; không có tuyên bố đây là hàng đang bán hoặc đại lý chính thức.

Danh sách, giá, size, tồn kho ban đầu, ID, đường dẫn ảnh local và nguồn ảnh:
[manifest nhập hàng](data/wearly-demo-products-2026-10-22.json).

## Cách nhập và bằng chứng

- Chỉ cho phép mục tiêu PostgreSQL localhost:5432/wearly và object store local.
- Tải, kiểm tra định dạng và chuyển định dạng lưu trữ ảnh trước khi nhập.
  Đọc lại bytes trong object store để đối chiếu SHA-256 trước khi công khai.
- Tạo sản phẩm, biến thể, tồn kho, lịch sử nhập kho và bản ghi ảnh trong một
  transaction Serializable. Không chạy lại seed hoặc reset database.
- Lịch sử tồn kho có lý do `LOCAL_DEMO_IMPORT_20261022`. Đây là thao tác nhập
  trực tiếp được người dùng yêu cầu; `importActorId` trong manifest là mã lịch
  sử của lượt nhập offline, không mạo danh tài khoản quản trị hoặc tạo tài khoản.
- So hash từng dòng cũ ở Product, ProductVariant, ProductImage, Category, Brand,
  Inventory, InventoryMovement, Order, Payment trước/sau: tất cả giữ nguyên.
  Các bản ghi kiểm thử có từ trước được giữ nguyên.
- Kiểm tra API toàn bộ 24 sản phẩm: giá, màu, size, tồn kho đúng; 90 biến thể
  khả dụng. Đọc toàn bộ 42 ảnh qua API và đối chiếu hash: đạt.
- Chrome ở 1440×1000 và 375×812: sản phẩm, giá, màu, lựa chọn size, nút thêm vào
  giỏ và ảnh local hiển thị; không có lỗi JavaScript. Đã xem ảnh chụp hai kích thước.
  Không tạo đơn hàng mới chỉ để kiểm tra hiển thị.

Script nhập, nguồn tải về, ảnh chụp, hash trước nhập và kết quả kiểm tra nằm tại
`.tools/catalog-import-20261022`, quyền chỉ chủ máy/SYSTEM. Script từ chối nhập
đè khi chỉ một phần slug đã tồn tại và không nhập thêm tồn kho khi đủ 24 slug
đã có. Không đưa khóa hoặc `.env` vào manifest.

Mở `http://localhost:8080/#/shop` và tải lại trang để thấy sản phẩm mới.
Quản trị vẫn quản lý các sản phẩm này qua màn hình sản phẩm/tồn kho hiện có.
