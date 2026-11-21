# Wearly — Khu vực tài khoản

Áp dụng cho hồ sơ, đơn hàng và chi tiết đơn, đánh giá, sổ địa chỉ, phong cách,
lịch sử thử đồ (trực tuyến và demo), yêu thích và cài đặt tài khoản.

## Thiết kế

Kế thừa palette và font của MASTER.md. Hướng tối giản, phân cấp rõ, khoảng trắng
đều; không áp dụng hero bán hàng, màu hồng/vàng hoặc font mới từ kết quả tìm kiếm
chung của ui-ux-pro-max vì đây là khu vực quản lý tài khoản trong Wearly.

- Tokens thành phần: `frontend/lib/core/design/account_tokens.dart` tham chiếu
  semantic tokens `T`, không khai báo palette riêng.
- Nền canvas, thẻ trắng với đường viền line, góc 6px; màu mận đánh dấu mục chọn.
- Thanh bên 256px, khoảng cách nội dung 32px. Chuyển sang menu mở rộng khi chiều
  rộng khả dụng nhỏ hơn 920px; ngưỡng này tăng theo cỡ chữ hệ thống.
- Giữ gutter toàn trang theo MASTER. Không bó chiều rộng toàn trang.
- Tất cả trang dùng trọn cùng một chiều rộng nội dung bên phải thanh điều hướng.
  Không có giới hạn 840/880px hoặc cột phụ 280px.
- Hồ sơ có ba cột nhập liệu bằng nhau; phong cách có bốn nhóm lựa chọn trực tiếp
  trong lưới 2×2, thu về một cột khi thiếu chiều rộng. Size, mẫu màu, thẻ phong cách
  và ngân sách có trạng thái chọn, nhãn truy cập và hỗ trợ bàn phím. Bản tóm tắt,
  trạng thái chưa lưu, hoàn tác và xác nhận tải lại nằm cùng thẻ đầy chiều rộng.
  Hồ sơ có hai thẻ đầy chiều rộng: thông tin cá nhân và tiện ích tài khoản.
  Sáu lối tắt nằm cùng mặt nền trong lưới 3×2, thu về một cột trên điện thoại;
  không chia thành các thẻ phụ lệch kích thước.
- Cài đặt dùng lưới 2×2 với chiều rộng bằng nhau và chiều cao cân bằng theo hàng.
  AccountGrid đo chiều cao thực tế bằng Table, không cố định chiều cao gây cắt chữ.
- Sổ địa chỉ dùng bốn cột tên gợi nhớ, người nhận, địa chỉ giao hàng và thao tác
  khi vùng nội dung rộng từ 1000px (tăng theo cỡ chữ). Địa chỉ mặc định đứng đầu
  và có nhãn màu mận. Màn hình nhỏ chuyển thành thẻ, giữ đầy đủ địa chỉ dài.
  Hộp chỉnh sửa rộng tối đa 640px, người nhận/điện thoại chia đều hai cột nếu đủ
  chỗ; nút hủy/lưu cùng một hàng và tự xuống dòng. Khung trống cao tối thiểu 360px.
- Thanh công cụ thống nhất: số lượng bên trái, hành động bên phải. Các cột
  thu về một cột cùng lúc khi không đủ chỗ hoặc khi người dùng phóng chữ.
- Đơn hàng dùng năm cột đơn/ngày, sản phẩm, trạng thái, tổng tiền/thanh toán và
  thao tác từ chiều rộng nội dung 1000px (tăng theo cỡ chữ). Thẻ trên điện thoại
  giữ tên sản phẩm đầy đủ, màu, size, số lượng và trạng thái thanh toán. Trạng
  thái có biểu tượng và chữ. Thẻ tìm kiếm cùng các bộ lọc nhanh có số lượng
  nằm trên danh sách; tìm không phân biệt dấu tiếng Việt, hoa/thường hay thứ tự
  từ. Mốc ngày hiển thị theo giờ Việt Nam.
- Đánh giá dùng bốn cột sản phẩm, số sao/ngày viết, nội dung và thao tác khi
  vùng nội dung rộng từ 1000px (ngưỡng tăng theo cỡ chữ). Ảnh 64×84px, tên sản
  phẩm 14px semibold; ngày theo múi giờ Việt Nam. Màn hình nhỏ chuyển thành
  thẻ đầy chiều rộng, nút sửa/xóa có vùng chạm tối thiểu 44px. Không cắt nội dung
  đánh giá dài; ảnh thiếu hoặc sản phẩm ngừng bán có biểu tượng thay thế.
- Tiêu đề 36px trên desktop, 28px trên điện thoại. Nhãn thẻ 18px semibold.
- Lịch sử thử đồ dùng bảng trang phục/kết quả/thời gian/thao tác từ chiều rộng
  nội dung 1000px (tăng theo cỡ chữ); màn hình nhỏ dùng thẻ đầy chiều rộng.
  Ảnh catalog 64×86px, huy hiệu trạng thái có icon và chữ; bộ lọc có số lượng.
  Ảnh riêng tư chỉ tải khi chọn xem, hiển thị dưới đúng lượt thử và được giải
  phóng khi ẩn/đổi bộ lọc/xóa/rời trang. Xóa có xác nhận phạm vi ảnh gốc và mọi
  kết quả liên quan. Giữ trạng thái trống, lỗi lần đầu và lỗi làm mới riêng biệt.
- Thẻ có padding 24px trên desktop, 20px trên điện thoại; khoảng cách lưới 24px.
- Các trang sử dụng chung `AccountFrame`, `AccountCard`, `AccountNotice`,
  `AccountEmptyState`, `AccountLoading`, `AccountLink`, `AccountGrid` và `AccountToolbar`.

## Tương tác

Giữ nguyên route, API, xác thực, kiểm tra dữ liệu và trạng thái lưu hiện có.
Menu có icon + chữ, semantics selected, focus của Material; đăng xuất tách bằng
đường phân cách. Trên điện thoại, menu đóng mặc định, mở bằng chạm hoặc bàn phím.
Biểu mẫu có nhãn, lỗi gần trường, trạng thái đang lưu và thông báo kết quả.
Email hồ sơ chỉ đọc. Không thêm số liệu, cấp thành viên hay ưu đãi giả.
Thông tin giới hạn lưu ảnh và dữ liệu demo được giữ nguyên.

Hồ sơ cá nhân (`/account`) hiển thị rõ trạng thái đã lưu/chưa lưu/đang lưu/lỗi.
Chỉ bật lưu và hoàn tác khi dữ liệu thay đổi; bỏ khoảng trắng đầu/cuối trước
khi so sánh và gửi. Hoàn tác khôi phục dữ liệu lần lưu thành công gần nhất,
xóa lỗi kiểm tra trường và không gọi API. Số điện thoại tùy chọn có thể xóa.
Lỗi lưu giữ nguyên bản nháp để thử lại; email chỉ đọc và có chú thích.
Thông báo giải thích hồ sơ không thay đổi sổ địa chỉ hay đơn hàng đã đặt.
Khóa nhập, gửi lại và lối tắt trong lúc lưu; biểu mẫu tách theo phiên người dùng
để phản hồi muộn không ghi đè thông tin của người đăng nhập sau.
Nếu provider cập nhật hồ sơ khi đang có bản nháp, yêu cầu hoàn tác về dữ liệu
mới trước khi lưu tiếp. API hồ sơ hiện không có phiên bản để kiểm tra xung đột
giữa hai tab; không mô tả đây là cơ chế ngăn ghi đè đồng thời từ máy chủ.

Đơn hàng (`/account/orders`) phân biệt tải lần đầu với cập nhật/tải thêm: giữ
danh sách và bộ lọc khi đang tải hoặc khi cập nhật lỗi, kèm thông báo dữ liệu cũ
và nút thử lại đúng thao tác. API trả tối đa 100 đơn mỗi trang. Khi chưa tải đủ,
hiển thị số đã tải/tổng và nêu rõ phạm vi tìm kiếm, số lượng trạng thái; không
kết luận toàn bộ tài khoản không có kết quả từ một trang. Cache chi tiết tách
khỏi các ID trong danh sách để việc tải lại trang đầu không làm mất đơn cũ đang
mở. Đổi mã đơn phải tải lại đúng chi tiết; lỗi 404 có lối về danh sách.
Hủy đơn đang chờ có xác nhận kèm mã đơn, khóa gửi lặp, đồng bộ trạng thái sau
lỗi/xung đột. Không cho hủy hoặc khởi tạo thanh toán từ chi tiết chưa cập nhật
được; các yêu cầu thanh toán/hoàn tiền vẫn theo cơ chế xác thực hiện có.

## Kiểm tra

Đánh giá (`/account/reviews`) tìm kiếm theo tên sản phẩm/nội dung và lọc số sao
trên máy chủ, áp dụng cho toàn bộ lịch sử. Các điều kiện kết hợp, đặt lại về
trang đầu khi đổi bộ lọc, giữ nguyên khi đổi chiều rộng màn hình. Đóng hoặc
lưu hộp thoại không tự nhảy trang; xóa mục cuối điều chỉnh về trang hợp lệ.
Hộp thoại có tên sản phẩm, số sao hiện chọn, xác nhận bỏ bản nháp và khóa gửi
lặp. Cập nhật lỗi giữ danh sách để đọc, khóa sửa/xóa cho đến khi tải lại thành
công; không tự thử lại khiến thông báo lỗi biến mất. Phiên khách hàng đổi phải
xóa trạng thái cũ. Tên sản phẩm đã ẩn không được dùng để trả kết quả tìm kiếm.

Kiểm tra 375/768/1440/1920/2560px và cỡ chữ lớn; điều hướng đủ tám mục; hồ sơ, địa chỉ,
phong cách, đơn hàng, đánh giá và yêu thích qua các kiểm thử chức năng hiện có.
Kiểm tra bản web bằng trình duyệt và ảnh chụp, không chỉ dựa vào phân tích mã.

Đã xác minh ngày 23/10/2026:

- `flutter analyze --no-pub`: không có lỗi/cảnh báo.
- 91 kiểm thử liên quan đạt, gồm kiểm thử hồi quy đo độ rộng, căn mép, độ cao
  thẻ và cột tại 1440/1920/2560px trong `frontend/test/account_layout_test.dart`.
- Build web release với API trực tuyến thành công.
- `node tools/verify-account-design-browser.cjs`: đủ 8 trang ở 375/768/1440/1920/2560px,
  reduced motion, một heading cấp 1 mỗi trang; menu điện thoại và nút lưu khi
  xoay ngang 812×375 hoạt động. Hồ sơ, địa chỉ và phong cách lưu qua API thật.
- Ảnh chụp và báo cáo tại `.tools/account-design-acceptance/`; tài khoản kiểm
  thử tạm được xóa sau kiểm tra. Không có lỗi trình duyệt được ghi nhận.

Kiểm tra bổ sung hồ sơ ngày 24/10/2026:

- `frontend/test/account_profile_test.dart`: trạng thái chỉnh sửa, hoàn tác,
  kiểm tra trường, lưu lỗi/thử lại, khóa gửi lặp, đổi tài khoản lúc đang lưu,
  cập nhật provider và sáu cấu hình chiều rộng/cỡ chữ (bao gồm 200%).
- `node tools/verify-profile-browser.cjs`: API thật trên 8080; hỗ trợ
  `PROFILE_TEST_BASE=http://localhost:5173` để kiểm tra bản release. Kiểm tra
  lưu bằng bàn phím, tải lại trình duyệt, xóa điện thoại tùy chọn, lỗi 503,
  yêu cầu chậm, sáu lối tắt và responsive. Mọi ghi dữ liệu dùng khách hàng tạm
  được xóa sau kiểm tra. Ảnh và báo cáo ở `.tools/profile-redesign/`.
- 74 kiểm thử tài khoản/phiên/điều hướng đạt; các kiểm thử hồ sơ và bố cục
  được chạy lại sau tinh chỉnh cuối. Phân tích Dart không có vấn đề và build
  web release thành công. Trình duyệt 8080 đạt chín nhóm kiểm tra, không ghi
  nhận lỗi runtime; đã xem ảnh desktop và điện thoại 320/375px.

Kiểm tra bổ sung đơn hàng:

- `frontend/test/order_history_test.dart`: tìm không dấu/bộ lọc, chống tải trùng,
  cập nhật lỗi giữ dữ liệu, tải thêm/thử lại đúng trang, mở đơn cũ, đổi mã đơn,
  xác nhận hủy/xung đột và responsive có cỡ chữ 200%.
- `node tools/verify-orders-browser.cjs`: dùng khách tạm, sản phẩm ẩn và kho riêng
  để kiểm tra API thật với 101 đơn, tìm kiếm/phân trang, chi tiết, hủy đơn,
  lỗi mạng và các chiều rộng 320–2560px. Tất cả fixture được dọn sau kiểm tra;
  sự kiện mail hủy đơn thử được chặn từ trước, không gửi thư. Ảnh và báo cáo:
  `.tools/orders-redesign/`.
- 52 kiểm thử liên quan đạt. Trình duyệt 8080 đạt đủ sáu nhóm kiểm tra với API
  thật, không có lỗi runtime; đã kiểm tra ảnh desktop/mobile, cỡ chữ 200% trong
  widget tests và màn hình nằm ngang. Phân tích Dart không có vấn đề.

Kiểm tra bổ sung đánh giá:

- 51 kiểm thử Flutter liên quan đạt, gồm bộ lọc/phân trang phía máy chủ,
  giữ trạng thái khi đổi bố cục, tải lỗi, yêu cầu chậm, giữ bản nháp, khóa gửi
  lặp, đổi phiên và cỡ chữ 200%. Phân tích Dart không có vấn đề.
- 8 kiểm thử PostgreSQL E2E đánh giá đạt; bổ sung xác minh tìm/lọc có phân
  trang, cô lập người dùng, ký tự tìm kiếm và sản phẩm ẩn. Backend build/lint đạt.
- `node tools/verify-reviews-workflow-browser.cjs`: sáu nhóm kiểm tra API thật
  trên 8080, 320–2560px và nằm ngang, không có lỗi runtime. Tài khoản, đơn,
  sản phẩm và đánh giá thử được dọn sau kiểm tra. Ảnh/báo cáo nằm tại
  `.tools/reviews-workflow/`; hỗ trợ `REVIEWS_TEST_BASE` cho bản release 5173.

Kiểm tra bổ sung sổ địa chỉ:

- Giữ bố cục bảng/thẻ, bổ sung tải lại và phản hồi trong trang. Tải lỗi giữ
  danh sách cũ, khóa thay đổi; form có giới hạn nhập, trạng thái chưa thay đổi,
  bảo vệ bản nháp, xử lý mất phản hồi và ẩn nội dung khi đổi phiên.
- Máy chủ chọn địa chỉ mặc định đầu tiên và địa chỉ thay thế sau xóa trong
  transaction có khóa user; không phụ thuộc một PATCH bổ sung từ trình duyệt.
- 72 kiểm thử Flutter liên quan và 5 kiểm thử PostgreSQL E2E đạt, gồm
  checkout chọn địa chỉ chủ động, tương thích phong cách, cỡ chữ200% và đổi phiên.
  Phân tích Dart và lint backend không có vấn đề.
- `node tools/verify-addresses-workflow-browser.cjs`: sáu nhóm kiểm tra với API
  thật trên8080, 320–2560px và nằm ngang, không có lỗi runtime; tài khoản thử
  riêng được dọn sau chạy. Ảnh/báo cáo ở `.tools/addresses-workflow/`.

Kiểm tra bổ sung yêu thích:

- Danh sách `/wishlist` tìm không dấu trên toàn bộ sản phẩm đã lưu, lọc còn
  hàng/hết hàng/ngừng bán và sắp xếp giá. Từ khóa, bộ lọc và trang nằm trong
  URL; xóa mục cuối tự sửa về trang hợp lệ. Placeholder giữ đúng vị trí lưu
  và không tiết lộ thông tin sản phẩm ẩn. Nút chọn size có nhãn rõ ràng.
- Tải lại hoặc thay đổi thất bại giữ dữ liệu cũ để đọc, khóa thao tác đến khi
  đối soát thành công. Phản hồi ghi đến muộn tự tải lại đúng phiên tài khoản.
- Hộp chọn size dùng tồn kho thật, chặn gửi lặp và đóng khi đang gửi. Nếu chưa
  xác nhận được thêm giỏ, nút kiểm tra chỉ đọc giỏ, không tự gửi thêm lần nữa.
  Hộp đang mở ngừng thao tác khi tài khoản thay đổi; thêm giỏ vẫn giữ yêu thích.
- 58 kiểm thử Flutter liên quan và 3 kiểm thử PostgreSQL E2E đạt, gồm tìm kiếm
  xuyên trang, mất phản hồi, đổi phiên và bố cục 320px/cỡ chữ 200%.
- `node tools/verify-wishlist-workflow-browser.cjs` kiểm tra API thật với khách,
  sản phẩm và kho thử riêng, dọn sau chạy. Hỗ trợ `WISHLIST_TEST_BASE` cho 5173;
  ảnh/báo cáo nằm trong `.tools/wishlist-workflow/`.
- Trình duyệt 8080 đạt cả năm nhóm kiểm tra API thật, không có lỗi runtime;
  đã xem ảnh desktop, điện thoại 320px và hộp chọn size. Phân tích Dart sạch,
  bản web release build thành công.

Kiểm tra bổ sung cài đặt tài khoản:

- Giữ bốn nhóm cài đặt và hai cột đồng chiều cao trên desktop; thông tin email,
  họ tên, điện thoại có nhãn, đọc được bằng trình đọc màn hình và sao chép email.
  Nêu rõ điện thoại chưa bổ sung; các liên kết đưa đến đúng màn hình quản lý.
- Tải lại thông tin qua `GET /users/me`, cập nhật hồ sơ dùng chung; lỗi giữ dữ
  liệu cũ và có thử lại. Chặn yêu cầu trùng, giữ trạng thái khi đổi bố cục và
  không để phản hồi của tài khoản cũ thay hồ sơ tài khoản mới.
- Trang, thanh bên và menu dùng chung trạng thái đăng xuất. Lỗi giữ thông báo
  trong trang; yêu cầu đang chạy khóa tất cả nút đăng xuất, hoàn tất vẫn chuyển
  về đăng nhập sau khi nút ban đầu bị dựng lại do thay đổi kích thước màn hình.
- Luồng đổi mật khẩu vẫn xác nhận mã email, điền sẵn email tài khoản và có
  đường trở về cài đặt. Không thêm công tắc hay trạng thái bảo mật giả.
- 70 kiểm thử Flutter liên quan đạt, gồm luồng đổi mật khẩu hoàn chỉnh, lỗi
  tải/đăng xuất, đổi tài khoản và màn hình 320px/cỡ chữ 200%. 10 kiểm thử phiên
  trình duyệt và 14 kiểm thử khôi phục mật khẩu với PostgreSQL/Redis/SMTP giả
  lập cục bộ đạt; không gửi email ra ngoài.
- `node tools/verify-settings-workflow-browser.cjs` dùng khách tạm để kiểm tra
  API thật và dọn sau chạy. Ảnh/báo cáo ở `.tools/settings-workflow/`, hỗ trợ
  `SETTINGS_TEST_BASE` cho bản release tại 5173.
- Trình duyệt 8080 đạt năm nhóm kiểm tra API thật, gồm lỗi mạng, liên kết,
  clipboard và đăng xuất xuyên lần tải lại; không có lỗi runtime. Đã xem ảnh
  desktop/320px và phần phiên đăng nhập. Phân tích Dart sạch, build web release đạt.
