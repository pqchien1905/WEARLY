# Bổ sung các luồng còn thiếu — 16/10/2026

Đã đối chiếu hai tài liệu yêu cầu và giao diện Flutter hiện có. Các trang chính đã tồn tại, nhưng thiếu sự liên kết giữa hồ sơ khách hàng, checkout, lịch sử mua và AI. Đợt này bổ sung trực tiếp các luồng đó, giữ thiết kế Wearly và mock repositories.

## Những gì đã bổ sung

| Khoảng trống | Giao diện / hành vi mới |
|---|---|
| Chưa có sổ địa chỉ dùng lại | `/account/addresses`: thêm/sửa/xóa, xác nhận xóa, mặc định, tối đa5 địa chỉ, validation và phản hồi lỗi |
| Checkout phải nhập lại | Chọn địa chỉ đã lưu để điền tên/điện thoại/địa chỉ; email chỉ điền nếu đang trống. Không tự ghi đè nội dung đang nhập |
| Chưa lưu sở thích thời trang | `/account/style`: size, phong cách, màu, ngân sách; lưu rồi áp dụng bằng nút trong Stylist |
| Danh sách đơn còn sơ sài | Tìm mã/tên sản phẩm, lọc trạng thái, xóa bộ lọc, ngày đặt/tổng tiền; chi tiết có người nhận, SKU, giá và tiến trình hiện tại |
| Khó tìm lại kết quả Try-On | `/account/try-ons`: danh sách tối đa20 kết quả, mở kết quả/trang phục, xóa riêng hoặc xóa toàn bộ có xác nhận |
| Sản phẩm chưa dẫn sang Stylist theo ngữ cảnh | Nút “Phối đồ cùng AI” đưa tên và phong cách sản phẩm vào ô yêu cầu để người dùng sửa/gửi |

Điều hướng tài khoản dùng chung, tự xuống dòng trên điện thoại. Các trang có trạng thái trống, chưa đăng nhập, loading và lỗi thích hợp. Tóm tắt tiền đã sửa tràn ngang khi dùng màn hình320px và cỡ chữ150%.

## Code và ranh giới dữ liệu

- `domain/account_details.dart`: models và AccountDetailsRepository.
- `data/mock_account_details.dart`: CRUD async, validation, default và snapshot bất biến.
- `app/account_details.dart`: provider theo email phiên; completion guard ngăn save cũ khôi phục dữ liệu sau logout/đổi tài khoản, trả lỗi nếu phiên đã đổi.
- `features/account`: navigation/frame, address/style/history và OrdersPage tách riêng khỏi auth/profile.
- Checkout/Stylist/Product Detail/Try-On dùng lại contracts và components hiện có; không thêm dependency.

Sổ địa chỉ và sở thích nằm trong bộ nhớ phiên tài khoản, bị xóa khi đăng xuất hoặc tải lại. Đơn hàng và lịch sử thử đồ thuộc tab demo, được ghi rõ trên UI, chưa phải lịch sử có phân quyền theo người dùng. Lịch sử Try-On chỉ giữ mã phiên, slug và SKU; không giữ ảnh cá nhân, filename hay ảnh AI. Tiến trình đơn chỉ phản ánh trạng thái hiện tại; không tạo mốc giao hàng hoặc thời gian giả.

## Kiểm chứng

- `flutter analyze`: không có issue, exit0 — [log](qa/journeys-analyze.log).
- `flutter test --reporter expanded`: **174/174 pass** — [log](qa/journeys-tests.log). Thêm23 unit/widget tests: CRUD/default/cap, lỗi/retry, signout race, address picker không ghi đè, style apply, history delete, order search/status/cancellation/missing ID, responsive320/768/1440 với chữ150% và tên sản phẩm dài.
- Build release web thành công, exit0 — [log](qa/journeys-build.log).
- **59 Chrome checks**:15 luồng mới trong [browser-account-journeys.json](qa/browser-account-journeys.json), cùng44 kiểm tra cũ qua5 suites. Các kết quả có `errors: []` và `externalRequests: []`.
- Review độc lập không có vấn đề chặn; góp ý bổ sung kiểm thử status dropdown đã thực hiện và chạy lại toàn bộ suite.
-10 ảnh mới tại375/1440px. Đã xem bố cục địa chỉ, phong cách, danh sách/chi tiết đơn và lịch sử thử đồ; không thấy chồng lấn ở các ảnh kiểm tra. Đây không thay thế kiểm tra thiết bị thật hoặc screen reader đầy đủ.

## Ảnh tham chiếu

| Giao diện | Desktop | Mobile |
|---|---|---|
| Sổ địa chỉ | [1440](qa/screenshots/journeys-addresses-1440.png) | [375](qa/screenshots/journeys-addresses-375.png) |
| Hồ sơ phong cách | [1440](qa/screenshots/journeys-style-1440.png) | [375](qa/screenshots/journeys-style-375.png) |
| Đơn hàng | [1440](qa/screenshots/journeys-orders-1440.png) | [375](qa/screenshots/journeys-orders-375.png) |
| Chi tiết đơn | [1440](qa/screenshots/journeys-order-detail-1440.png) | [375](qa/screenshots/journeys-order-detail-375.png) |
| Lịch sử thử đồ | [1440](qa/screenshots/journeys-history-1440.png) | [375](qa/screenshots/journeys-history-375.png) |

## Những phần vẫn còn thiếu so với sản phẩm thương mại

Ảnh thật theo từng màu/góc chụp; đánh giá sản phẩm; quy trình yêu cầu đổi trả/hoàn tiền; mã ưu đãi có tính toán và điều kiện dùng; tích hợp vận chuyển. Backend/auth/RBAC, dữ liệu lâu dài, thanh toán và AI thật chưa được triển khai theo phạm vi đã thống nhất. Không coi toàn bộ Master Prompt là hoàn tất production. AccountDetailsRepository đã chuẩn bị để thay adapter NestJS sau này; xem api-contracts-frontend.md.

Preview: http://127.0.0.1:4173. Đăng nhập demo rồi mở thanh điều hướng tài khoản để thử. Không tạo commit vì workspace không có Git repository; không triển khai công khai.
