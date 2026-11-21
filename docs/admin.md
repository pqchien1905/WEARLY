# Quản trị trực tuyến

Chạy backend bằng `npm run start:dev` trong `backend`. Từ thư mục gốc chạy `.\tools\frontend.ps1 api`; nếu đang đứng trong `frontend`, dùng `..\tools\frontend.ps1 api`.

Mở `http://localhost:8080/#/admin/login` để đăng nhập quản trị bằng **Tên đăng nhập** và mật khẩu. Tài khoản chủ máy local dùng tên `admin`; mật khẩu do chủ máy yêu cầu được đặt trực tiếp ở máy, không hardcode trong ứng dụng. Form quản trị không nhận email. Tên đăng nhập được chuẩn hóa chữ thường, gồm 3–64 ký tự chữ, số, dấu chấm, gạch dưới hoặc gạch ngang. Trang này không có đăng ký công khai; khách hàng vẫn đăng nhập bằng email.

Migration `20261022190000_admin_username` bổ sung tên đăng nhập duy nhất cho mỗi tài khoản. Các tài khoản cũ/đăng ký mới được cấp mã tự sinh; quản trị viên xem tên này ở **Nhân sự & quyền** để cung cấp cho nhân viên. Lệnh cấp quyền bên dưới cũng in tên đăng nhập. Email liên hệ không dùng trong yêu cầu đăng nhập quản trị; khôi phục qua email công khai chỉ dành cho khách hàng.

Khách hàng dùng `http://localhost:8080/#/login`. Tài khoản khách hàng và nhân sự là các bản ghi riêng, có ID, mật khẩu và phiên riêng. Form khách hàng chỉ nhận tài khoản CUSTOMER; ADMIN/MANAGER/WAREHOUSE/SUPPORT đăng nhập bằng tên đăng nhập tại trang quản trị. Tài khoản CUSTOMER bị từ chối tại API đăng nhập quản trị. Đổi mật khẩu khách hàng không thay mật khẩu hoặc xóa phiên quản trị đang mở.

Tài khoản chủ máy đã được tách: bản ghi cũ giữ email, mật khẩu khách hàng, ID và toàn bộ địa chỉ/giỏ hàng/đơn hàng; `admin` là bản ghi ADMIN mới. Email nội bộ của tài khoản này thuộc miền dự trữ `accounts.wearly.invalid`, không phải hộp thư và không dùng cho khôi phục mật khẩu. Chức năng Quên mật khẩu công khai chỉ áp dụng cho CUSTOMER. Quản trị viên cần liên hệ người vận hành để đặt lại mật khẩu quản trị; không dùng email khách hàng để thay mật khẩu `admin`.

Công cụ chuyển một tài khoản đang dùng chung thành hai tài khoản độc lập:

```powershell
$adminCredential = Get-Credential -UserName admin -Message 'Mật khẩu cho tài khoản quản trị riêng'
$adminCredential.GetNetworkCredential().Password | node tools/separate-admin-account.cjs customer@example.com admin 'Tên khách hàng'
Remove-Variable adminCredential
```

Mật khẩu chỉ đi qua stdin, không có giá trị mặc định. Công cụ yêu cầu tài khoản hiện tại đồng thời khớp email và tên đăng nhập ADMIN, khóa giao dịch cùng cơ chế quản lý nhân sự, lưu bản sao riêng trong `.tools/account-separation`, giữ nguyên dữ liệu mua hàng và hash mật khẩu khách hàng. Phiên/mã khôi phục cũ của tài khoản chung bị thu hồi; lịch sử thao tác quản trị cũ giữ nguyên actor ID. Lệnh chạy lại không ghi đè mật khẩu. Kiểm chứng công cụ trên DB riêng: `node tools/test-separate-admin-account.cjs`.

Phiên quản trị giữ qua tải lại bằng cookie HttpOnly; access token ở RAM. Dữ liệu vẫn được giữ trên PostgreSQL. Chế độ demo (`demo`) hiển thị rõ dữ liệu minh họa và không yêu cầu tài khoản quản trị thật; `run` và `api` đều dùng API.

## Giao diện và tra cứu quản trị (24/10/2026)

- Menu chia thành Cửa hàng, Sản phẩm & nội dung, Vận hành; chỉ hiện mục được cấp quyền. Thanh trên hiển thị trang hiện tại, tài khoản và vai trò nằm cuối menu. Màn hình nhỏ dùng menu ngăn kéo.
- Tổng quan ưu tiên tiền đã thu, tổng đơn, đơn chờ xác nhận và sản phẩm đang bật. Cảnh báo sắp hết (1–5) / hết hàng (0) chỉ tính SKU và sản phẩm đang bật; bấm cảnh báo mở đúng bộ lọc kho. Có 5 đơn mới nhất và phân bố trạng thái đơn lấy từ PostgreSQL, cùng phần đối soát và nhật ký có thể mở rộng. Các chỉ số tính toàn thời gian; không có phần trăm tăng trưởng giả.
- Sản phẩm, kho, đơn và khách hàng có tìm kiếm trên toàn bộ dữ liệu tại server, phân trang 20 bản ghi và bộ lọc trạng thái. Bộ lọc, từ khóa, số trang lưu trong URL; thay từ khóa hoặc bộ lọc trở về trang đầu, giữ được sau tải lại / Back. Desktop dùng bảng; màn hình hẹp dùng thẻ.
- API `GET /admin/{products|inventory|orders|users}` nhận thêm `q` (tối đa 100 ký tự) và `status`. Sản phẩm / khách: `active|hidden`; kho: `in_stock|low|out`; đơn: `PENDING|CONFIRMED|SHIPPED|DELIVERED|CANCELLED|RETURNED`. Bộ lọc sai loại trả 400. Tìm kiếm không phân biệt hoa thường, coi `%` và `_` là ký tự thường. Tên tiếng Việt vẫn cần dấu tương ứng.
- Sản phẩm tìm theo tên / slug / SKU / danh mục / thương hiệu; kho theo tên / SKU; đơn theo mã / UUID / tài khoản khách / tên sản phẩm; khách theo tên / email / số điện thoại. Khách hàng chỉ gồm role CUSTOMER, không trả hash mật khẩu hoặc token.
- Danh sách và tổng số bản ghi được đọc trong cùng transaction RepeatableRead. Tổng quan giữ nguyên phép tính tiền thu / hoàn / COD, bổ sung `activeProducts`, `lowStockVariants`, `outOfStockVariants`, `orderStatuses`, `recentOrders`, `generatedAt`. Không cần migration mới cho đợt này.

Tại máy phát triển, cấp quyền cho email đã đăng ký bằng:

```powershell
node tools/grant-admin.cjs email-cua-ban@example.com
```

Chạy từ root và dùng một tài khoản dành riêng cho nhân sự. Script dùng cấu hình PostgreSQL của backend, chỉ cập nhật tài khoản hiện có và thu hồi các phiên cũ khi đổi quyền. Sau chuyển quyền, tài khoản này chỉ đăng nhập qua trang quản trị. Nếu tài khoản đã có dữ liệu mua hàng cần giữ riêng, dùng công cụ tách tài khoản ở trên. Không tạo tài khoản/mật khẩu mặc định. Không sửa `.env` hoặc dùng script này cho người chưa được chủ cửa hàng cho phép.

## Các thao tác đã nối

- Tổng quan: số sản phẩm, đơn, đơn chờ xác nhận, khách hàng và tổng số lượng kho từ toàn database.
- Thay đổi gần đây trên trang tổng quan: lịch sử PostgreSQL, mới nhất trước, 20 mục/trang; có tải lại và trang trước/sau. Mỗi mục gồm thao tác, mã quản trị viên, mã bản ghi và thời gian theo múi giờ thiết bị. Không lưu nội dung request hoặc thông tin khách hàng vào lịch sử.
- Danh mục (`/#/admin/categories`): tìm kiếm/lọc/sắp xếp/phân trang tại server, thống kê, chi tiết, thêm mới và đổi tên; thương hiệu (`/#/admin/brands`) giữ danh sách phân trang và form chung. Tên tối đa 100 ký tự; slug gồm chữ thường không dấu, số và dấu gạch nối, duy nhất trong cùng loại. Slug cố định sau khi tạo, chưa có nghiệp vụ xóa. Danh mục mới chọn được trong form sản phẩm; chỉ hiện ở cửa hàng khi có sản phẩm đủ điều kiện công khai. UI gửi tên và thời điểm cập nhật đã đọc để phát hiện sửa đồng thời.
- Sản phẩm: danh sách phân trang, thêm/sửa metadata, chọn danh mục/thương hiệu có sẵn, bộ ảnh tối đa 20 ảnh và ẩn/hiện. Có tải ảnh từ máy cho sản phẩm đã lưu; hỗ trợ URL HTTPS công khai, asset bundled và ảnh catalog lưu trên server. Khi kết quả upload chưa xác định, tải lại bộ ảnh trước khi thao tác tiếp.
- Biến thể: tạo SKU với size/màu/giá; sửa giá và trạng thái bán. SKU/size/màu đã tạo không đổi định danh. SKU mới có tồn kho 0; nhập kho ở thao tác riêng.
- Tồn kho: tăng/giảm bằng số nguyên và lý do; gửi phiên bản đã đọc. Khi xung đột hoặc không xác định kết quả, tải lại trước khi thao tác tiếp; không tự gửi lặp lệnh tăng kho.
- Đơn: xem người nhận, sản phẩm, phí giao và tổng tiền đã chốt; chuyển PENDING → CONFIRMED → SHIPPED → DELIVERED, kiểm tra version. Giao xong không đồng nghĩa COD đã thu tiền.
- Khách hàng: danh sách, thống kê, chi tiết, lịch sử đơn, sửa thông tin liên hệ và khóa/mở khóa cho ADMIN/MANAGER. Không gửi hash mật khẩu/token tới Flutter. Quy tắc và kết quả kiểm thử ở phần khách hàng bên dưới.
- Nội dung (`/#/admin/content`): lưu bản nháp tiêu đề campaign và chính sách, sau đó **Xuất bản nội dung** riêng. Bản nháp không xuất hiện công khai. Sửa chưa lưu sẽ khóa nút xuất bản; xung đột phải tải lại bản hiện tại. Tiêu đề tối đa120, chính sách5000 ký tự; văn bản không tự thay đổi phí giao hàng hoặc nghiệp vụ đổi trả.
- Bộ sưu tập (`/#/admin/collections`): ADMIN/MANAGER thêm/sửa tên, mô tả, phong cách, thứ tự, ảnh bìa và ẩn/hiện. Sản phẩm tự cập nhật theo phong cách; mỗi phong cách chỉ có một bộ để tránh lặp. Ảnh bìa chọn từ sản phẩm có ảnh và biến thể đang bán trong cùng nhóm, hoặc tự động. Bộ trống chưa xuất hiện công khai. Slug cố định sau tạo; version bảo vệ lưu đồng thời, thay đổi có nhật ký. [Chi tiết và kiểm chứng](COLLECTIONS_COMPLETION_2026-10-23.md).

Các thao tác lưu metadata, SKU và tồn kho tách biệt; không trình bày một chuỗi nhiều request như một giao dịch nguyên tử. Form tạo sản phẩm mới mặc định ẩn. Sản phẩm cần bật hiển thị, có ảnh và ít nhất một biến thể đang bán để xuất hiện trên cửa hàng. Ẩn sản phẩm/biến thể giữ nguyên lịch sử đơn.

Khi sửa sản phẩm, Flutter chỉ PATCH các trường đã đổi kèm `expectedUpdatedAt`. Sửa tên/chất liệu không gửi lại bộ ảnh cũ; bộ ảnh chỉ được thay thế khi bạn sửa ảnh. Server từ chối phiên bản cũ với `409 PRODUCT_CONFLICT`; form yêu cầu tải lại trước khi lưu tiếp. Sửa giá/trạng thái SKU dùng cùng cơ chế. Trường phiên bản vẫn tùy chọn ở API để tương thích client cũ; client bỏ trường này không được bảo vệ khỏi ghi đè. Kho và trạng thái đơn dùng `expectedVersion` để từ chối dữ liệu cũ.

Nhật ký ghi cùng transaction với thao tác thành công trên sản phẩm, SKU, danh mục, thương hiệu, tồn kho và trạng thái đơn. Khi ghi nhật ký lỗi, thay đổi nghiệp vụ cũng rollback. Request bị từ chối không tạo sự kiện thành công. Mã actor lấy từ phiên đã xác thực, không nhận từ form. Đây là lịch sử thao tác ứng dụng, chưa phải kho kiểm toán chống sửa đổi bởi người có quyền database.

Khuyến mãi, theo dõi vận hành / AI, đối soát COD, hỗ trợ, theo dõi thư và phân quyền nhân sự đã có trang dùng API. Các tích hợp bên ngoài vẫn phụ thuộc cấu hình provider của môi trường; trang vận hành hiển thị trạng thái cấu hình. Chưa kiểm chứng native Android/iOS hoặc môi trường production. Máy cài mới cần chạy migration theo hướng dẫn setup; không seed lại database nghiệp vụ.

## Kiểm chứng

### Hoàn thiện quản lý kho (24/10/2026)

**Nguồn dữ liệu và quy tắc giữ nguyên**

`Inventory.quantity` là nguồn chính thức theo `ProductVariant`, được trừ ngay khi checkout thành công. Giỏ hàng không giữ hàng; xác nhận/giao đơn không trừ thêm. Hủy đơn, giao hàng hoàn về và nhận hàng khách trả dùng transaction/version và cơ chế chống ghi lặp hiện có. Đây là số lượng khả dụng sau khi trừ đơn, không phải số hàng vật lý còn trong nhà kho khi đơn chưa xuất đi. Kiểm kê phải nhập phần còn có thể bán, đã trừ hàng dành cho đơn hiện có; giao diện ghi rõ điều này.

Không có cột reserved, giá vốn hoặc ngưỡng riêng từng SKU trong schema hiện tại. Không dựng chỉ số giữ hàng/giá trị hàng tồn, không thêm bảng/cột/dependency. Đợt hoàn thiện bổ sung migration chỉ tạo index tra cứu audit theo target/action. Ngưỡng sắp hết giữ nguyên **1–5**, hết hàng **0**. Sản phẩm/SKU ẩn vẫn có thể nhập, xuất và kiểm kê; thao tác kho không tự bật bán. Sản phẩm chưa có biến thể phải tạo SKU qua trang sản phẩm trước.

**Lỗi gốc và phần đã hoàn thiện**

- Trang kho cũ dùng danh sách quản trị chung, ít thông tin và chưa có chi tiết/lịch sử. Thay route bằng workspace riêng, tái sử dụng token, card, bảng/thẻ, thống kê, skeleton, thông báo và dialog hiện có. Hiển thị ảnh/tên/SKU, màu/size, danh mục, số khả dụng, trạng thái, cập nhật UTC+7; responsive desktop/tablet/mobile và chữ phóng lớn.
- API danh sách trước chỉ có q/status và sắp ngày tạo. Bổ sung lọc danh mục, sản phẩm, khoảng lượng, bật/ẩn, thiếu bản ghi; sort SKU/tên/ngày/lượng; phân trang 20/50/100. Thực hiện lọc/count/sort tại DB, tải quan hệ theo lô cho đúng trang. Tổng và trang đọc cùng transaction RepeatableRead. Bỏ nhánh truy vấn kho trùng trong service cũ.
- Thêm thống kê DB phân biệt SKU có kho, số sản phẩm có SKU trong kho, tổng đơn vị khả dụng (kể cả SKU ẩn), SKU còn/sắp hết/hết, SKU chưa có kho và đơn vị thuộc sản phẩm/SKU bật. Thống kê toàn bộ kho, không chỉ kết quả lọc. Dữ liệu SKU thiếu kho trả quantity/id null, không giả làm 0; có luồng xác nhận khởi tạo 0 rồi nhập kho thực tế. Khởi tạo đồng thời/lặp không reset lượng đang có.
- API điều chỉnh trước chấp nhận delta 0 và lý do toàn khoảng trắng. Đã chặn 0, trim lý do, giữ giới hạn ±1.000.000/lần; chặn âm và tràn số nguyên PostgreSQL. Trong transaction, khóa tài khoản và kiểm tra lại active/quyền `inventory.write`. Cập nhật lượng/version, biến động và audit cùng transaction; lỗi audit rollback tất cả.
- Nhập/xuất/kiểm kê dùng cùng endpoint delta + expectedVersion đang có. Kiểm kê tính chênh lệch từ bản đang xem, không ghi đè lượng tuyệt đối khi phiên bản đã thay đổi. Dialog hiển thị trước→sau, yêu cầu lý do, validation, khóa nút lưu khi request chạy. Xung đột/kết quả chưa chắc chắn buộc tải lại; không tự gửi lại lệnh tăng/giảm. Sửa thông báo VERSION_CONFLICT dùng chung để lỗi kho không bị mô tả nhầm là lỗi chuyển trạng thái đơn.
- `InventoryMovement` đã tồn tại nhưng thiếu API đọc và liên kết audit. Bổ sung lịch sử chỉ đọc theo từng SKU, phân trang, lọc ngày UTC+7/tăng/giảm/thủ công/đặt/hủy/hoàn; link về đơn. Ghi `movementId` vào JSON audit cho điều chỉnh thủ công mới để lấy actor và lượng trước/sau chính xác. Không suy ra actor theo timestamp, không tính số dư giả từ sổ cũ thiếu số dư mở đầu. Biến động cũ/tự động chưa có liên kết vẫn hiển thị delta, lý do, thời gian và đơn, để trống phần không có dữ liệu.
- Refresh sau ghi làm mới danh sách/chi tiết/thống kê/lịch sử kho, sản phẩm và catalog trong cùng phiên. `WAREHOUSE` dùng trang kho mà không gọi API taxonomy/catalog bị cấm. ADMIN/MANAGER/WAREHOUSE theo đúng quyền hiện có; SUPPORT/CUSTOMER bị chặn ở server và UI.

**API bổ sung, tương thích**

| Endpoint | Công dụng |
| --- | --- |
| `GET /admin/inventory` | Giữ envelope items/total/page/limit và các trường hàng cũ; thêm quan hệ phục vụ UI |
| `GET /admin/inventory/summary` | Thống kê và danh mục cho người có inventory.read |
| `GET /admin/inventory/:id` | Chi tiết kho/SKU/sản phẩm |
| `GET /admin/inventory/:id/movements` | Lịch sử chỉ đọc, lọc và phân trang |
| `POST /admin/inventory/:id/adjust` | Endpoint cũ, giữ body delta/expectedVersion/reason, tăng validation và kiểm tra quyền trong transaction |
| `POST /admin/inventory/variants/:id/initialize` | Tạo bản ghi thiếu với lượng 0; lặp trả lại bản ghi hiện tại, không reset |

List query: `q` tối đa 100 ký tự (tên không dấu, SKU, màu, UUID sản phẩm/SKU; escape `%`, `_`, `\`), `categoryId`, `productId` UUID; `status=in_stock|low|out`; `visibility=all|active|hidden`; `record=existing|missing`; `minQuantity`, `maxQuantity` từ 0 đến 2.147.483.647; `sort=updated|newest|sku_asc|name_asc|quantity_asc|quantity_desc`; `page`, `limit` tối đa 100. URL status cũ không truyền visibility tiếp tục chỉ xét sản phẩm/SKU bật, giữ hành vi link cảnh báo từ Dashboard. Trang kho ghi rõ lựa chọn hiển thị; các thẻ số liệu toàn kho gửi visibility=all. SKU chưa có kho không thể đồng thời lọc số lượng/trạng thái lượng. ID phụ giữ phân trang ổn định.

History query: `page`, `limit`, `type=in|out|admin|order|cancel|return`, `from`, `to` dạng YYYY-MM-DD, bao gồm hai đầu theo UTC+7. Chọn sản phẩm qua danh sách/tìm UUID hoặc “Các SKU cùng sản phẩm”, rồi xem lịch sử của SKU tương ứng. Không có endpoint sửa/xóa lịch sử.

**Kiểm chứng thực tế**

| Luồng | Kiểm chứng |
| --- | --- |
| Danh sách, sort/filter/page | PostgreSQL, Flutter, Chrome; literal search, quantity range, SKU ẩn/thiếu, URL/reload |
| Nhập/xuất/kiểm kê | POST thật + DB; delta/version/audit chính xác; không cho âm, 0, số lẻ, tràn int hoặc lý do trống |
| Đồng thời và rollback | Hai actor cùng version: một 201, một 409; gửi lại không cộng lặp; audit lỗi không đổi kho hoặc tạo movement |
| Kết quả request chưa rõ | Widget mô phỏng server đã ghi nhưng response 503: không gửi lại; tải lại hiển thị số lượng thật |
| Khởi tạo thiếu kho | Hai request trả cùng ID; chạy lại sau nhập giữ nguyên lượng; không tạo biến động hàng giả |
| Sản phẩm/cửa hàng | Lượng trong API product, API public và trang sản phẩm khớp sau điều chỉnh |
| Checkout/hủy | Tạo đơn thật ở DB test trừ một lần; điều chỉnh kho sau đặt rồi hủy lặp giữ nguyên phần điều chỉnh, chỉ hoàn hàng một lần; lịch sử có order code thật |
| Bán hàng đồng thời/hoàn trả | Hồi quy commerce (khách cùng mua SKU cuối), returns (nhận hoàn từng phần/lặp), shipments (giao/hoàn), admin-products và staff |
| Responsive/quyền | Flutter 360/768/1440 và chữ 150%; Chrome 375/768/1440; ADMIN và WAREHOUSE đăng nhập thật; SUPPORT/CUSTOMER/không token bị chặn ở API |

Kết quả tự động: **109 kiểm thử Flutter riêng biệt** qua 10 suite (lượt chung 108 test; suite kho chạy lại sau bổ sung tình huống response không chắc chắn có 13/13 test); **68 kiểm thử PostgreSQL riêng biệt** qua 8 suite (`admin-inventory`, `admin-query`, `commerce`, `returns`, `shipments`, `admin-products`, `staff`, `admin`). Suite kho mới có 7 test. Suite staff cập nhật expectation audit để kiểm tra movementId mới; vẫn kiểm tra quantity/version trước và sau. `flutter analyze`, Flutter web release build, backend build và ESLint đều qua; log ở `.tools/inventory-baseline/`.

Chrome: `tools/verify-admin-inventory-browser.cjs`, frontend mặc định 8080 hoặc `ADMIN_TEST_BASE=http://localhost:5173` cho bản release riêng. Script tạo 23 SKU, tài khoản/category/brand/product riêng; chỉ thay đổi và dọn các ID của lượt chạy. Browser không checkout/gửi mail: đơn phục vụ điều hướng là fixture trực tiếp, checkout thật nằm trong test PostgreSQL `_test` đã tắt outbound. Ảnh, report và log ở `.tools/inventory-acceptance/`.

Lượt Chrome cuối: **4 nhóm luồng đều qua**, `errors=[]`, `unexpectedResponses=[]`, `cleaned=true`; kiểm tra thêm bộ lọc hết/sắp hết vẫn giữ phạm vi “Tất cả SKU”, không vô tình đổi sang SKU đang bán. Đăng nhập thật bằng ADMIN rồi WAREHOUSE, điều chỉnh và tải lại trang đều khớp database. Sau dọn dữ liệu thử, kiểm tra DB phát triển ghi nhận **0 sản phẩm/category/tài khoản QA còn lại, 0 bản ghi kho âm, 0 SKU thiếu kho**; kết quả ở `.tools/inventory-acceptance/data-check.json`. Đây là kiểm tra trạng thái tại thời điểm chạy, không phải cam kết cho mọi thay đổi trực tiếp vào DB trong tương lai.

**Danh sách file đợt kho**

Tạo mới (8):

- `backend/src/modules/admin/dto/admin-inventory-query.dto.ts`
- `backend/src/modules/admin/inventory-workspace.ts`
- `backend/test/admin-inventory.e2e-spec.ts`
- `frontend/lib/features/admin/remote/inventory_page.dart`
- `frontend/lib/features/admin/remote/inventory_detail.dart`
- `frontend/lib/features/admin/remote/inventory_widgets.dart`
- `frontend/test/admin_inventory_workspace_test.dart`
- `tools/verify-admin-inventory-browser.cjs`

Chỉnh sửa (14):

- `backend/src/modules/admin/admin.controller.ts`
- `backend/src/modules/admin/admin.service.ts`
- `backend/src/modules/admin/dto/admin.dto.ts`
- `backend/src/modules/admin/audit-snapshot.ts`
- `backend/test/staff.e2e-spec.ts`
- `frontend/lib/app/app.dart`
- `frontend/lib/data/remote_admin.dart`
- `frontend/lib/features/admin/remote/admin_providers.dart`
- `frontend/lib/features/admin/remote/admin_pages.dart`
- `frontend/lib/features/admin/remote/admin_widgets.dart`
- `frontend/lib/features/admin/remote/inventory_actions.dart`
- `frontend/test/admin_overview_test.dart`
- `frontend/test/remote_admin_ui_test.dart`
- `docs/admin.md`

Không xóa file. Giữ nguyên thay đổi của các công việc trước; bản sao trước sửa/log nằm trong `.tools/` (ignored).

**Giới hạn**

Chưa benchmark kho rất lớn hoặc thử thiết bị mobile thật/native/production. Audit JSON chưa có index riêng cho movementId: truy vấn lịch sử tải theo trang và theo lô nhưng cần đo/đánh index phù hợp nếu audit tăng lớn. Cảnh báo deprecation `pg` hiện hữu vẫn còn. Không có đẩy tồn kho thời gian thực giữa các phiên độc lập: phiên quản trị hiện tại refresh sau ghi, phiên khác cần tải lại; ghi kho/checkout luôn kiểm tra dữ liệu hiện tại và được bảo vệ bởi version/transaction. Ledger cũ thiếu actor/số dư không được backfill suy đoán. Không có cấu hình ngưỡng từng SKU hay giá trị kho theo giá vốn.

Giữ server Flutter cổng **8080** của chủ máy; nhấn **R** tại terminal Flutter rồi **Ctrl+F5** để nhận source mới. Backend chạy build mới tại cổng 3000. Không mở thêm server trên cổng 8080 đang dùng.

### Hoàn thiện quản lý sản phẩm (24/10/2026)

Giữ Flutter/Riverpod/go_router, NestJS/Prisma/PostgreSQL và kho ảnh S3 hiện có. Không thêm dependency hoặc bảng/cột; phần xóa sản phẩm bổ sung một giá trị enum nhật ký bằng migration. UI dùng font, token, heading, card, trạng thái, thông báo, hộp thoại và thống kê của các trang quản trị hiện có.

**Giao diện và chức năng đã triển khai**

- Danh sách `/#/admin/products`: bảng desktop, thẻ ở màn hình hẹp/chữ lớn; ảnh, tên/UUID, số SKU, danh mục, khoảng giá SKU đang bán, tồn kho, trạng thái hiển thị, thời gian cập nhật UTC+7 và menu thao tác. Có skeleton, retry, rỗng, lỗi, phân trang 20/50/100 và giữ bộ lọc trên URL khi tải lại/quay về từ chi tiết.
- Tìm tên có/không dấu, slug, SKU, UUID, tên danh mục/thương hiệu; lọc danh mục, thương hiệu, giá, bật/ẩn, tồn kho. Sắp xếp ngày tạo/cập nhật, tên, giá, tồn kho. Khoảng giá áp dụng cho cùng một SKU đang bán. Ký tự `%`, `_`, `\` được tìm như ký tự thường, không trở thành wildcard.
- Chi tiết `/#/admin/products/:id`: tổng quan hai cột trên desktop, xếp dọc trên mobile; bộ ảnh chọn được từng ảnh, xem lớn, chuyển ảnh bằng nút/phím trái-phải và phóng 1–4 lần bằng nút/cảm ứng. Giá, tồn kho đang bán và tổng kho được phân biệt; có mô tả/thuộc tính, điều kiện hiển thị, mã sao chép và ngày tạo/cập nhật UTC+7.
- Biến thể trên trang chi tiết dùng bảng desktop, thẻ khi màn hình hẹp/chữ lớn. Có tìm SKU/màu/kích cỡ, lọc trạng thái và tồn kho kết hợp; tổng kho/số biến thể của sản phẩm không đổi theo bộ lọc. Sửa giá/trạng thái, thêm SKU và điều chỉnh kho dùng lại các hộp thoại có kiểm tra phiên bản. Nút nhảy tới từng phần, chỉnh sửa, ẩn/hiện và xóa có xác nhận; quay về danh sách giữ bộ lọc. Link cửa hàng chỉ xuất hiện khi sản phẩm đáp ứng điều kiện công khai.
- Form tạo/sửa: thông tin cơ bản và thiết lập bán hàng, lỗi từng trường, trạng thái đang lưu, chặn nhấn lưu nhiều lần. Lỗi slug/SKU/biến thể trùng giữ bản nháp để sửa. Lỗi xung đột hoặc kết quả ghi không chắc chắn yêu cầu kiểm tra/tải lại dữ liệu; không tự gửi lại lệnh tạo.
- Trang chỉnh sửa dùng hai cột trên desktop: thông tin/phân loại bên trái, ảnh bìa và bản xem trước cập nhật theo nội dung đang nhập cùng thiết lập bán hàng bên phải. Màn hình nhỏ xếp một cột. Có nút nhảy tới từng phần, trạng thái chưa lưu, hủy bản nháp có xác nhận và xác nhận rời trang qua các nút điều hướng trong form.
- Bộ ảnh có nút chọn trực tiếp ảnh bìa. Biến thể hiển thị bảng trên desktop và thẻ trên mobile; quản lý giá/trạng thái và điều chỉnh kho riêng. Cần lưu hoặc hủy bản nháp thông tin trước khi sửa biến thể. Lỗi validation được cuộn tới trường cần sửa; lỗi API/tải ảnh được đưa vào vùng nhìn thấy.
- Ảnh: upload JPEG/PNG tối đa 8 MB, preview, đổi URL, mô tả/màu, sắp xếp ảnh bìa, bỏ ảnh có xác nhận. Giữ validation kích thước và nội dung ảnh, re-encode, bỏ metadata, khóa idempotency và endpoint ảnh an toàn đã có. Bỏ ảnh khỏi sản phẩm không xóa file đã được đơn hàng tham chiếu.
- Tái sử dụng thao tác SKU và kho ở cả chi tiết/editor. Giá bán là số nguyên VND không âm, SKU mới có kho 0; nhập/xuất kho cần lý do và phiên bản. SKU/size/màu giữ định danh sau tạo theo nghiệp vụ hiện có.
- Xóa sản phẩm tại menu ba chấm trên danh sách, có xác nhận và nút xóa màu đỏ. ADMIN/MANAGER được xóa vĩnh viễn sản phẩm chưa có đơn hàng, lịch sử kho, đánh giá, lượt thử đồ hoặc mục giỏ hàng. Server kiểm tra phiên bản và các liên kết trong transaction; sản phẩm có dữ liệu liên quan trả `409 PRODUCT_IN_USE`, UI hướng dẫn dùng “Ẩn sản phẩm”. Xóa thành công làm mới danh sách/thống kê/cửa hàng, giữ bộ lọc và chuyển về trang hợp lệ nếu trang cuối hết sản phẩm.
- Xóa sản phẩm đồng thời xóa các biến thể, tồn kho chưa có lịch sử, dòng bộ ảnh và mục yêu thích; ảnh bìa bộ sưu tập trở về lựa chọn tự động. File ảnh catalog được giữ theo cơ chế hiện có. Có nhật ký `PRODUCT_DELETED`; migration `20261024140000_product_deletion` bổ sung loại nhật ký này. Không có chức năng khôi phục sản phẩm đã xóa.
- Database chỉ có một giá trên mỗi SKU, một mô tả sản phẩm; chương trình khuyến mãi tiếp tục dùng module hiện có.

**API, dữ liệu và lỗi gốc đã sửa**

| API | Hành vi |
| --- | --- |
| `GET /admin/products` | Lọc, sắp xếp, phân trang ở PostgreSQL; giữ response cũ, thêm `summary` trên từng sản phẩm |
| `GET /admin/products/summary` | Tổng sản phẩm, bật/ẩn, đủ điều kiện công khai, sắp hết/hết hàng, số danh mục từ database |
| `GET /admin/products/:id` | Chi tiết và các quan hệ ảnh, danh mục, thương hiệu, SKU, kho |
| `POST /admin/products`, `PATCH /admin/products/:id` | Validation, chuẩn hóa, lỗi slug trùng rõ ràng, transaction/audit, kiểm tra phiên bản khi PATCH |
| `DELETE /admin/products/:id` | Quyền `catalog.write`, body bắt buộc `expectedUpdatedAt`; trả `{id, deleted: true}`, 404 nếu không còn tồn tại, 409 nếu phiên bản cũ hoặc có dữ liệu liên quan |
| `POST /admin/skus`, `PATCH /admin/skus/:id` | Chặn SKU/size-màu trùng, khoảng trắng, giá âm; kiểm tra phiên bản khi sửa |
| Upload ảnh và điều chỉnh kho hiện có | Dùng lại endpoint/idempotency/version; upload tăng phiên bản sản phẩm để ngăn form cũ xóa ảnh vừa tải |

Query sản phẩm: `q` tối đa 100 ký tự; `categoryId`, `brandId` UUID; `status=active|hidden`; `stock=in_stock|low|out|no_variants`; `visibility=published|incomplete`; `minPrice`, `maxPrice` chuỗi số nguyên tối đa 14 chữ số; `sort=newest|oldest|updated|name_asc|name_desc|price_asc|price_desc|stock_asc|stock_desc`; `page`, `limit` tối đa 100. Query sai hoặc khoảng giá đảo ngược trả 400. ID sắp xếp phụ giữ thứ tự ổn định; sản phẩm không có giá được xếp sau.

Danh sách/tổng dùng cùng transaction RepeatableRead, truy vấn aggregate tại DB và tải quan hệ theo lô cho đúng trang, không tải mọi sản phẩm về Flutter để lọc. Giữ relations response để không phá client hiện có. Kiểm tra `catalog.read`/`catalog.write` tại server; hiện chỉ ADMIN/MANAGER có quyền catalog. Các giao dịch ghi sản phẩm/SKU/upload khóa và kiểm tra lại trạng thái/quyền actor, cùng cơ chế khóa tài khoản đang dùng.

Thống kê là toàn bộ catalog, không phải riêng kết quả lọc. “Đang hiển thị” = sản phẩm bật + có ảnh + có SKU đang bán. “Có SKU sắp hết” = sản phẩm bật và có SKU đang bán còn 1–5; “Hết hàng” = sản phẩm bật, có SKU đang bán nhưng tổng kho SKU bán bằng 0. Kho SKU ẩn không tính vào giá/kho bán. Sản phẩm hết hàng vẫn có thể xuất hiện ở cửa hàng theo quy tắc hiện có.

Đã sửa thiếu trang chi tiết, bộ lọc/sắp xếp chỉ giới hạn ở danh sách chung, lỗi báo trùng khó hiểu, thiếu xác nhận bỏ ảnh, thiếu bảo vệ ghi đè metadata/SKU và nguy cơ form cũ thay bộ ảnh sau upload. Lỗi tìm `%` từng khớp mọi UUID đã sửa bằng so sánh ID chính xác. Giữ logic checkout trừ kho, hủy/hoàn kho có kiểm soát và snapshot đơn; không thay giá/tên/ảnh đã chốt khi sửa catalog.

**Kiểm thử**

- Đợt hoàn thiện trang chi tiết: 49 test Flutter qua hai suite sản phẩm/API UI quản trị, gồm 4 test mới về ảnh/phóng ảnh/bàn phím, bộ lọc kết hợp và sửa đúng SKU, dữ liệu trống ở màn hình nhỏ/chữ 150%, xóa từ chi tiết và giữ bộ lọc khi quay về. Kiểm tra trình duyệt tại 375/768/1440 px với `tools/verify-product-detail-browser.cjs`; sản phẩm được yêu cầu chỉ được đọc, mọi thao tác ghi dùng fixture riêng. Ảnh trước/sau và báo cáo ở `.tools/product-detail-acceptance/`.
- Bổ sung xóa sản phẩm: 9 test PostgreSQL của `admin-products`, 45 test Flutter của `admin_products_workspace_test` và `remote_admin_ui` qua. Kiểm tra phân quyền, phiên bản bắt buộc/cũ, xóa đồng thời, cascade, giữ từng loại dữ liệu liên quan, hủy xác nhận/chặn nhấn lặp và phân trang sau xóa. Browser dùng `tools/verify-product-deletion-browser.cjs`, chỉ xóa fixture riêng; log và ảnh ở `.tools/product-deletion-acceptance/`.
- Đợt chỉnh sửa toàn bộ editor: 42 test Flutter thuộc `admin_products_workspace_test.dart` và `remote_admin_ui_test.dart`, phân tích tĩnh và build web release qua. Ba test mới kiểm tra preview/hủy bản nháp, xác nhận nút quay về và sửa đúng SKU trong bảng desktop. Chrome qua 5 nhóm kiểm tra bằng `tools/verify-product-editor-browser.cjs` trên preview release và phiên Flutter tại cổng 8080 sau khi nạp mã mới; ảnh 375/1440 px và log trong `.tools/product-editor-acceptance/`. Sản phẩm tại link yêu cầu chỉ được đọc; các lượt ghi dùng sản phẩm/tài khoản kiểm thử riêng và dọn sau khi chạy.
- **101 test Flutter, 11 suite, không skip**: sản phẩm, đơn, khách hàng, tổng quan, API/UI quản trị, phân quyền, mua hàng, catalog, upload và đọc catalog qua API/PostgreSQL đang chạy. Suite sản phẩm có 16 test, gồm 360/768/1440 px, chữ 150%, SKU dài, bộ lọc/URL, validation, chống lưu lặp, stale metadata/SKU, ảnh bìa/xác nhận bỏ ảnh, phân quyền, retry/rỗng/404 chi tiết/editor.
- **90 test backend, 12 suite**: `admin-query`, `admin`, `catalog-integrity`, `catalog-publication`, `admin-products`, `commerce`, `returns`, `refunds`, `admin-orders`, `admin-customers`, `staff`, `catalog-upload`. PostgreSQL riêng `_test`; suite upload dùng S3 cục bộ với bucket test. `admin-products` chạy lại sau sửa tìm ký tự `%`: 6/6 qua. Checkout → sửa sản phẩm/giá/ẩn → đọc lịch sử → hủy lặp đã xác nhận giá lịch sử giữ nguyên và kho chỉ hoàn một lần.
- `flutter analyze`, ESLint, backend build và Flutter web release build đều qua; log ở `.tools/products-baseline/`. Không có thay đổi dependency/schema trong đợt này.
- Chrome thật: `tools/verify-admin-products-browser.cjs`, đặt `ADMIN_TEST_BASE=http://localhost:5173` để chạy preview release mà không chiếm cổng Flutter 8080. Tạo dữ liệu kiểm thử có marker riêng, chỉ dọn ID/ảnh/tài khoản của lượt chạy trong `finally`. Browser không checkout/gửi mail; fixture đơn tạo trực tiếp để xem lịch sử, checkout được kiểm tra ở suite PostgreSQL cách ly. Báo cáo từng luồng, lỗi console/API và ảnh 375/768/1440 lưu trong `.tools/products-acceptance/`.
- Lượt Chrome cuối: **5 nhóm luồng đều qua**, `errors=[]`, `unexpectedResponses=[]`, `cleaned=true`. Bao gồm đăng nhập/lọc/phân trang/reload; tạo/SKU/kho; upload S3/công khai; thay giá/tên/ảnh và lịch sử đơn/khách; responsive/xung đột/tải lại/ẩn. Script đã xác nhận giá trị input sau reload từ dữ liệu phiên khác. Những lần chạy đầu có lỗi selector kiểm thử (menu Danh mục trùng tên sidebar, vai trò hộp thoại Flutter và giá trị input ngoài viewport); đã sửa script và chạy lại toàn bộ thành công.

**File của đợt sản phẩm** (các thay đổi từ công việc khác trong workspace được giữ nguyên)

Tạo mới:

- `backend/src/modules/admin/catalog-write.ts`
- `backend/src/modules/admin/product-list.ts`
- `backend/src/modules/admin/dto/admin-products-query.dto.ts`
- `backend/test/admin-products.e2e-spec.ts`
- `frontend/lib/features/admin/remote/products_page.dart`
- `frontend/lib/features/admin/remote/product_detail.dart`
- `frontend/lib/features/admin/remote/product_widgets.dart`
- `frontend/test/admin_products_workspace_test.dart`
- `tools/verify-admin-products-browser.cjs`

Chỉnh sửa:

- `backend/src/modules/admin/admin.controller.ts`
- `backend/src/modules/admin/admin.service.ts`
- `backend/src/modules/admin/dto/admin.dto.ts`
- `backend/src/modules/catalog-media/catalog-media.service.ts`
- `backend/test/catalog-upload.e2e-spec.ts`
- `frontend/lib/app/app.dart`
- `frontend/lib/data/remote_admin.dart`
- `frontend/lib/features/admin/remote/admin_pages.dart`
- `frontend/lib/features/admin/remote/admin_providers.dart`
- `frontend/lib/features/admin/remote/admin_widgets.dart`
- `frontend/lib/features/admin/remote/product_editor.dart`
- `frontend/test/admin_overview_test.dart`
- `frontend/test/remote_admin_ui_test.dart`
- `docs/admin.md`

Không xóa file source. Các bản sao trước sửa, script hỗ trợ và log/ảnh build/kiểm thử nằm trong `.tools/` đã được ignore.

**Giới hạn kiểm chứng**

Chưa benchmark catalog quy mô production, chưa kiểm thử trình duyệt trên thiết bị mobile thật hoặc native Android/iOS. Cảnh báo deprecation của `pg` về truy vấn trên kết nối đang bận vẫn xuất hiện; chưa nâng Prisma/pg trong đợt này. API PATCH giữ phiên bản tùy chọn để tương thích: client cũ không gửi `expectedUpdatedAt` vẫn có thể ghi đè; UI mới luôn gửi phiên bản của dữ liệu thật. Không coi kiểm thử local là chứng nhận production.

Giữ phiên Flutter của chủ máy tại **8080**. Nhấn **R** trong terminal Flutter, sau đó **Ctrl+F5** ở trình duyệt để nhận source mới; không chạy thêm `frontend.ps1 api` trên cổng đang được sử dụng. API cổng 3000 phải chạy build mới hoặc watch.

### Hoàn thiện quản lý khách hàng (24/10/2026)

Trang `/#/admin/customers` và `/#/admin/customers/:id` dùng dữ liệu PostgreSQL qua API hiện có. Giữ Flutter/Riverpod/go_router, NestJS/Prisma, font và token của Admin Dashboard; không thêm thư viện, bảng, cột hoặc migration trong đợt khách hàng này.

**Giao diện và thao tác**

- Bảng desktop có mã khách (UUID rút gọn, xem/copy đầy đủ tại chi tiết), họ tên, email, số điện thoại, ngày đăng ký UTC+7, số đơn và trạng thái. Màn hình hẹp chuyển sang thẻ; email dài không đẩy vỡ bảng. Các thẻ thống kê có chiều cao đồng bộ.
- Tìm tên/email/điện thoại/UUID đầy đủ; lọc hoạt động/đã khóa, đã/chưa có đơn, đăng ký 30 ngày gần nhất. Sắp xếp mới/cũ, tên A–Z/Z–A, nhiều đơn nhất. Phân trang 20/50/100 tại server, thứ tự có ID làm tiêu chí phụ để ổn định. URL giữ tìm kiếm/bộ lọc/trang khi reload hoặc quay lại từ chi tiết.
- Chi tiết hiển thị thông tin liên hệ, thống kê mua hàng, lịch sử đơn phân trang và liên kết sang chi tiết đơn. Quay từ đơn về khách vẫn giữ trang lịch sử và bộ lọc danh sách. Trang đơn hỗ trợ lọc đúng `customerId`, không suy đoán theo email hoặc tên.
- Form sửa chỉ gửi trường đã đổi, có validation và giữ bản nháp khi trùng email/điện thoại. Khóa/mở khóa có xác nhận, khóa thao tác khi request đang chạy; lỗi xung đột yêu cầu tải lại. Có loading, empty state, retry, thông báo kết quả và xử lý khách không tồn tại.

**API, quyền và tính nhất quán**

Tất cả đường dẫn dưới đây bắt đầu bằng `/api/v1`:

| Endpoint | Chức năng |
| --- | --- |
| `GET /admin/users` | Giữ response `items,total,page,limit`; thêm số đơn `_count.orders`, ngày và thông tin liên hệ công khai cần thiết |
| `GET /admin/users/summary` | Tổng khách, đang hoạt động, bị khóa, mới trong 30 ngày |
| `GET /admin/users/:id` | Chi tiết và thống kê mua hàng của một CUSTOMER |
| `PATCH /admin/users/:id` | Sửa `name`, `email`, `phone`, bắt buộc `expectedUpdatedAt` |
| `PATCH /admin/users/:id/status` | Đổi `active`, bắt buộc `expectedUpdatedAt` |
| `GET /admin/orders?customerId=:id` | Lịch sử đơn chính xác theo tài khoản, tận dụng API đơn hàng |
| `PATCH /users/me` | Hồ sơ khách hàng dùng cùng chuẩn hóa và kiểm tra trùng số điện thoại |

Query danh sách gồm `q` tối đa 100 ký tự; `status=active|hidden` (giữ giá trị API cũ); `orders=has_orders|no_orders`; `registered=30d`; `sort=newest|oldest|name_asc|name_desc|orders_desc`; `page`, `limit` tối đa 100. Các trường/giá trị sai bị từ chối. `%`/`_` được coi là ký tự thường; tìm tiếng Việt cần dấu tương ứng.

Chỉ ADMIN/MANAGER có `customers.read`/`customers.manage`. Server kiểm tra quyền, vai trò CUSTOMER của đối tượng, UUID và dữ liệu đầu vào. PATCH hồ sơ không nhận trực tiếp `role` hoặc `password`; cấp quyền dùng các trường riêng được mô tả bên dưới, đặt lại mật khẩu dùng endpoint riêng. Response chọn trường rõ ràng, không trả hash/token. Danh sách/tổng và từng nhóm thống kê đọc trong transaction RepeatableRead; danh sách không tải toàn bộ đơn.

Sửa tài khoản dùng transaction Serializable với cơ chế retry/khóa hiện có và `expectedUpdatedAt` để tránh ghi đè dữ liệu mới. Đổi email hoặc trạng thái thu hồi phiên cùng mã/token khôi phục cũ trong cùng transaction. Mở khóa không khôi phục các phiên đã thu hồi. Worker khôi phục kiểm tra lại email sau khi lấy khóa để không phát hành mã cho email vừa bị thay đổi trong lúc xử lý. Mật khẩu và thông tin người nhận đã chốt trong đơn không bị sửa.

Nhật ký dùng sự kiện `STAFF_UPDATED` hiện có (đã hỗ trợ cập nhật tài khoản CUSTOMER ở module nhân sự), nhãn hiển thị “Cập nhật tài khoản”. Chỉ ghi các cờ thay đổi tên/email/điện thoại, vai trò/trạng thái/version; không sao chép thông tin liên hệ vào nhật ký. Không thêm enum/migration chỉ để đổi tên sự kiện.

**Quy tắc số điện thoại đã được chủ dự án chọn**

Chặn số trùng ở cả quản trị và hồ sơ khách hàng, so với mọi tài khoản khác. Chuẩn hóa khoảng trắng, dấu `().-`, tiền tố `00`, và `+84`/`0084`/`84` tương ứng sang số nội địa; chấp nhận số 7–15 chữ số, có thể có `+` quốc tế. Số trống vẫn được phép. Không đồng nhất số điện thoại người nhận đơn/địa chỉ với số điện thoại duy nhất của tài khoản, vì đó là dữ liệu giao nhận đã có nghiệp vụ riêng.

Hai API ghi dùng cùng khóa giao dịch và kiểm tra số đã chuẩn hóa, kể cả số cũ lưu dạng có dấu phân cách. Đã kiểm thử hai request đồng thời từ quản trị/hồ sơ: chỉ một request thành công; request còn lại trả `409 PHONE_ALREADY_EXISTS`. Email trùng trả `409 EMAIL_ALREADY_EXISTS`, dữ liệu cũ trả `409 CUSTOMER_CONFLICT`. Hồ sơ khách hiển thị đúng lỗi trùng và giữ nội dung đang nhập.

**Định nghĩa thống kê**

- Bốn thẻ danh sách là tổng toàn bộ CUSTOMER, không chỉ trang/kết quả tìm kiếm. “Mới” là cửa sổ 30 × 24 giờ; “Hoạt động” nghĩa là tài khoản được phép đăng nhập, không suy luận thời điểm truy cập cuối.
- Tổng đơn tính mọi trạng thái. Giá trị đơn đã giao là tổng `Order.total` của `DELIVERED`, gồm COD chưa thu và chưa trừ hoàn tiền; được ghi rõ trên giao diện.
- Đã thanh toán ròng là khoản thanh toán chính trạng thái PAID/PARTIALLY_REFUNDED/REFUNDED trừ hoàn tiền chính SUCCEEDED; hỗ trợ dữ liệu REFUNDED cũ chưa có bản ghi hoàn thành. Không tính COD chưa thu hoặc lần thanh toán phụ vào giá trị mua hàng. Tiền trả bằng chuỗi VND để giữ chính xác số nguyên.

**Kiểm chứng**

- 90 kiểm thử Flutter qua 9 suite khách hàng, đơn, hồ sơ, tài khoản và quản trị. Suite khách hàng mới có 14 test, gồm 360/768/1440 px, chữ 150%, URL, retry/rỗng/404, lịch sử đúng khách, validation, chống lưu lặp và xung đột. Sau tinh chỉnh giao diện cuối cùng, chạy lại 14 test này, analyze và release build đều qua.
- 53 test PostgreSQL qua 6 suite `admin-customers`, `admin-query`, `admin-orders`, `staff`, `commerce`, `admin`. Recovery ban đầu bị skip khi thiếu biến TEST_REDIS_HOST; đã chạy với Redis và SMTP cục bộ: 15 test qua, gồm kiểm thử mới cho đổi email đồng thời. Lượt cuối chạy chung `admin-customers` và `recovery`: 23/23 qua; tổng cộng 68 test backend riêng biệt. Fixture kiểm tra chuyển vai trò đã đặt rõ thời điểm mật khẩu và kiểm tra thư theo đúng người nhận, tránh phụ thuộc giá trị mặc định của database test cũ hoặc thư retry của test khác. Lint và backend build qua.
- Chrome thật trên bản release localhost:5173: đăng nhập quản trị, tìm/lọc/sắp xếp/phân trang/reload, chi tiết/lịch sử đơn/quay lại, sửa và lưu dữ liệu thật, trùng email/điện thoại, khóa/mở khóa, thu hồi phiên, xung đột và dữ liệu người nhận cũ. Danh sách/chi tiết/form kiểm tra ở 375/768/1440 px; không có lỗi JS/overflow hoặc response lỗi ngoài các lỗi chủ động kiểm thử. Script hồ sơ cũng qua 9 nhóm kiểm tra, từ 320 đến 2560 px, gồm lỗi kết nối, retry, lưu bằng bàn phím và chống gửi lặp.
- E2E dùng database `_test`. Browser QA tạo tài khoản/sản phẩm/đơn riêng và dọn theo ID đã tạo; không reset database hoặc gửi email ra ngoài. Báo cáo/ảnh nằm ở `.tools/customers-acceptance/` và `.tools/profile-redesign/` (ignored). Không dùng các dữ liệu QA này làm dữ liệu ứng dụng.

Chạy lại browser QA bằng `node tools/verify-admin-customers-browser.cjs` và `node tools/verify-profile-browser.cjs`; mặc định frontend 8080, API 3000. Nếu kiểm thử bản release riêng tại 5173, đặt `ADMIN_TEST_BASE=http://localhost:5173` và `PROFILE_TEST_BASE=http://localhost:5173`. Kiểm thử Recovery cần `TEST_REDIS_HOST=127.0.0.1`; suite dùng namespace Redis duy nhất và SMTP test cục bộ, không xóa queue ứng dụng.

**Các file thuộc đợt khách hàng** (các file dùng chung chỉ sửa phần tích hợp liên quan):

| Nhóm | File |
| --- | --- |
| API khách hàng mới | `backend/src/modules/admin/customers.service.ts`, `dto/admin-customers.dto.ts`, `backend/test/admin-customers.e2e-spec.ts` |
| Tích hợp admin/quyền/audit | `backend/src/modules/admin/admin.controller.ts`, `admin.module.ts`, `audit-snapshot.ts`, `backend/src/common/permissions.ts` |
| Liên kết đơn | `backend/src/modules/admin/dto/admin-orders-query.dto.ts`, `backend/src/modules/admin/order-list.ts` |
| Hồ sơ/khôi phục | `backend/src/modules/users/profile-identity.ts`, `users.service.ts`, `dto/user.dto.ts`, `backend/src/modules/recovery/recovery.service.ts`, `backend/test/recovery.e2e-spec.ts` |
| UI khách hàng mới | `frontend/lib/features/admin/remote/customers_page.dart`, `customer_detail.dart`, `customer_widgets.dart` |
| Kết nối/định tuyến/quyền UI | `frontend/lib/data/remote_admin.dart`, `frontend/lib/app/app.dart`, `frontend/lib/domain/staff_permissions.dart`, `frontend/lib/features/admin/remote/admin_pages.dart`, `admin_providers.dart`, `admin_widgets.dart`, `admin_activity.dart` |
| UI đơn và hồ sơ | `frontend/lib/features/admin/remote/orders_page.dart`, `order_detail.dart`, `order_presentation.dart`, `frontend/lib/core/contact_phone.dart`, `frontend/lib/core/network/api_client.dart`, `frontend/lib/features/account/account_profile_page.dart` |
| Test và tài liệu | `frontend/test/admin_customers_workspace_test.dart`, `frontend/test/account_profile_test.dart`, `tools/verify-admin-customers-browser.cjs`, `tools/verify-admin-workspace-browser.cjs`, `tools/verify-profile-browser.cjs`, `docs/admin.md` |

**Giới hạn đã biết:** chưa đo tải production hoặc kiểm chứng native Android/iOS. Không thêm tạo/xóa khách hàng thủ công, đổi vai trò hay đặt mật khẩu trong trang khách hàng vì hệ thống hiện tại dùng luồng đăng ký và quản lý nhân sự riêng. Quy tắc số điện thoại duy nhất được đảm bảo qua hai API ghi đã nêu; chưa thêm unique index/schema nên thao tác SQL/import trực tiếp có thể bỏ qua quy tắc này. Truy vấn chuẩn hóa số cũ và khóa ghi chung cần đánh giá lại khi lượng tài khoản/tần suất cập nhật lớn. Cảnh báo deprecation `pg` về truy vấn trên kết nối đang bận vẫn thuộc dependency hiện tại; các kiểm thử giao dịch qua, chưa nâng dependency trong đợt này.

Phiên Flutter 8080 của chủ máy được giữ nguyên. Để thấy source mới, nhấn **R** ở terminal Flutter rồi **Ctrl+F5** trên trình duyệt; không chạy thêm `frontend.ps1 api` trên cổng đã có server. Backend phải chạy bản build mới hoặc chế độ watch.

### Hoàn thiện quản lý đơn hàng (24/10/2026)

Trang `/#/admin/orders` dùng API thật, giữ kiến trúc Flutter/Riverpod và NestJS/Prisma hiện có. Giao diện dùng bảng trên desktop, thẻ trên màn hình hẹp; có loading, retry, thông báo kết quả, xử lý danh sách rỗng và đơn không tồn tại. Trang chi tiết chia thành sản phẩm/tổng tiền, giao nhận, thanh toán, lịch sử đơn/vận chuyển và các thao tác theo quyền. Bộ lọc được giữ khi quay từ chi tiết về danh sách.

`GET /api/v1/admin/orders` hỗ trợ:

- `q`: mã đơn, UUID, tên/email tài khoản, người nhận/số điện thoại lưu trong đơn, tên sản phẩm hoặc SKU; tối đa 100 ký tự.
- `status`: trạng thái đơn hiện có; các nút trạng thái có số lượng tương ứng với những điều kiện lọc khác.
- `provider`: `cod`, `vnpay`, `free`; `paymentStatus`: `PENDING`, `PAID`, `PARTIALLY_REFUNDED`, `REFUNDED`, `FAILED`, `CANCELLED`, hoặc `COD_UNSETTLED` (đã giao, COD chưa thu).
- `from`, `to`: ngày `YYYY-MM-DD`, bao gồm hai ngày đầu/cuối theo UTC+7. Thời gian đơn và đối soát hiển thị theo cùng múi giờ. Ngày sai hoặc khoảng đảo ngược trả 400.
- `sort`: `newest`, `oldest`, `total_desc`, `total_asc`; `page` và `limit` (API tối đa 100; giao diện chọn 20/50/100).

Danh sách chỉ tải dữ liệu cần hiển thị và một sản phẩm đại diện, không tải toàn bộ lịch sử, lần thanh toán và yêu cầu trả hàng. Danh sách/tổng/số lượng theo trạng thái dùng cùng transaction RepeatableRead. Không thêm thư viện hoặc migration cho thay đổi này.

Quy trình vẫn là `PENDING → CONFIRMED → SHIPPED → DELIVERED`; hủy trước khi gửi, giao lại/hoàn kho, trả hàng và hoàn tiền dùng các API hiện có. API kiểm tra `expectedVersion`, khóa đơn trong transaction và ghi lịch sử/nhật ký cùng thao tác. Không cho giao đơn thiếu thanh toán, sai số tiền, phương thức không hỗ trợ hoặc VNPay chưa xác minh. Giao COD thành công không tự ghi nhận tiền; đối soát cần đúng tổng tiền và mã tham chiếu, có bảo vệ ghi nhận lặp. Hủy hoàn lại kho một lần. Khi xung đột hoặc kết quả chưa chắc chắn, phải tải lại dữ liệu trước khi gửi tiếp. Phân quyền được kiểm tra ở server và giao diện.

Kiểm chứng đợt đơn hàng: **81 kiểm thử Flutter**, **57 kiểm thử PostgreSQL** thuộc các suite quản trị đơn, truy vấn, nhân sự, vận chuyển, trả hàng và hoàn tiền; `flutter analyze`, Flutter release build, backend build và ESLint đều qua. Kiểm thử mới ở `frontend/test/admin_orders_workspace_test.dart` và `backend/test/admin-orders.e2e-spec.ts` bao gồm màn hình 360/768/1440, chữ 150%, bộ lọc, đồng thời và thanh toán không hợp lệ.

Chạy `node tools/verify-admin-orders-browser.cjs` khi API cổng 3000 và frontend bản mới cổng 8080 đã chạy. Có thể đổi frontend bằng `ADMIN_TEST_BASE`. Script tạo 22 đơn và tài khoản/sản phẩm riêng, kiểm tra tìm kiếm/lọc/sắp xếp/phân trang, chọn khoảng ngày, quay lại danh sách, xác nhận/giao/COD, hủy hoàn kho và xung đột trên Chrome thật. Chỉ thay đổi các bản ghi vừa tạo; dọn chúng khi kết thúc. Mail của đơn thử được đánh dấu đã xử lý trước thao tác để không gửi thư. Báo cáo và ảnh 375/768/1440 ở `.tools/orders-acceptance/` (ignored).

Nếu terminal đang chạy Flutter tại 8080, nhấn **R** để hot restart rồi tải lại trình duyệt; không mở thêm một phiên trên cùng cổng. Backend cần chạy bản build mới hoặc chế độ watch. Kiểm thử trình duyệt của đợt này chạy bản release riêng qua localhost:5173 để giữ phiên Flutter đang mở của chủ máy.

Giới hạn môi trường: vận chuyển vẫn dùng `local_simulator`, VNPay dùng cấu hình sandbox hiện có. Đợt này chưa kiểm chứng giao dịch tiền thật, hãng vận chuyển thật hoặc tải production; không thể xem việc vượt qua kiểm thử local là chứng nhận các tích hợp production. Tên tiếng Việt cần dấu tương ứng khi tìm kiếm.

Log backend còn cảnh báo deprecation của `pg` về các truy vấn trên cùng kết nối đang bận. Các kiểm thử giao dịch/đồng thời vẫn qua; cảnh báo này cần được rà soát khi nâng cấp bộ Prisma/pg, chưa thay đổi phiên bản dependency trong đợt giao diện đơn hàng.

Đợt giao diện 24/10: 97 kiểm thử Flutter thuộc 13 suite quản trị và chức năng liên quan; 31 kiểm thử PostgreSQL trong `admin-query`, `admin`, `staff`, `admin-username`; `flutter analyze`, backend build và ESLint. `admin_overview_test.dart` kiểm tra tìm kiếm, reset phân trang, bộ lọc theo URL, retry, màn hình 360 / 768 / 1440 và chữ phóng lớn 150%.

Chạy `node tools/verify-admin-workspace-browser.cjs` sau khi API và bản web mới đã phục vụ tại cổng 8080. Có thể đổi địa chỉ web qua biến môi trường `ADMIN_TEST_BASE`. Script tạo tài khoản quản trị kiểm thử tạm, dùng đăng nhập thật, kiểm tra 14 trang ở 375 / 768 / 1440, phiên đăng nhập, tìm kiếm, bộ lọc, phân trang, mở sản phẩm / đơn / hộp thoại kho và đăng xuất. Script không lưu thay đổi nghiệp vụ; tài khoản và phiên tạm được xóa khi kết thúc. Ảnh và báo cáo lưu trong `.tools/admin-redesign/` (ignored).

`powershell -NoProfile -File tools/test-backend.ps1` chạy E2E PostgreSQL riêng `_test`. `node tools/test-frontend-api.cjs --admin` tạo tài khoản/sản phẩm/đơn kiểm thử riêng, build Flutter release rồi chạy Chrome thật. Helper chỉ dọn các ID/email/slug của chính lượt chạy, không reset database phát triển. Ảnh/log ở `.tools/api-admin-verification/` (ignored). Sau kiểm thử, chạy `.\tools\frontend.ps1 build-api` để build lại với API mặc định `localhost:3000`.

### Hoàn thiện quản lý nội dung (24/10/2026)

Trang `/#/admin/content` tiếp tục sử dụng singleton `StoreContent` của dự án, tách bản nháp và snapshot công khai. Không thay đổi nội dung cửa hàng trong quá trình kiểm thử.

- Biên tập theo bốn nhóm: Trang chủ (tiêu đề, tên, mô tả ngắn), Giới thiệu, Liên hệ và Chính sách (giao hàng/đổi trả, riêng tư, điều khoản). Chuyển nhóm giữ dữ liệu đang nhập; lưu kiểm tra cả nhóm đang ẩn và đưa người dùng tới trường lỗi đầu tiên.
- Xem trước văn bản trực tiếp ở desktop, hộp xem trước đầy đủ ở mọi kích thước; chuyển được vị trí hiển thị. Có bản xem riêng cho nội dung đang công khai. Tất cả là văn bản thuần, không thực thi HTML/script.
- Hiển thị phiên bản, thời điểm lưu/xuất bản UTC+7, trạng thái chưa lưu/chưa xuất bản/đồng bộ và số mục khác bản công khai. Nội dung khách nhìn thấy chỉ thay đổi sau **Xác nhận xuất bản**; hộp xác nhận đối chiếu giá trị cũ/mới của từng mục thay đổi. Phải lưu nháp trước khi xuất bản.
- Khôi phục bản nháp từ snapshot công khai có xác nhận, tạo phiên bản nháp mới và ghi audit. Không thay đổi snapshot, phiên bản công khai hoặc thời điểm xuất bản; bản nháp đã giống bản công khai không cần xuất bản lại. Không xóa singleton hay lịch sử để “hủy nháp”.
- Tải lại khi có chỉnh sửa yêu cầu xác nhận. Rời trang qua menu/Back có cảnh báo bỏ thay đổi; reload/đóng tab web sử dụng cảnh báo native của trình duyệt khi có thay đổi hoặc đang lưu. Trình duyệt quyết định cách hiển thị cảnh báo native; không lưu nội dung nháp vào browser storage.
- Lưu/xuất bản/khôi phục chỉ gửi một lần trong lúc xử lý. Xung đột hoặc kết quả chưa xác định giữ nội dung đang nhập và yêu cầu tải lại trước khi tiếp tục. Hết phiên quản trị sẽ ẩn nội dung của hộp xem trước/xác nhận; phản hồi cũ không áp dụng cho phiên mới. Xuất bản vẫn làm mới cache công khai khi phản hồi đến sau lúc rời trang.
- Nhật ký tải theo nhu cầu, phân trang 10 mục; hiển thị thao tác, phiên bản, thời gian và ID người thao tác. Audit chỉ lưu trạng thái/phiên bản, không sao chép văn bản nháp hoặc thông tin liên hệ.

API:

| Endpoint | Hành vi |
| --- | --- |
| `GET /admin/content` | Bản nháp, snapshot `published`, `createdAt`, `updatedAt`, `hasUnpublishedChanges` |
| `PUT /admin/content` | Lưu nháp với `expectedVersion`; DTO cũ không gửi `details` vẫn giữ thông tin cửa hàng hiện có |
| `POST /admin/content/publish` | Xuất bản đúng phiên bản đã lưu; `{ "expectedVersion": n }`; từ chối khi đã đồng bộ |
| `POST /admin/content/restore` | Chép bản công khai vào nháp; `{ "expectedVersion": n }`; 409 khi phiên bản cũ, chưa có bản công khai hoặc nội dung đã giống nhau |
| `GET /admin/content/history` | `page`, `limit`; lịch sử chỉ của singleton, tự co số trang vượt tổng |
| `GET /content` | Chỉ snapshot công khai, không lộ nháp, thời điểm lưu nháp hoặc metadata quản trị |

ADMIN/MANAGER có quyền `content.manage`; CUSTOMER/WAREHOUSE/SUPPORT bị từ chối. Mutation kiểm tra lại tài khoản active/quyền bên trong transaction, khóa singleton kể cả lần tạo đầu tiên và ghi audit nguyên tử. Lưu đồng thời không ghi đè bản mới; khi audit thất bại dữ liệu được rollback.

Migration `20261024220000_content_draft_restore` bổ sung `CONTENT_DRAFT_RESTORED`; đã áp dụng trên database local và test. Môi trường khác chạy Prisma generate/migrate deploy rồi build theo quy trình hiện có; không reset database.

File thay đổi:

- Backend: `src/modules/content/{content.controller.ts,content.service.ts}`, `src/modules/admin/audit-snapshot.ts`, `prisma/schema.prisma`, `prisma/migrations/20261024220000_content_draft_restore/migration.sql`.
- Frontend: `lib/features/admin/remote/{content_page.dart,content_workspace.dart,content_models.dart,content_preview.dart,content_history.dart,content_unload.dart,content_unload_stub.dart,content_unload_web.dart,admin_providers.dart,admin_activity.dart}`, `lib/app/{app.dart,content_navigation.dart}`, `lib/data/remote_admin.dart`. Không thêm package phụ thuộc.
- Kiểm thử: `backend/test/content.e2e-spec.ts`, `frontend/test/{store_content_test.dart,admin_content_workspace_test.dart}`, `tools/verify-admin-content-browser.cjs`.

Chrome acceptance chạy `node tools/verify-admin-content-browser.cjs` sau khi build backend và mở frontend local. Công cụ tự mở một Nest API ở cổng local tạm, chuyển request của phiên Chrome kiểm thử tới API này và dùng database `*_test` đã migrate. Đây là API/database thật, không dùng response mock. Công cụ từ chối ghi đè singleton test có sẵn, luôn dọn fixture và kiểm tra fingerprint nội dung cửa hàng local trước/sau. Báo cáo/ảnh tại `.tools/content-admin-acceptance`.

Kết quả: 64 Flutter tests, 23 PostgreSQL/Nest E2E tests (3 suites), 3 audit unit tests và 5 nhóm luồng Chrome đều đạt. Flutter analyze, ESLint, Nest build và Flutter web release build đạt. Kiểm tra Chrome tại 375/768/1440 px; widget tests có thêm cỡ chữ 150%. Đã kiểm tra mất phiên và thu hồi quyền nội dung của cùng tài khoản khi đang mở hộp xác nhận. Không có lỗi chặn trong phạm vi kiểm tra; nội dung cửa hàng local được giữ nguyên và fixture đã được dọn.

### Khuyến mãi tự động và bố cục quản trị (25/10/2026)

- Bộ sưu tập, khuyến mãi và kho dùng bảng phủ chiều rộng nội dung, giới hạn cột tên/thao tác và chia đều không gian cho các cột thông tin. Màn hình nhỏ chuyển sang thẻ. Phân trang quản trị dùng chung, mặc định **10 mục**, có số trang và khoảng bản ghi; đổi bộ lọc/số mục về trang đầu.
- Trong **Khuyến mãi → Thêm khuyến mãi**, chọn **Tự động giảm giá**, nhập tên và chọn **Toàn bộ sản phẩm** hoặc **Một số sản phẩm**. Bộ chọn tìm theo tên/SKU, phân trang và chọn nhiều sản phẩm. Chọn giảm tiền/phần trăm, trần giảm trên mỗi sản phẩm, lịch UTC+7 rồi bật chương trình. Không cần tạo hoặc nhập mã để khách nhận giá giảm.
- Giá tự động áp dụng trên từng đơn vị sản phẩm. Nếu có nhiều chương trình phù hợp, lấy mức giảm cao nhất, không cộng dồn các chương trình tự động. Không dùng điều kiện đơn tối thiểu hoặc giới hạn lượt cho loại này, để giá công khai nhất quán cho mọi khách.
- Cửa hàng, bộ sưu tập, chi tiết sản phẩm, yêu thích, giỏ hàng và thanh toán dùng giá do backend tính; hiện giá gốc gạch ngang, giá mới và tên chương trình. Bộ lọc/sắp xếp giá và AI Stylist dùng giá sau giảm. Khi quay lại sản phẩm/danh mục, dữ liệu giá được tải mới; giỏ hàng được cập nhật khi mở giỏ/thanh toán. Tại tạo đơn, server kiểm tra lại giá và trả xung đột nếu giá đã đổi.
- **Khách nhập mã** vẫn hỗ trợ mã ưu đãi cũ, phạm vi toàn bộ hoặc một số sản phẩm. Mã được tính trên giá còn lại sau khuyến mãi tự động; giá trị đơn tối thiểu xét trên tổng tiền sản phẩm sau giảm tự động. Mã tự động nội bộ không thể dùng làm mã nhập tay.
- Đơn hàng lưu giá gốc, giá thực trả và tên/chương trình đã dùng trên từng dòng. Tắt, hết hạn hoặc sửa khuyến mãi không thay đổi đơn cũ; hoàn tiền theo giá thực trả. Chương trình đã có lịch sử đơn không được xóa. Chi tiết quản trị hiển thị số đơn và tổng giảm tự động; đơn hủy không tính vào tổng đang sử dụng.
- Migration bổ sung `20261025050000_automatic_promotions` đã áp dụng ở local và database kiểm thử riêng. Triển khai nơi khác cần `prisma generate`, `prisma migrate deploy`, build và khởi động lại backend/frontend. Mã cũ giữ `CODE/ALL`, không tự chuyển sang giảm giá tự động.

### Hoàn thiện quản lý khuyến mãi (24/10/2026)

Trang `/#/admin/promotions` và `/#/admin/promotions/:id` dùng PostgreSQL thật, dành cho ADMIN/MANAGER có quyền `promotions.manage`.

- Tìm mã không phân biệt hoa thường; `%`, `_`, `\` được hiểu là ký tự thường. Lọc trạng thái và loại giảm, sắp xếp, phân trang 10/20/50/100 (mặc định 10); bộ lọc lưu trên URL và giữ khi quay lại từ chi tiết.
- Thống kê toàn bộ mã, đang áp dụng, sắp bắt đầu và hết lượt. Trạng thái do server tính: đã tắt → hết hạn → sắp bắt đầu → hết lượt → đang áp dụng. Điều kiện giá trị đơn và giới hạn từng khách vẫn được kiểm tra riêng tại checkout.
- Thêm/sửa giảm cố định hoặc phần trăm, mức đơn tối thiểu, trần giảm, giới hạn tổng/từng khách và lịch UTC+7; có lịch chọn ngày giờ hoặc nhập trực tiếp. Mặc định mã mới tắt. Mã được chuẩn hóa chữ hoa và không đổi sau khi tạo. Ngày không sửa giữ nguyên cả giây/millisecond từ API.
- Bật/tắt và xóa có xác nhận. PATCH/DELETE yêu cầu `expectedVersion`; kiểm tra lại quyền người thao tác trong transaction, khóa cùng bản ghi coupon với checkout, ghi audit nguyên tử. Mã trùng trả `PROMOTION_CODE_EXISTS`; xung đột phiên bản bắt buộc tải lại, không tự gửi lại yêu cầu chưa rõ kết quả.
- Chỉ xóa mã chưa từng có `CouponRedemption`. Mã có lịch sử, kể cả lượt đã trả lại, trả `PROMOTION_IN_USE`; dùng tắt mã để ngừng áp dụng. Đơn hàng và giá trị giảm lịch sử không thay đổi.
- Chi tiết hiển thị tổng lượt đang tính, lượt trả lại, tổng giảm và lịch sử phân trang có liên kết đơn hàng. Tổng giảm gồm đơn chưa thanh toán, không được diễn giải là doanh thu. Giảm chỉ trên tiền sản phẩm; phần trăm làm tròn xuống, không vượt tiền sản phẩm. Preview không giữ lượt; tạo đơn giữ lượt trong transaction. Luồng hủy đơn hợp lệ trước giao hàng trả lượt; hoàn hàng không tự trả lượt. Hạ giới hạn xuống dưới số đã dùng sẽ chặn lần dùng tiếp theo, không sửa đơn cũ.
- Loading, lỗi/tải lại, danh sách rỗng, 404, form validation, phản hồi thành công, chặn nhấn lưu nhiều lần và xử lý phiên quản trị kết thúc. Giao diện đã kiểm tra 375/768/1440 px và cỡ chữ 150%.

API bổ sung/hoàn thiện:

| Endpoint | Hành vi |
| --- | --- |
| `GET /admin/promotions` | `q`, `status=active|scheduled|expired|exhausted|inactive`, `kind=FIXED|PERCENT`, `sort=newest|updated|code_asc|expiry|usage_desc`, `page`, `limit`; tự co trang vượt tổng |
| `GET /admin/promotions/summary` | Thống kê toàn bộ theo trạng thái thực tế |
| `GET /admin/promotions/:id` | Điều kiện, `status`, `usedCount`, `historyCount`, `discountTotal`, `canDelete`; giữ `_count.redemptions` tương thích |
| `GET /admin/promotions/:id/redemptions` | Lịch sử phân trang, mã/trạng thái đơn, số tiền giảm và ngày trả lượt; không trả thông tin cá nhân |
| `POST /admin/promotions` | Tạo mã; kiểm tra giá trị, ngày có timezone, mã duy nhất |
| `PATCH /admin/promotions/:id` | Cập nhật có `expectedVersion`, giữ bất biến mã |
| `DELETE /admin/promotions/:id` | Body `{ "expectedVersion": 0 }`; 409 khi mã đã đổi hoặc đã có lịch sử |

Migration `20261024210000_promotions_workspace` bổ sung audit `PROMOTION_DELETED` và index cho danh sách/lịch sử. Đã áp dụng trên database local và database test riêng. Khi triển khai môi trường khác: chạy Prisma generate, migrate deploy, build backend/frontend theo quy trình hiện có; không reset dữ liệu.

Kiểm thử: `backend/test/promotions.e2e-spec.ts`, `frontend/test/admin_promotions_workspace_test.dart`, `frontend/test/promotions_test.dart`; kiểm tra hồi quy commerce/admin và component dùng chung. Chrome acceptance: `node tools/verify-admin-promotions-browser.cjs` (chỉ local), tạo fixture có phạm vi riêng và luôn dọn ở `finally`; báo cáo/ảnh tại `.tools/promotions-admin-acceptance`. Không có fixture/mock trong chức năng chính.

Kết quả xác nhận: 64 kiểm thử Flutter, 41 kiểm thử PostgreSQL/API (16 khuyến mãi + 25 commerce/admin), 3 kiểm thử audit và 5 nhóm Chrome đạt. Flutter analyze, ESLint, Nest build và Flutter web release build đạt. Chrome không có lỗi runtime/overflow hoặc phản hồi admin API bất thường; fixture đã dọn. Driver `pg` vẫn có cảnh báo deprecation trong kiểm thử đồng thời của dự án, không làm thất bại kiểm thử.

Các file thay đổi trong đợt khuyến mãi:

- Backend: `src/modules/promotions/{promotions.controller.ts,promotions.service.ts,promotions-query.dto.ts,promotions-workspace.ts}`, `src/modules/admin/audit-snapshot.ts`, `prisma/schema.prisma`, `prisma/migrations/20261024210000_promotions_workspace/migration.sql`.
- Frontend: `lib/features/admin/remote/{promotions_page.dart,promotions_workspace.dart,promotion_editor.dart,promotion_widgets.dart,promotion_actions.dart,promotion_detail.dart,admin_pages.dart,admin_providers.dart,admin_widgets.dart,admin_activity.dart}`, `lib/data/remote_admin.dart`, `lib/app/app.dart`.
- Kiểm chứng/tài liệu: `backend/test/promotions.e2e-spec.ts`, `frontend/test/{promotions_test.dart,admin_promotions_workspace_test.dart}`, `tools/verify-admin-promotions-browser.cjs`, `docs/admin.md`.

### Hoàn thiện quản lý bộ sưu tập (24/10/2026)

Đã hoàn thiện `/#/admin/collections` và `/#/admin/collections/:id` trên Flutter/Riverpod/go_router, NestJS/Prisma/PostgreSQL hiện có. Giữ cơ chế tự gom sản phẩm theo **phong cách chính xác** và mỗi phong cách một bộ sưu tập. Không thêm dependency hoặc dữ liệu giả cho chức năng chính.

**Chức năng và quyết định nghiệp vụ**

- Danh sách có ảnh bìa, mô tả, phong cách, số sản phẩm công khai/tổng, thời gian UTC+7, thứ tự hiển thị; thống kê toàn cửa hàng, tìm kiếm tiếng Việt có/không dấu theo tên/phong cách/slug/UUID, lọc hiển thị/ẩn/chờ, sort và phân trang server. URL giữ bộ lọc/trang khi reload, mở chi tiết và quay lại; server giới hạn lại số trang khi dữ liệu giảm.
- Form tạo/sửa có gợi ý slug tiếng Việt, slug bất biến sau tạo, mô tả, phong cách nhập tự do hoặc chọn gợi ý từ DB, thứ tự 0–10000 và bật/ẩn. Bộ mới mặc định ẩn để người quản trị kiểm tra trước khi bật. Duplicate slug/style được sửa ngay trong form; không khóa form buộc reload với lỗi nhập liệu này.
- Chọn ảnh bìa bằng tìm kiếm/phân trang sản phẩm **công khai cùng phong cách**, thay cho tải toàn bộ catalog. Có ảnh tự động, xem trước, bỏ ảnh đã chọn. Nếu ảnh đã chọn mất điều kiện, storefront dùng thành viên hợp lệ khác và trang quản trị giải thích rõ; nếu không còn thành viên hợp lệ thì hiển thị trạng thái chờ. Quản trị/picker/storefront dùng cùng thứ tự ảnh của sản phẩm.
- Chi tiết hiển thị metadata, ảnh thực tế, cảnh báo fallback, tổng/công khai, tối đa 6 sản phẩm gần cập nhật, sao chép mã và liên kết tới storefront hoặc danh sách sản phẩm theo đúng phong cách. Trang sản phẩm hỗ trợ `style` và chip xóa bộ lọc này.
- Bật/ẩn và xóa có xác nhận, bắt buộc phiên bản. Xóa chỉ gỡ bản ghi bộ sưu tập/trang giới thiệu, **không xóa hoặc đổi trạng thái sản phẩm, không đổi tồn kho**. Audit `COLLECTION_DELETED` cùng transaction; audit lỗi thì rollback.
- Giao diện có loading, empty/error/404, retry, khóa gửi lặp, xử lý phiên hết hạn, phiên bản cũ và phản hồi muộn sau timeout. Cache quản trị/storefront được làm mới sau mutation; không tự phát lại thao tác ghi chưa rõ kết quả. Form đang mở không thể tiếp tục ghi sau đăng xuất.

**API và database**

Tất cả endpoint dưới `admin/collections` yêu cầu `content.manage`; create/update/delete kiểm tra lại actor đang hoạt động và quyền trong Serializable transaction, không chỉ dựa vào guard trước khi vào service.

| Endpoint | Hợp đồng |
| --- | --- |
| `GET /api/v1/admin/collections` | `q` ≤100, `status=published/hidden/waiting`, `sort=position/newest/updated/title_asc/title_desc/products_desc`, `page`, `limit` ≤100 |
| `GET /api/v1/admin/collections/summary` | Tổng, đang hiển thị, đang ẩn, đang chờ; mỗi bộ được tính một lần |
| `GET /api/v1/admin/collections/:id` | UUID, metadata, version, tổng/công khai, cover/fallback và tối đa 6 sản phẩm gần cập nhật |
| `GET /api/v1/admin/collections/styles` | Gợi ý phong cách từ sản phẩm/bộ sưu tập thật, gồm cả phong cách chưa công khai |
| `GET /api/v1/admin/collections/covers` | Bắt buộc `style`, tùy chọn `q/page/limit`; chỉ trả một trang sản phẩm đủ điều kiện làm bìa |
| `POST /api/v1/admin/collections` | Giữ DTO hiện có: title/slug/style/description, active/position/coverProductId |
| `PATCH /api/v1/admin/collections/:id` | Giữ DTO hiện có, bắt buộc `expectedVersion`; không đổi slug |
| `DELETE /api/v1/admin/collections/:id` | Bắt buộc `expectedVersion`; 409 `COLLECTION_CHANGED`, 404 nếu đã xóa |

Truy vấn admin dùng aggregate và cover theo từng trang, không lặp truy vấn riêng từng bộ. Tìm kiếm bind tham số và escape ký tự LIKE. Điều kiện công khai khớp storefront (sản phẩm bật, ảnh dùng được, SKU bật; không bắt buộc tồn dương). Public API giữ hợp đồng hiện có, gồm trang bộ sưu tập đang bật nhưng trống vẫn trả trang rỗng; danh sách public chỉ liệt kê bộ đủ điều kiện.

Hai migration đã áp dụng **local và `_test`**: `20261024190000_collection_deletion` thêm enum audit; `20261024200000_collection_product_style_index` thêm index Product(style, active, createdAt). Môi trường triển khai khác chạy `prisma migrate deploy` trước khi khởi động backend mới.

**File chính**

- Frontend: `frontend/lib/features/admin/remote/collections_page.dart` là entry point; `collections_workspace.dart`, `collection_detail.dart`, `collection_editor.dart`, `collection_cover_picker.dart`, `collection_actions.dart` tách danh sách, chi tiết, form và thao tác. Tích hợp qua `admin_pages.dart`, `admin_providers.dart`, `admin_widgets.dart`, `admin_activity.dart`, `products_page.dart`, `frontend/lib/data/remote_admin.dart`, `frontend/lib/app/app.dart`.
- Backend: `backend/src/modules/admin/collections-workspace.ts`, `dto/admin-collections-query.dto.ts`, `dto/admin-products-query.dto.ts`, `product-list.ts`, `audit-snapshot.ts`; `backend/src/modules/products/collections.{service,controller,dto}.ts`; schema Prisma và hai migration trên.
- Kiểm thử: `backend/test/admin-collections.e2e-spec.ts`, `frontend/test/admin_collections_workspace_test.dart`, `tools/verify-admin-collections-browser.cjs`.

**Kiểm chứng**

- Backend build/ESLint, Flutter analyze và web release build đạt; Wasm dry run thành công.
- 115 kiểm thử Flutter: workspace bộ sưu tập (19 ca), public collections, UI quản trị, sản phẩm, danh mục và thương hiệu. Có 375/768/1440 px, chữ 200%, form, chọn bìa phân trang, xóa một lần, timeout đến muộn, đăng xuất, retry và 404.
- 48 kiểm thử PostgreSQL thuộc admin/public collections, sản phẩm, danh mục, thương hiệu; 3 unit test audit đạt. Có phân quyền, quyền bị thu hồi trước transaction, đối chiếu public/admin, thứ tự ảnh, fallback, trạng thái/phiên bản, rollback audit, xóa đồng thời và bảo toàn sản phẩm/tồn kho.
- Chrome tại localhost:8080: 5 nhóm luồng đạt, gồm đăng nhập thật, lọc/tìm kiếm/phân trang/reload, tạo/sửa/chọn bìa/bật/ẩn, liên kết storefront/sản phẩm, fallback, responsive, xung đột và xóa có xác nhận. Report không có lỗi JS/overflow/API bất thường; chỉ fixture riêng được thay đổi và đã dọn. Ảnh/report: `.tools/collections-admin-acceptance/`; chạy lại bằng `node tools/verify-admin-collections-browser.cjs`.
- Log: `.tools/collections-admin-regression.log`, `.tools/collections-widget-tests.log`, `.tools/collections-admin-build.log`. API 3000 và web 8080 đã được nạp source mới.

Chưa triển khai hoặc kiểm thử tải production/thiết bị thật/Safari. Cảnh báo deprecation `pg` hiện có vẫn xuất hiện trong kiểm thử đồng thời, không làm thất bại kiểm thử; chưa nâng dependency trong phạm vi này. Các tab/phiên khác dùng “Tải lại” để nhận thay đổi, chưa có đồng bộ realtime. Không còn lỗi chức năng đã biết trong các luồng được kiểm chứng.

### Hoàn thiện quản lý thương hiệu (24/10/2026)

Đã hoàn thiện `/#/admin/brands` và `/#/admin/brands/:id` trên kiến trúc Flutter/Riverpod/go_router → NestJS/Prisma/PostgreSQL hiện có. Trang dùng API thật; không thêm dependency hoặc dữ liệu giả vào chức năng quản trị. Backend 3000 và Flutter web 8080 đã được khởi động lại bằng source mới.

**Chức năng**

- Bảng desktop/thẻ mobile, thống kê toàn cửa hàng, tìm kiếm tiếng Việt có/không dấu, slug/UUID, lọc mức độ có sản phẩm/công khai, sắp xếp và phân trang tại database. URL giữ bộ lọc, số trang và liên kết quay lại; server tự giới hạn trang khi dữ liệu giảm.
- Tạo thương hiệu với gợi ý slug tiếng Việt, validation và xử lý slug trùng ngay trong form. Đổi tên giữ nguyên slug và liên kết sản phẩm. Gửi phiên bản `updatedAt` để chặn ghi đè dữ liệu cũ; khóa thao tác khi đang lưu, không tự phát lại yêu cầu khi kết quả chưa xác định.
- Chi tiết gồm tổng/công khai/chưa công khai, tối đa 6 sản phẩm gần cập nhật, mã sao chép, thời gian UTC+7 và liên kết tới sản phẩm, kho, cửa hàng. Đã nối `brand` xuyên suốt ProductQuery → RemoteProductRepository và hiển thị tên thương hiệu/bộ lọc tại cửa hàng. Kho hỗ trợ `brandId` cùng bộ lọc thương hiệu thật.
- Xóa có xác nhận và bắt buộc `expectedUpdatedAt`. Chặn cả sản phẩm ẩn, khóa bản ghi cha trong Serializable transaction để bảo vệ trước việc đồng thời gán sản phẩm. Có audit `BRAND_DELETED`; lỗi audit thì hoàn tác toàn bộ. Không thay đổi tồn kho hay tự xóa sản phẩm.
- Có loading, empty/error/404, retry, thông báo xung đột, phân quyền đọc/ghi và xử lý phiên đăng nhập. Thành phần danh sách/chi tiết/xóa dùng chung với danh mục để giữ hành vi và thiết kế nhất quán.

**API**

| Endpoint | Quyền / hợp đồng |
| --- | --- |
| `GET /api/v1/admin/brands` | `catalog.read`; `q`, `coverage=empty/populated/published/unpublished`, `sort=name_asc/name_desc/newest/oldest/updated/products_asc/products_desc`, `page`, `limit` ≤ 100 |
| `GET /api/v1/admin/brands/summary` | `catalog.read`; tổng thương hiệu, trống, có sản phẩm công khai, tổng sản phẩm/công khai |
| `GET /api/v1/admin/brands/:id` | `catalog.read`; bản ghi, số lượng, sản phẩm gần cập nhật; UUID hợp lệ, 404 nếu thiếu |
| `POST /api/v1/admin/brands` | `catalog.write`; tên 1–100 ký tự, slug ASCII 1–100 ký tự và duy nhất |
| `PATCH /api/v1/admin/brands/:id` | `catalog.write`; `name`, `expectedName`, `expectedUpdatedAt`; slug bất biến |
| `DELETE /api/v1/admin/brands/:id` | `catalog.write`; bắt buộc `expectedUpdatedAt`; 409 `BRAND_IN_USE`/`VERSION_CONFLICT`, 404 nếu đã xóa |

Số công khai cùng điều kiện với storefront: sản phẩm đang bật, có ảnh dùng được và SKU đang bật; không yêu cầu tồn kho dương. SQL chỉ dùng định danh bảng/cột từ allowlist nội bộ, tham số người dùng được bind. Mỗi sản phẩm chỉ được đếm một lần. Hợp đồng phân trang/tham chiếu cũ vẫn được giữ. Timestamp khi đổi tên vẫn tùy chọn ở API để tương thích client cũ; giao diện mới luôn gửi timestamp. Client chỉ gửi `expectedName` chưa được bảo vệ đầy đủ trước chuỗi thay đổi A → B → A.

**File chính**

- Frontend mới: `brands_page.dart`, `taxonomy_kind.dart`, `taxonomy_workspace.dart`, `taxonomy_detail.dart`, `taxonomy_widgets.dart` trong `frontend/lib/features/admin/remote/`. Các entry point danh mục chuyển thành wrapper của thành phần dùng chung.
- Frontend tích hợp: `admin_pages.dart`, `admin_providers.dart`, `admin_widgets.dart`, `admin_activity.dart`, `inventory_page.dart`; `frontend/lib/app/{app,providers}.dart`, `frontend/lib/data/{remote_admin,remote_catalog}.dart`, `frontend/lib/domain/catalog.dart`, `frontend/lib/features/catalog/catalog_page.dart`.
- Backend: `backend/src/modules/admin/taxonomy-workspace.ts`, `taxonomy.service.ts`, `categories-workspace.ts`, `admin.controller.ts`, `inventory-workspace.ts`, `audit-snapshot.ts`; các DTO taxonomy/danh mục/kho; `backend/prisma/schema.prisma` và migration `20261024180000_brand_deletion`.
- Kiểm thử: `backend/test/admin-brands.e2e-spec.ts`, `frontend/test/admin_brands_workspace_test.dart`, cập nhật `remote_admin_ui_test.dart` và `remote_catalog_test.dart`; trình duyệt `tools/verify-admin-brands-browser.cjs`.

**Kiểm chứng**

- Backend build, ESLint, Flutter analyze và Flutter web release build: đạt; Wasm dry run thành công.
- 116 kiểm thử Flutter: thương hiệu, danh mục, UI quản trị, kho, sản phẩm, danh mục công khai và hợp đồng catalog; riêng thương hiệu 20 ca, gồm 375/768/1440 px và chữ 200%.
- 38 kiểm thử PostgreSQL thuộc thương hiệu/danh mục/kho/sản phẩm (thương hiệu 11 ca), cộng 3 unit test audit: đạt. Bao gồm phân quyền, input không hợp lệ, phân trang, cập nhật đồng thời, phiên bản cũ, rollback audit, xóa đồng thời và cạnh tranh gán sản phẩm; lọc thương hiệu độc lập với từ khóa/mã sản phẩm.
- Chrome tại 8080: 5 nhóm acceptance đạt với API và PostgreSQL thật. Tạo → đổi tên → chọn thương hiệu trong form sản phẩm → mở kho/sản phẩm/cửa hàng; responsive; xung đột; hủy/xác nhận xóa; sản phẩm được gán trong lúc hộp thoại xóa đang mở. Không có lỗi JS/overflow hay phản hồi API bất thường. Chỉ fixture riêng được sửa/dọn, tồn kho trước/sau bằng nhau.
- Báo cáo và ảnh ở `.tools/brands-acceptance/`; chạy lại bằng `node tools/verify-admin-brands-browser.cjs`. Log build/test ở `.tools/brands-build.log`, `.tools/brands-regression.log`.

Migration đã áp dụng local và database `_test`; các môi trường khác cần `prisma migrate deploy` trước khi chạy backend mới. Chưa triển khai production hoặc kiểm thử tải production/thiết bị thật/Safari. Cảnh báo deprecation hiện có của `pg` về query trên kết nối đang bận vẫn xuất hiện ở kiểm thử đồng thời; tất cả kiểm thử đã qua, chưa nâng dependency trong đợt này. Không có lỗi chức năng còn biết trong phạm vi đã kiểm chứng.

### Hoàn thiện quản lý danh mục (24/10/2026)

Phạm vi đã triển khai và kiểm chứng: `/#/admin/categories`, `/#/admin/categories/:id`, API quản trị danh mục, form taxonomy dùng chung và đồng bộ với sản phẩm/kho/cửa hàng. Giữ Flutter/Riverpod/go_router, NestJS/Prisma/PostgreSQL, font/token/component quản trị và các thư viện hiện có. Đợt hoàn thiện bổ sung migration `20261024170000_category_deletion` cho sự kiện audit `CATEGORY_DELETED`, không thêm bảng/cột nghiệp vụ hoặc dependency. Migration đã áp dụng database local và `_test`; môi trường triển khai khác cần chạy `prisma migrate deploy` trước khi khởi động backend mới.

**Kết quả phân tích và lỗi đã xử lý**

| Phát hiện / nguyên nhân | Xử lý |
| --- | --- |
| Trang cũ chỉ liệt kê thẻ và phân trang bằng state cục bộ; chưa tìm kiếm, lọc, sort, thống kê, chi tiết | Workspace có bảng desktop/thẻ mobile, lưu bộ lọc và trang vào URL, GET summary/detail và truy vấn server |
| Không phân biệt tổng sản phẩm với sản phẩm công khai | Hai chỉ số riêng, tính trên từng Product; SKU/ảnh không làm đếm trùng. Danh mục trống vẫn quản lý được |
| Chỉ kiểm tra expectedName; chuỗi sửa A → B → A có thể nhận bản cũ | Bổ sung expectedUpdatedAt tùy chọn, UI luôn gửi phiên bản từ API; timestamp tăng kể cả cập nhật trong cùng mili giây; kiểm tra/ghi trong Serializable transaction |
| Slug trùng chỉ trả lỗi chung, buộc tải lại form | Trả 409 TAXONOMY_SLUG_EXISTS, lỗi ngay trường slug; sửa giá trị rồi lưu lại được |
| Form chưa gợi ý slug tiếng Việt, chưa thông báo thành công | Tạo slug không dấu từ tên, hỗ trợ Đ/đ và dấu tổ hợp; người dùng tự sửa slug thì giữ giá trị đó; toast sau API xác nhận |
| Phản hồi mutation đến sau timeout có thể để cache cũ | Dùng callback hoàn tất muộn của ApiClient để invalidate danh mục/tham chiếu/catalog; không tự phát lại mutation hay báo thành công khi chưa xác nhận |
| Kiểm tra quyền chỉ trước service; request không đổi tên vẫn ghi audit | Kiểm tra actor đang hoạt động và catalog.write trong transaction; no-op không ghi thêm sự kiện; audit lỗi thì rollback |

**Chức năng và hợp đồng API**

- UI: ID rút gọn (UUID đầy đủ ở chi tiết), tên/slug, số sản phẩm, tình trạng xuất hiện ở cửa hàng, thời gian UTC+7 và thao tác chi tiết/đổi tên. Có loading skeleton, retry, empty state, validation, khóa nút khi lưu, xử lý xung đột và phiên kết thúc. Tái sử dụng card, metric, status, pager và mutation dialog hiện có.
- Tìm kiếm tên tiếng Việt có/không dấu, slug và UUID đầy đủ. `%`, `_`, `\` là ký tự tìm kiếm thường, không thành SQL wildcard. Query dùng tham số; sort chỉ lấy từ danh sách cho phép.
- `GET /admin/categories`: giữ `items/total/page/limit` và `_count.products`; bổ sung `publishedProducts`. Query `q` tối đa 100 ký tự, `coverage=empty|populated|published|unpublished`, `sort=name_asc|name_desc|newest|oldest|updated|products_asc|products_desc`, `page` 1–10000, `limit` 1–100. UI chọn 20/50/100; mặc định API cũ 12 được giữ nguyên. Tổng và trang đọc trong RepeatableRead, có ID làm tiêu chí sắp xếp phụ.
- `GET /admin/categories/summary`: tổng danh mục, chưa có sản phẩm, có ở cửa hàng, tổng sản phẩm được phân loại và tổng sản phẩm công khai. Thẻ là số liệu toàn bộ database, không phải chỉ trang đang xem.
- `GET /admin/categories/:id`: thông tin, ngày tạo/cập nhật, tổng sản phẩm và số công khai; UUID sai trả 400, không tồn tại trả 404.
- `POST /admin/categories`: tên trim, không rỗng, tối đa 100 ký tự; slug hợp lệ và duy nhất. Hai request cùng slug chỉ một lần tạo thành công. Tên có thể trùng nếu slug khác, đúng ràng buộc hiện tại.
- `PATCH /admin/categories/:id`: đổi tên bằng expectedName và expectedUpdatedAt. Slug/quan hệ sản phẩm bất biến. Bản cũ trả 409, người dùng phải tải lại. ADMIN/MANAGER theo catalog.read/catalog.write; CUSTOMER/SUPPORT/WAREHOUSE không có quyền quản lý danh mục.
- `DELETE /admin/categories/:id`: bắt buộc body `{ expectedUpdatedAt: "<ISO timestamp>" }`, quyền `catalog.write`. Kiểm tra lại actor trong transaction Serializable, khóa Category, kiểm tra phiên bản và mọi sản phẩm liên quan kể cả sản phẩm ẩn. Danh mục chứa sản phẩm trả 409 `CATEGORY_IN_USE`; phiên bản cũ trả 409; không tồn tại trả 404. Chỉ xóa danh mục trống, không chuyển hoặc xóa sản phẩm. Xóa và ghi audit cùng transaction; lỗi audit rollback. Audit giữ target ID và slug, có nhãn tiếng Việt trong trang hoạt động.
- Query tổng hợp tại DB theo lô, không truy vấn lặp từng danh mục/sản phẩm và không đưa toàn bộ danh sách lên client để lọc. Tham chiếu sản phẩm tiếp tục dùng API danh mục phân trang sẵn có.

**Hoàn thiện giao diện và dữ liệu trong đợt bổ sung**

- Danh sách có số sản phẩm công khai ở từng dòng và thao tác xóa trên desktop/mobile. Danh mục chứa sản phẩm mở thông báo giải thích và liên kết tới danh sách sản phẩm; danh mục trống mở xác nhận xóa vĩnh viễn. Hộp thoại dùng đúng navigator của dialog trong admin shell; đóng không làm mất trang quản trị.
- Sau tạo thành công, mở chi tiết danh mục vừa tạo và giữ đường dẫn quay lại danh sách/bộ lọc. Response muộn hoặc không chắc chắn không tự điều hướng hay gửi lại lệnh. Slug vẫn bất biến khi đổi tên; luồng thương hiệu dùng chung form được giữ nguyên.
- Trang chi tiết tách thành `category_detail.dart`: tổng quan hai cột trên desktop, xếp dọc trên mobile, số công khai/chưa công khai, tỷ lệ công khai, 6 sản phẩm gần đây, sao chép ID, ngày UTC+7 và thao tác quản lý. Các sản phẩm gần đây lấy từ `recentProducts` của API detail; chỉ tải ảnh đầu và điều kiện hiển thị cần thiết, cùng snapshot với thống kê. Các liên kết mở đúng bộ lọc sản phẩm, sản phẩm chưa công khai, tồn kho và cửa hàng.
- Phân trang API tự giới hạn về trang cuối hợp lệ khi số kết quả giảm; UI đồng bộ URL bằng replace và giữ bộ lọc. Tìm UUID chấp nhận cả chữ hoa. Xóa bộ lọc xóa cả từ khóa đang nhập chưa áp dụng. Danh mục không tồn tại có màn hình phục hồi riêng.
- Sau xóa, làm mới danh sách/thống kê/tham chiếu/catalog; tránh gọi lại chi tiết đã xóa trong lúc đóng route. Xung đột yêu cầu tải lại dữ liệu, không tự phát lại thao tác xóa.

**Đồng bộ và phạm vi nghiệp vụ giữ nguyên**

Category hiện chỉ có `id`, `name`, `slug`, `createdAt`, `updatedAt`; Product bắt buộc thuộc một Category. Danh mục công khai khi có ít nhất một Product bật, ảnh có URL và SKU bật; không phụ thuộc số tồn kho. Đổi tên không đổi categoryId, slug, SKU, tồn kho hoặc dữ liệu giao dịch. Form sản phẩm nhận danh mục mới sau mutation; liên kết từ chi tiết dùng categoryId cho quản trị sản phẩm/kho và slug cho `/shop?category=...`.

**Ngoài mô hình nghiệp vụ hiện có:** phân cấp/tree, parentId, vô hiệu hóa danh mục, đổi slug/redirect slug cũ, upload ảnh danh mục, mô tả, thứ tự và SEO riêng. Không thêm trường hoặc nút giả cho các mục này. Xóa danh mục trống được hỗ trợ như trên. Việc “chưa có ở cửa hàng” là kết quả điều kiện công khai của sản phẩm, không phải trạng thái active của danh mục.

**Kiểm thử thực tế**

| Nhóm | Kết quả |
| --- | --- |
| Backend build; ESLint toàn bộ backend; Prettier các file TS sửa | Qua |
| Flutter analyze; release web build | Qua; analyze không có issue |
| PostgreSQL `_test`: admin-categories, admin, admin-products | **31/31**, gồm **10 kiểm thử danh mục**; thêm **3/3 unit test audit** |
| Flutter: admin_categories_workspace, remote_admin_ui, catalog_categories, admin_products_workspace | **70/70**; bố cục 375/768/1440px, chữ 200%, tạo/đổi tên/xóa, xung đột và bảo vệ danh mục chứa sản phẩm |
| Chrome thật + API 3000 + DB phát triển, frontend tại localhost:8080 | **5 nhóm luồng qua**; `errors=[]`, `unexpectedResponses=[]`, `cleaned=true`; có hủy/xác nhận xóa mobile và sản phẩm được gán sau khi mở xác nhận |

Các kiểm thử backend xác minh list/detail/count, dấu tiếng Việt/ký tự đặc biệt, lọc/sort/phân trang/rỗng, validation, trùng slug đồng thời, tên trùng được phép, hai actor sửa đồng thời, bản cũ A→B→A, no-op, slug bất biến, quyền 401/403, 400/404, rollback khi audit thất bại và tồn kho/liên kết giữ nguyên. Đối chiếu thống kê với số đếm DB và danh mục API công khai.

Kiểm thử bổ sung xác minh xóa có kiểm tra timestamp, chặn sản phẩm ẩn, hai actor xóa đồng thời chỉ có một audit, rollback xóa khi audit lỗi và tranh chấp giữa tạo sản phẩm với xóa danh mục không để lại tham chiếu mất. Kiểm thử Flutter bảo vệ nút xác nhận khỏi gửi trùng, giữ bộ lọc sau xóa, phục hồi 404 và đóng đúng dialog trong shell. Trình duyệt bắt được lỗi navigator khi đóng thông báo bảo vệ; đã sửa và chạy lại toàn bộ thành công.

Flutter kiểm tra 375/768/1440 px, chữ 200%, form/slug/duplicate, giữ query/reset page, chi tiết và payload phiên bản, retry/rỗng, quyền kho, chống double submit và hoàn tất muộn sau timeout không tự gửi lại. Các test cũ về đăng xuất khi đang ghi và cache công khai tiếp tục qua; cập nhật mock summary và cuộn đến điều khiển theo bố cục mới.

Chrome: đăng nhập quản trị thật; tìm kiếm không dấu, lọc, sort, phân trang, reload; thêm/đổi tên và đối chiếu DB; chọn danh mục vừa tạo trong form sản phẩm và lưu; mở sản phẩm, kho và cửa hàng từ danh mục; đối chiếu tồn kho trước/sau; list/detail/dialog trên 375/768/1440; từ chối bản chỉnh sửa cũ và tải lại bản đã thắng. Chỉ fixture của lượt chạy được tạo/sửa/dọn, không checkout/gửi thư hay sửa dữ liệu kinh doanh. Chạy lại bằng `node tools/verify-admin-categories-browser.cjs`, hoặc đặt `ADMIN_TEST_BASE=http://localhost:5173` khi dùng preview riêng. Log/ảnh/report ở `.tools/categories-acceptance/`. Kiểm tra sau dọn ghi nhận 0 sản phẩm/danh mục/tài khoản mang marker categories-qa còn lại, 0 kho âm và 0 SKU thiếu kho tại thời điểm chạy (`data-check.json`).

**Danh sách file của đợt này**

Tạo mới:

- `backend/src/modules/admin/categories-workspace.ts`
- `backend/src/modules/admin/dto/admin-categories-query.dto.ts`
- `backend/test/admin-categories.e2e-spec.ts`
- `frontend/lib/features/admin/remote/categories_page.dart`
- `frontend/lib/features/admin/remote/category_detail.dart`
- `frontend/lib/features/admin/remote/category_widgets.dart`
- `frontend/lib/features/admin/remote/taxonomy_actions.dart`
- `frontend/test/admin_categories_workspace_test.dart`
- `tools/verify-admin-categories-browser.cjs`

Chỉnh sửa:

- `backend/src/modules/admin/admin.controller.ts`
- `backend/src/modules/admin/dto/admin.dto.ts`
- `backend/src/modules/admin/taxonomy.service.ts`
- `backend/src/modules/admin/audit-snapshot.ts`
- `backend/prisma/schema.prisma`
- `backend/prisma/migrations/20261024170000_category_deletion/migration.sql`
- `frontend/lib/features/admin/remote/admin_activity.dart`
- `frontend/lib/app/app.dart`
- `frontend/lib/data/remote_admin.dart`
- `frontend/lib/features/admin/remote/admin_pages.dart`
- `frontend/lib/features/admin/remote/admin_providers.dart`
- `frontend/lib/features/admin/remote/admin_widgets.dart`
- `frontend/lib/features/admin/remote/taxonomy_page.dart`
- `frontend/test/remote_admin_ui_test.dart`
- `docs/admin.md`

Không xóa file source. File build/generated được cập nhật bởi lệnh build; bản sao trước sửa và artifact kiểm thử lưu trong `.tools/` đã ignore. Các thay đổi sẵn có từ đợt quản trị trước được giữ nguyên.

**Giới hạn và vận hành**

- Chưa benchmark dữ liệu cỡ production, kiểm thử tải dài hạn, mobile thiết bị thật, Safari/Firefox hoặc native. Kiểm thử responsive thực tế ở Chrome và Flutter widget; không coi kết quả local là chứng nhận production.
- expectedUpdatedAt tùy chọn để tương thích client cũ. Client chỉ gửi expectedName vẫn được hỗ trợ và không có bảo vệ đầy đủ trước tình huống A→B→A; UI mới luôn gửi timestamp. Ghi trực tiếp DB ngoài API vẫn vượt qua kiểm soát ứng dụng.
- Chưa có realtime đồng bộ giữa nhiều trình duyệt. Mutation làm mới cache cùng phiên; trang đang mở ở phiên khác cần “Tải lại”; thao tác lưu có kiểm tra phiên bản.
- Cảnh báo deprecation `pg` về query trên kết nối đang bận vẫn có; không nâng dependency trong đợt này. Release build JavaScript và Wasm dry run đều qua.
- Giữ phiên Flutter của chủ máy ở **8080**, đã nạp source mới; tải lại trình duyệt để nhận giao diện. API 3000 đã khởi động bằng build mới. Không chạy thêm server trên cổng đang dùng. Chưa triển khai môi trường production hoặc kiểm thử tải production.

## Hoàn thiện trang kho và đối soát — 24/10/2026

Trang `/admin/inventory` tiếp tục dùng Flutter/Riverpod/go_router và API NestJS/Prisma/PostgreSQL hiện có. Danh sách mới có tên sản phẩm mở được chi tiết kho, ảnh/SKU/màu/cỡ/danh mục, tồn kho, cảnh báo và nút nhập kho trực tiếp. Trên màn hình hẹp hoặc chữ lớn, các dòng chuyển sang bố cục dọc. Chuyển giữa tồn kho hiện tại và SKU chưa có kho giữ bộ lọc tìm kiếm/danh mục; bộ lọc lượng không hợp lệ với SKU thiếu kho được bỏ khi chuyển. Trang chi tiết có nút nhập/xuất/kiểm kê rõ ràng, lịch chọn ngày và tổng biến động theo bộ lọc.

- `GET /admin/inventory` bổ sung `summary: { units, lowStock, outOfStock }`, tính trên **toàn bộ kết quả lọc**, không chỉ trang hiện tại. Tổng quan đầu trang vẫn là toàn kho. `sort=attention` xếp lượng tăng dần, rồi tên/SKU/ID để ưu tiên bổ sung hàng và giữ thứ tự ổn định.
- Danh sách và lịch sử giới hạn trang trả về trong khoảng hợp lệ khi số bản ghi giảm; giao diện đồng bộ URL bằng replace, giữ các bộ lọc khác. Không còn danh sách rỗng chỉ vì URL trỏ đến trang vượt tổng hiện tại.
- `GET /admin/inventory/:id/movements` bổ sung `summary: { incoming, outgoing, net }` theo cùng bộ lọc ngày/loại, trong cùng snapshot với count và trang. Đây là tổng biến động đã ghi nhận, không suy ra số dư mở đầu hoặc số dư cuối từ lịch sử cũ.
- `POST /admin/inventory/:id/adjust` nhận thêm `operation?: in | out | count | delta`. Nhập phải có delta dương, xuất phải có delta âm; kiểm kê vẫn gửi chênh lệch cùng expectedVersion. Client cũ không gửi operation được ghi là delta. Operation và movementId nằm trong allowlist audit; lịch sử mới phân biệt nhập/xuất/kiểm kê, dữ liệu cũ giữ nhãn điều chỉnh thủ công.
- Kiểm kê bằng số lượng hiện tại có thông báo riêng và không tạo biến động 0. Form không nhận ký pháp số hex; lý do vẫn bắt buộc 3–200 ký tự. Preview trước/sau có vùng thông báo hỗ trợ trình đọc màn hình. Xóa bộ lọc lịch sử xóa cả ngày sai đang nhập, ngay cả khi chưa áp dụng.
- Giữ kiểm soát quyền ADMIN/MANAGER/WAREHOUSE, transaction/version, rollback khi lỗi audit, chống gửi lặp và buộc tải lại khi kết quả chưa rõ. Lịch sử chỉ đọc; không bổ sung thao tác xóa kho làm mất dấu đơn hàng. SKU mới tạo từ trang sản phẩm, bản ghi kho thiếu được khởi tạo 0 có xác nhận.
- Migration `20261024160000_inventory_audit_lookup` thêm index `AdminAuditEvent(targetId, action)` để tra liên kết lịch sử; đã áp dụng database local và `_test`. Không thêm bảng/cột hoặc dependency. Khi triển khai, chạy `prisma migrate deploy` theo quy trình hiện có trước khi khởi động backend mới.

File trong đợt này:

- Giao diện: `frontend/lib/features/admin/remote/inventory_page.dart`, `inventory_detail.dart`, `inventory_actions.dart`; hai component mới `inventory_rows.dart`, `inventory_overview.dart`; kết nối ở `admin_providers.dart` và `frontend/lib/data/remote_admin.dart`.
- Backend: `backend/src/modules/admin/inventory-workspace.ts`, `admin.service.ts`, `audit-snapshot.ts`, `dto/admin.dto.ts`, `dto/admin-inventory-query.dto.ts`, `backend/prisma/schema.prisma` và migration nêu trên.
- Kiểm thử: `frontend/test/admin_inventory_workspace_test.dart`, `remote_admin_ui_test.dart`, `backend/test/admin-inventory.e2e-spec.ts`, `staff.e2e-spec.ts`, `tools/verify-admin-inventory-browser.cjs`; tài liệu `docs/admin.md`.

Kiểm chứng sau sửa: **65 bài Flutter qua** (kho, sản phẩm, giao diện quản trị); **55 bài PostgreSQL qua** (kho, nhân sự, commerce, returns, shipments, sản phẩm). Phân tích toàn bộ Flutter và ESLint toàn bộ backend sạch; build NestJS, Flutter web release và Wasm dry run thành công. Chrome trên localhost:8080 qua 4 nhóm luồng, bao gồm đăng nhập ADMIN/WAREHOUSE, POST thật, kiểm tra trực tiếp DB và giao diện 375/768/1440px; report `.tools/inventory-acceptance/report.json` có `errors=[]`, `unexpectedResponses=[]`, `cleaned=true`. Bộ Flutter còn kiểm tra 360px và phóng chữ 150%. Dữ liệu giả lập chỉ dùng trong kiểm thử; chức năng chính gọi API thật.

Giới hạn kiểm chứng: đã kiểm tra tại local/database test, chưa triển khai môi trường production hoặc đo tải lớn. Cảnh báo deprecation có sẵn của driver `pg` về query trên kết nối đang bận vẫn xuất hiện trong một số luồng chung; build và các kiểm thử đều qua, chưa nâng driver trong đợt này. Không có lỗi chức năng kho còn biết trong các luồng đã kiểm tra.

## Quản lý tài khoản khách hàng — 24/10/2026

- `/admin/customers` có **Thêm khách hàng**, thao tác nhanh xem/sửa/khóa hoặc mở khóa/xóa ở từng dòng; trên điện thoại dùng nút có nhãn trong thẻ. Hồ sơ khách hàng dùng cùng biểu mẫu và hộp thoại thao tác. Sau tạo mở hồ sơ mới; sau xóa từ hồ sơ quay lại danh sách với bộ lọc trước đó.
- `POST /admin/users`: ADMIN/MANAGER có `customers.manage` tạo tài khoản CUSTOMER đang hoạt động. Nhập tên, email, số điện thoại tùy chọn và mật khẩu 12–128 ký tự; giao diện yêu cầu nhập lại mật khẩu. Chuẩn hóa email/số điện thoại, kiểm tra trùng với mọi tài khoản, băm Argon2id. Không phát phiên đăng nhập khách hàng hoặc gửi email khi quản trị viên tạo tài khoản.
- Form thêm mới và chỉnh sửa có ô **Có quyền truy cập trang quản trị**, mặc định bỏ chọn. Chỉ ADMIN có `staff.manage` được bật. Khi bật phải nhập **Tên đăng nhập quản trị** và chọn **Vai trò quản trị** (mặc định MANAGER; có ADMIN/MANAGER/WAREHOUSE/SUPPORT), kèm mô tả quyền. Người chỉ có quyền quản lý khách hàng thấy ô tích bị vô hiệu hóa với lý do rõ ràng.
- `POST /admin/users` và `PATCH /admin/users/:id` nhận thêm `adminAccess: true`, `adminRole` và `username`. Tên đăng nhập chuẩn hóa chữ thường, dài 3–64 ký tự, cùng quy tắc đăng nhập quản trị; trùng tên trả `USERNAME_ALREADY_EXISTS`. Cấp quyền và sửa hồ sơ thực hiện trong cùng transaction, kiểm tra quyền actor tại thời điểm ghi. MANAGER không thể cấp quyền bằng cách gọi API trực tiếp. Thiếu vai trò/tên đăng nhập hoặc gửi chúng mà không bật `adminAccess` trả 400; trường `role` trực tiếp vẫn bị từ chối.
- Cấp quyền chuyển CUSTOMER thành vai trò nhân sự đã chọn, giữ nguyên ID/mật khẩu/lịch sử đơn và trạng thái khóa. Phiên đăng nhập và mã khôi phục cũ bị thu hồi; tăng phiên bản quyền và ghi audit không chứa mật khẩu/tên đăng nhập. Sau khi lưu, UI mở **Nhân sự & quyền** và lọc theo email vừa lưu. Tài khoản nhân sự đăng nhập trang quản trị bằng tên đăng nhập; mua hàng dùng tài khoản khách riêng theo cơ chế hiện tại. Thu hồi quyền tại Nhân sự & quyền bằng cách đổi vai trò về Khách hàng.
- Kiểm chứng bổ sung cho ô cấp quyền: 28 bài E2E khách hàng/nhân sự/đăng nhập quản trị và 31 bài Flutter khách hàng/nhân sự qua; build backend/web, lint và phân tích tĩnh qua. Trình duyệt thực kiểm tra tạo tài khoản MANAGER bằng ô tích trên màn hình 375px, chuyển đến danh sách nhân sự lọc đúng email, rồi đăng nhập quản trị thành công bằng tên vừa chọn.
- `PATCH /admin/users/:id` và `PATCH /admin/users/:id/status` giữ kiểm tra `expectedUpdatedAt`. Đổi email hoặc trạng thái thu hồi phiên đăng nhập và mã khôi phục cũ. Không thay đổi thông tin giao nhận đã lưu trong đơn hàng.
- **Đặt lại mật khẩu** có tại danh sách (biểu tượng chìa khóa trên desktop, nút có nhãn trên điện thoại) và hồ sơ khách hàng, bên cạnh **Chỉnh sửa**. Hộp thoại hiển thị tên/email khách, nhập mật khẩu mới và xác nhận, nút hiện/ẩn mật khẩu; chỉ gửi khi hai giá trị khớp và dài 12–128 ký tự.
- `POST /admin/users/:id/reset-password` nhận `{ "password": "<mật khẩu mới>", "expectedUpdatedAt": "<ISO timestamp>" }`, yêu cầu `customers.manage`. Server chỉ thay mật khẩu tài khoản CUSTOMER chưa xóa, băm Argon2id, cập nhật `passwordChangedAt` theo đồng hồ database và `updatedAt`, thu hồi tất cả phiên đăng nhập/mã khôi phục trong cùng transaction. Tài khoản đang khóa vẫn bị khóa; không đổi thông tin hồ sơ, quyền hoặc đơn hàng, không gửi email và không phát token. Bản ghi cũ trả `409 CUSTOMER_CONFLICT`; đích nhân sự/đã xóa/không tồn tại trả 404. Quyền actor và vai trò đích được kiểm tra lại dưới khóa transaction.
- Audit đặt lại mật khẩu dùng `STAFF_UPDATED` với cờ `details.after.passwordChanged=true`; giao diện lịch sử ghi **Đặt lại mật khẩu khách hàng**. Không lưu mật khẩu, hash hoặc email trong audit. Hộp thoại chặn gửi lặp khi đang lưu; nếu kết quả chưa rõ hoặc xung đột, yêu cầu tải lại trước lần thử tiếp theo.
- `DELETE /admin/users/:id` nhận body `{ "expectedUpdatedAt": "<ISO timestamp>" }`. Xóa mềm bằng `deletedAt`, đặt `active=false`, thu hồi phiên đăng nhập và mã khôi phục, ghi audit trong cùng transaction. Bản ghi đã thay đổi trả 409; tài khoản nhân viên/không tồn tại/đã xóa trả 404. Hộp thoại hiển thị đúng tên/email và nút đỏ **Xác nhận xóa**; có thể đóng để hủy trước khi gửi.
- Tài khoản đã xóa không xuất hiện trong danh sách, thống kê khách hàng hoặc tìm kiếm nhân sự; không thể mở khóa hay nâng quyền qua API nhân sự. Ràng buộc database buộc bản ghi đã xóa luôn là CUSTOMER không hoạt động. Đơn hàng, thanh toán, hoàn tiền và các dữ liệu liên quan vẫn giữ nguyên. Email và số điện thoại tiếp tục dành cho hồ sơ đã xóa, không dùng lại cho tài khoản mới; đây không phải xóa toàn bộ dữ liệu cá nhân.
- Migration bổ sung: `20261024110000_customer_management`. Audit tạo/xóa dùng `CUSTOMER_CREATED`/`CUSTOMER_DELETED`, chỉ lưu trạng thái, không chép mật khẩu hoặc dữ liệu liên hệ. Chạy migration và build backend trước khi dùng UI mới.
- Kiểm chứng: bộ E2E khách hàng (11 bài) và nhân sự (10 bài) qua trên database `_test`; 33 bài Flutter khách hàng/repository/nhân sự qua. Build backend, lint các file backend sửa, phân tích tĩnh giao diện và release build web qua. `node tools/verify-customer-management-browser.cjs` kiểm chứng tạo, sửa, khóa/mở khóa trên desktop 1440px và hủy/xác nhận xóa trên mobile 375px; dùng tài khoản dùng thử riêng và dọn sau chạy. Ảnh/report ở `.tools/customer-management-acceptance/`.
