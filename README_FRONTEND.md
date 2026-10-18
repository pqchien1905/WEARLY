# Wearly — Fashion AI Commerce frontend

Flutter Web + Dart, giao diện tiếng Việt. Storefront, Stylist, phòng thử và Admin dùng chung Design System. Bản demo chạy hoàn toàn bằng dữ liệu trong bộ nhớ; không có backend, database, thanh toán hoặc AI thật.

## Chạy ngay trong workspace Windows này

```powershell
# Tại D:\Fashion Shop
.\tools\frontend.ps1 run
```

Script dùng Flutter/Git portable trong `.tools` nếu có, hoặc Flutter đã cài trong PATH. Chrome cần được cài. Bản release đang được phục vụ tại **http://127.0.0.1:4173** trong phiên phát triển này. Nếu server đã dừng:

```powershell
.\tools\frontend.ps1 build
.\tools\frontend.ps1 preview
```

Preview là máy chủ file tĩnh phục vụ build Flutter, không phải backend nghiệp vụ. Không cần API key hoặc `.env`.

## Trên máy khác

Cài Flutter stable và Git theo [hướng dẫn Flutter](https://docs.flutter.dev/install/manual). Phiên kiểm thử dùng Flutter **3.47.7**, Dart **3.13.5**, Chrome Windows. `pubspec.lock` khóa dependencies đã chạy.

```sh
cd frontend
flutter pub get
flutter run -d chrome --dart-define=DEMO_MODE=true
flutter analyze
flutter test --reporter expanded
flutter build web --release --dart-define=DEMO_MODE=true
```

Đầu ra: `frontend/build/web`. Phục vụ qua HTTP, không mở trực tiếp `index.html` bằng file explorer. Hash routes hỗ trợ static hosting không cần rewrite. Nếu triển khai dưới thư mục con, dùng `--base-href=/ten-thu-muc/`.

## Điểm bắt đầu

| Màn hình | URL |
|---|---|
| Home | `/#/` |
| Catalog | `/#/shop` |
| Product Detail chuẩn | `/#/products/nep-1` |
| Stylist | `/#/ai-stylist` |
| Phòng thử | `/#/virtual-try-on?product=nep-1` |
| Tài khoản | `/#/account` |
| Sổ địa chỉ / hồ sơ phong cách | `/#/account/addresses`, `/#/account/style` |
| Đơn hàng / lịch sử thử đồ | `/#/account/orders`, `/#/account/try-ons` |
| Admin | `/#/admin` |
| Component gallery | `/#/design-system` |
| Bộ sưu tập riêng | `/#/collections/everyday` |
| Liên hệ / FAQ | `/#/contact`, `/#/faq` |
| Lỗi quyền mô phỏng | `/#/403` |

Thử mua: chọn M ở sản phẩm đầu tiên → thêm giỏ → checkout → dùng dữ liệu liên hệ minh họa → xác nhận demo. Đơn mới xuất hiện ngay tại account và Admin. Giá 490.000đ + phí tiêu chuẩn 30.000đ = 520.000đ.

Đăng nhập demo → Sổ địa chỉ để thêm/sửa/xóa, chọn mặc định (tối đa 5 địa chỉ). Checkout chỉ điền địa chỉ sau khi bạn chọn, không ghi đè nội dung đang nhập. Hồ sơ phong cách lưu size/màu/phong cách/ngân sách; trong Stylist chọn “Dùng hồ sơ phong cách” để áp dụng. Các lựa chọn này được xóa khi đăng xuất hoặc tải lại trang.

Đơn hàng hỗ trợ tìm theo mã/tên sản phẩm, lọc trạng thái và xem tiến trình hiện tại. Lịch sử thử đồ chỉ lưu tối đa 20 mã kết quả/trang phục trong tab, có mở lại và xóa; không lưu ảnh cá nhân. Xem [báo cáo bổ sung giao diện](docs/account-journeys-2026-10-16.md).

Thử AI: gửi yêu cầu Stylist, chỉnh ngân sách/size/phong cách/màu. Trong phòng thử, chọn sản phẩm + size, chọn JPEG/PNG, tích đồng ý và chạy. Kết quả là placeholder có nhãn rõ, không biến đổi ảnh. Mở “Kịch bản kiểm thử demo” để thử error/timeout. Xóa ảnh hoặc rời route giải phóng tham chiếu và cache ảnh.

Admin cho phép tạo/sửa/xóa sản phẩm, thêm/xóa biến thể màu–size, chỉnh giá/tồn kho, xem và đổi trạng thái đơn. Khuyến mãi là cấu hình demo; nội dung là bản nháp. Chúng chưa áp dụng vào checkout hay xuất bản storefront. Cài đặt có giả lập offline và reset phiên.

## Cấu trúc và thay đổi

- `lib/app/config.dart`: tên thương hiệu, email, phí ship, demo flag. Tên trong HTML/manifest là metadata build, cập nhật cùng config khi đổi thương hiệu.
- `lib/core/design/tokens.dart`: palette, font, grid, theme. [MASTER.md](design-system/fashion-ai-commerce/MASTER.md) là nguồn chuẩn thiết kế.
- `lib/core/widgets`: buttons, fields, states, shell, cards, selectors.
- `lib/domain`: hợp đồng catalog/commerce/AI; `lib/data`: mock implementations và fixture 32 sản phẩm / 256 SKU ban đầu.
- `lib/app/*providers*`: nơi thay repository bằng adapter NestJS. [Kiến trúc](docs/frontend-architecture.md), [API contracts](docs/api-contracts-frontend.md).
- `assets/images`, `assets/fonts`: ảnh và fonts local. [Nguồn tài sản](frontend/assets/ATTRIBUTION.md).

`DEMO_MODE=false` chưa có adapter production và không bật dịch vụ thật. Không dùng bản frontend này như hệ thống đăng nhập/quản trị có bảo mật.

## Kiểm thử và bàn giao

```powershell
.\tools\frontend.ps1 check
# Browser checks dùng Playwright local tại .tools/browser (hoặc npm install --prefix .tools/browser playwright)
.\.tools\node-v24.22.0-win-x64\node.exe tools/browser-flow.cjs
.\.tools\node-v24.22.0-win-x64\node.exe tools/browser-mobile.cjs
.\.tools\node-v24.22.0-win-x64\node.exe tools/browser-account.cjs
.\.tools\node-v24.22.0-win-x64\node.exe tools/browser-refinement.cjs
.\.tools\node-v24.22.0-win-x64\node.exe tools/browser-polish.cjs
.\.tools\node-v24.22.0-win-x64\node.exe tools/screenshots.cjs
.\.tools\node-v24.22.0-win-x64\node.exe tools/contrast.cjs
```

Browser scripts yêu cầu preview ở port 4173, Chrome tại đường dẫn mặc định Windows. Kết quả lưu trong `docs/qa`. Widget tests dùng engine thử nghiệm; kiểm tra upload thật được chạy riêng trên release Chrome để phát hiện khác biệt nền tảng.

Đợt hoàn thiện giao diện16/10/2026: **151/151 Flutter tests**, analyzer không có issues. Đã tinh chỉnh hero/ảnh, catalog, điều hướng, footer, tài khoản, checkout và bảng Admin; thêm motion160/220ms và reduced-motion support. Xem [báo cáo giao diện và kiểm chứng](docs/visual-polish-2026-10-16.md). Các sửa lỗi nghiệp vụ trước đó tại [báo cáo refinement](docs/refinement-2026-10-16.md). Bộ ảnh nhiều góc/màu thực tế vẫn cần bổ sung.

Release build thành công; **44 Chrome checks** đạt, không browser errors/external requests. Bộ ảnh mới có52 reference ở375/768/1440/1920px với prefix `polish-`, cùng ảnh các trạng thái tương tác. Bản preview4173 phục vụ build mới nhất.

- [Báo cáo P0–P4](docs/milestones.md)
- [Checklist Pass / Fail / Not tested](docs/frontend-acceptance.md)
- [Visual QA và ảnh chụp](docs/visual-qa.md)
- [SEO và giới hạn phát hành](docs/seo-strategy.md)

Skill đã đọc và áp dụng: `.agents/skills/dev-flow/SKILL.md`, **`.agents/skills/frontend-design/SKILL.md`** (bản đã cài trong workspace). Hai concept được so sánh trước khi chọn “Tủ đồ đương đại”. Các file Design System được viết thủ công; không dùng generator hay CLI UI UX Pro Max. Home, Catalog, Detail được dựng và kiểm tra ảnh trước khi mở rộng các nhóm màn hình.

Tài liệu nghiệp vụ thực tế có tên `fashion_ai_commerce_agent_spec (1).md`; file không có hậu tố `(1)` không tồn tại. Master prompt frontend-first được ưu tiên khi phạm vi xung đột.
