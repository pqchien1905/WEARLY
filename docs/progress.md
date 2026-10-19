# Execution ledger — 2026-10-15-fashion-frontend

P0 in progress: source specifications and installed frontend-design read. Two concepts evaluated; A selected. Documents written. Toolchain detection: Chrome available; Flutter, Git, Node not in PATH.

Ruling: implement in the explicitly requested empty workspace; no existing Git branch to isolate. Preserve source documents.
Ruling: repository models are shared by storefront/admin; same variant pricing used in catalog/cart/checkout. No backends created.

## Checkpoint — 2026-10-16

User requested the current interface for review, with refinement to continue later. Preview confirmed HTTP 200 at http://127.0.0.1:4173. Latest release build succeeded after the shell semantics fix. Automatic opening of Chrome was blocked by execution policy; user can open the preview link directly.

Implemented: P0 design system/reference screens; P1 storefront/cart/checkout; P2 mock Stylist/Try-On; P3 account/Admin. P4 audit and documentation are underway. 112 Flutter tests passed before the final semantics wrapper change. Desktop browser flow: 9 checks passed. Mobile browser flow after semantics fix: 6 checks passed, zero browser errors and zero external requests. Local CanvasKit and font fallback included.

Resume: final analyze/tests after last changes; rerun desktop browser flow; review final screenshots; finish docs/visual-qa.md, docs/frontend-acceptance.md and P1–P4 milestone reports. README_FRONTEND.md, architecture, API contracts, SEO strategy, code-review notes and asset attribution are written. All services remain in-memory mock; do not claim production readiness.

## Brand update — 2026-10-16

Renamed current brand to Wearly at user request. Updated BrandConfig, web metadata/loading shell, favicon W, demo email, SKU/order prefixes, promotion code and current design/handover documents. Internal product slugs remain stable. Constrained wordmark width to retain mobile layout. Verification: 112/112 tests pass, analyzer clean, release build succeeds; Chrome branding verified and screenshots captured at 375 and 1440, no browser errors. Preview serves the updated build at http://127.0.0.1:4173. Earlier P4 documentation work remains pending for the later continuation.

## Final frontend demo acceptance — 2026-10-16

User resumed refinement. P0–P4 frontend demo work is complete within the documented mock scope. Added asynchronous AccountRepository and feedback/retry, generation guards for reset/logout, controlled order status with cancellation/navigation guards, 150% search layout fix, input contrast token, tonal colors, announcement touch target and static skeleton. Review findings have regression coverage.

Final verification: 123/123 Flutter tests pass; analyzer clean; release build succeeds. Chrome desktop9 + mobile6 + account7 checks pass, errors[] and externalRequests[] in all three runs. Screenshot capture: 7 routes ×4 widths =28 references, no browser errors. All11 measured contrast pairs meet their respective thresholds. Final release served at http://127.0.0.1:4173.

Completed milestone reports, visual QA, acceptance checklist, architecture/API contracts, attribution, SEO boundaries and README. No Git repository exists, so integration/commit/PR workflow does not apply. No real backend/auth/payment/AI added. Remaining production dependencies and untested screen-reader/device/performance coverage are explicit in docs/frontend-acceptance.md; repeated photography and single-photo gallery remain known demo asset limitations.

## Storefront refinement — 2026-10-16

User approved the concrete review fixes. Implemented nullable unlimited price caps, repository color facets, transactional mobile filter draft, quick add, typed color media/gallery, compact Try-On and metadata-only result routes, Contact/FAQ/curated collections, Admin mobile cards. Independent review found image-replacement/run race; fixed with delayed-XFile red/green regression. Eight-color mobile card overflow also reproduced and fixed. Gallery keyboard/result deletion/Admin media preservation verified. Full suite147 passes; final browser/visual verification ongoing.

Ruling: retain licensed source images and explicit missing-color disclosure; no invented alternate-angle/photo variants. Actual complete photography is still outstanding and clearly documented. No backend/AI/auth/payment or persistent storage added.

Final refinement verification:147/147 tests, analyzer clean, release build success;33 Chrome checks pass, errors[]/externalRequests[] in all4 suites.48 reference images plus interaction states captured; final visual corrections applied to sheets/dialogs and curated collection selection. Preview4173 responds200 and serves the final build. Actual per-color/multi-angle photography remains outstanding; all other scoped code tasks completed. See docs/refinement-2026-10-16.md.

## Full-width layout — 2026-10-16

User requested full-screen expansion. Removed the shared1440px page/header cap via T.maxWidth; page gutters remain56/32/20px and local reading/form/modal constraints remain intentional. Admin shell already fills remaining viewport beside sidebar. Full suite147 passes; analyzer/build/browser screenshots are being verified under docs/qa/full-width-*.
Final full-width verification:147/147 tests pass, analyzer clean, web release rebuilt; Chrome Home/Catalog1920px and Home375px captured, browser errors[]. Preview4173 serves updated build. Screenshot: docs/qa/screenshots/full-width-home-1920.png.

## Visual polish — 2026-10-16

Implemented shared motion tokens, finite route fade, clipped image hover and focus outline, reduced-motion handling, button/form/table theme refinement, active navigation, responsive footer, portrait hero and gallery framing, four-column wide catalog, desktop auth editorial layout, bounded checkout reading widths, compact Try-On preview and full-panel Admin tables. Full-width page/header preserved; checkout uses a local1320px form group to avoid excessive distance between fields and summary. Home collection story now spans the page with two editorial columns.

Verification complete:151/151 Flutter tests, analyzer clean, final release web build succeeds.44 Chrome checks across5 suites pass with errors[] and externalRequests[].52 reference screenshots at375/768/1440/1920 plus populated cart/checkout/drawer/footer states reviewed.11 measured contrast pairs pass. Independent read-only review and follow-up found no blocking issues. Preview4173 serves the final build.

Remaining limits:7 repeated stock photos across32 fixtures, incomplete per-color/multi-angle media; all services remain mock; no actual-device frame-time/Safari/iOS/full screen-reader audit. See docs/visual-polish-2026-10-16.md and updated MASTER/COMPONENTS. No Git commits or external deployment performed.

## Account and shopping continuity — 2026-10-16

Added account-scoped address/style repository and AsyncNotifier, shared account navigation, address CRUD/default and explicit checkout selection, saved style application in Stylist, order search/status filter/current progress/detail, metadata-only Try-On history with confirmed removal, and contextual PDP→Stylist prompt. Fixed CartSummary narrow/enlarged-text overflow. Signout/identity-change completion guard prevents stale writes from restoring account data or reporting success.

Verification:174 tests pass, analyzer clean, release build exit0;59 Chrome checks across6 suites have no JS errors or external requests.10 new screenshots at375/1440. Independent review had no blocking findings; added the suggested status-dropdown test and reran full suite. Details and remaining commercial gaps: docs/account-journeys-2026-10-16.md. Preview4173 serves current build; no real services or persistent personal storage added.

## Backend foundation — 2026-10-18

Đã lưu Git baseline, nối origin pqchien1905/WEARLY và chuyển Flutter sang frontend với102 file source/assets giữ nguyên hash. Thêm backend NestJS11/Prisma7,22 models,2 migrations,seed32 products/256SKUs, auth/users/catalog/cart/orders/admin, AI disabled-provider/worker/outbox/storage foundation, Docker Compose và tài liệu.

Node/Flutter portable đã thêm PATH; Git,WSL,Docker Desktop đã cài. Windows yêu cầu restart để bật virtualization features. Compose config đạt nhưng Engine/Redis chưa chạy được trước reboot. PostgreSQL18.4 thật tại55432 được dùng tạm để kiểm thử; backend .env mặc định vẫn theo Docker.

Backend build/lint/unit4 và PostgreSQL E2E10 đạt; Flutter180 test đạt,1 live API test đạt riêng, analyze sạch, Web release build đạt. Independent review không có Critical/Important; hai lỗi nhỏ về null-validation và khôi phục env test đã sửa. npm production dependency audit0 findings. Chi tiết, các lệnh và phạm vi chưa hoàn tất tại [backend-report.md](backend-report.md).

Chưa hoàn tất: Docker/Redis runtime sau reboot, real AI/private upload lifecycle/payment, remote Flutter auth/cart/orders/admin. Không tuyên bố production-ready hoặc toàn bộ tiêu chí master prompt đã đạt.

## Native Windows backend continuation — 2026-10-18

Theo yêu cầu sau restart, đã cài PostgreSQL17.11 + psql + pgAdmin trực tiếp trên Windows. PostgreSQL và Memurai Developer4.1.2 chạy dưới Windows Services Automatic, chỉ nghe loopback5432/6379. Đã tạo role ứng dụng không phải superuser, database wearly/wearly_test UTF8, deploy2 migrations và seed32 products/256SKUs. pgAdmin có kết nối WEARLY sẵn; bundled driver đọc dữ liệu thành công.

Worker được kiểm chứng bằng PostgreSQL và Redis-compatible Memurai thật. Thêm6 worker integration tests, queue namespace độc lập và sửa lỗi provider exception có thể lộ dữ liệu trong Redis failedReason/stacktrace. Kết quả: unit5, commerce10 + worker6 E2E, build/lint và Flutter live catalog1 đều đạt. API readiness200 xác nhận cả database/Redis; Swagger200. Không gọi provider AI thật hay coi test doubles là kết quả AI sản phẩm.

DISM RestoreHealth đã thành công, nhưng SFC báo hệ thống có repair pending cần restart tiếp; Docker Engine vẫn chưa chạy. Native backend không phụ thuộc Docker nên có thể sử dụng ngay. Compose dùng host ports5433/6380 trên máy này để tránh xung đột. Memurai Developer không dùng production, tự dừng sau10 ngày; các giới hạn AI/upload/payment/remote Flutter còn giữ nguyên trong migration-plan.md.

## Private image lifecycle — 2026-10-18

Thêm upload JPEG/PNG riêng tư, validation bytes/pixels, strip metadata, consent, ownership, quota; signed read60s, delete202 và cleanup24h có retry. Worker đồng bộ công bố kết quả với xóa ảnh bằng transaction lock. Migration thứ3 bổ sung metadata, không reset database. MinIO native local chạy trên loopback9000/9001, có bucket test riêng.

Kiểm thử trước final review: unit9, commerce10 + worker9 + upload6 E2E đều đạt; build/lint đạt. Flutter source không thay đổi; provider AI vẫn Disabled. Chi tiết và giới hạn URL/versioning/storage production tại [private-images.md](private-images.md). Docker vẫn chờ Windows hoàn tất repair sau restart.

Sau review: sửa bốn findings bằng regression RED→GREEN; thêm migration thứ4 cho retry cleanup công bằng. Final unit11/E2E27/build/lint/compiled smoke đạt, Flutter live catalog1 đạt. Không còn review finding bị hoãn. Runtime API/worker cũ chưa reload vì execution policy chặn thao tác tiến trình; hướng dẫn chạy bản mới tại setup.md. Không có thay đổi frontend hoặc gọi AI thật.

## Docker restored — 2026-10-18, sau restart20:39

Người dùng xác nhận lưu công việc và cho phép restart. Windows đã áp dụng bản sửa đang pending: vmcompute/hns phục hồi và Running; WSL2 không còn báo lỗi; CBS RebootPending=false. Docker Desktop4.95.0/Engine29.8.2 đã chạy, hello-world pull/run exit0. Compose PostgreSQL17.11 và Redis7 Healthy tại127.0.0.1:5433/6380; SQL query/PONG đạt. Native PostgreSQL/Memurai vẫn Running, không đổi dữ liệu hoặc env. API/worker/MinIO container chưa build/chạy; dev processes cần chạy lại sau reboot. Setup/report đã cập nhật, lỗi Docker về Virtual Machine Platform đã được xử lý.

## Flutter resize / F12 regression — 2026-10-18

Reproduced the reported numeric-to-bool TypeError in Chrome: scroll a product, Stylist or Try-On page, then narrow the viewport as docked DevTools does. Unkeyed ExpansionTiles shared the route's PageStorage identifier with its scroll view; Expansible read the saved numeric scroll offset as a nullable bool when the responsive layout recreated it. Opening a section could also overwrite the scroll offset with a boolean.

Added distinct PageStorageKeys to all six ExpansionTile call sites, including account demo controls and individual FAQ entries. No layout, API or database changes. Five actual-route regression tests failed before the fix and pass afterward, covering fractional scroll offsets, repeated responsive changes and independent expanded state. Full Flutter suite:185 passed,1 live-API test skipped; analyzer clean; Web release build passed. Chrome checks on product, Stylist, Try-On, login and FAQ all pass after scrolling and resizing through1440/600/375px, with no Flutter/browser exceptions. For an existing `flutter run` session, use uppercase `R` to rebuild and clear the old in-memory PageStorage state.

## Flutter API shopping — 2026-10-18

Giữ giao diện Flutter và chế độ demo, thêm USE_REMOTE_API cho đăng ký/login/refresh/logout, profile name/phone, sổ địa chỉ CRUD/default, giỏ SKU, đặt COD, lịch sử phân trang/chi tiết và hủy đơn chờ xác nhận. Cache cá nhân bị loại khi đổi tài khoản; token chỉ ở RAM. Giá/tồn kho do backend kiểm tra; retry checkout giữ nguyên Idempotency-Key/body và không DELETE giỏ sau phản hồi thành công.

Giao diện phân biệt loading/error/empty, dùng địa chỉ UUID đã lưu, hiển thị COD chưa thu tiền và hủy đơn thật. Admin/AI/wishlist/style/reset password chưa nối được chặn với thông báo rõ. Không thay schema hoặc backend. Có lệnh ngắn `./tools/frontend.ps1 api` tại root, frontend port8080 khớp CORS đã cấu hình.

Kiểm chứng:212 Flutter tests đạt,2 live tests opt-in được bỏ qua trong suite thường; analyze không issues. Live shopping chạy riêng qua NestJS/PostgreSQL test DB đạt: profile/address/cart/order tồn tại qua đăng nhập mới, hủy lặp không trả kho hai lần, logout thu hồi phiên. Chrome release đã chạy register/address/cart/COD/cancel/reload-login trên375/1440px và kiểm tra resize kiểu F12 không exception. Helper tạo fixture riêng trong database kết thúc _test và dọn đúng dữ liệu của nó, không reset database phát triển. Có thêm regression RED→GREEN cho catalog public không gửi token hoặc refresh phiên riêng.

Giới hạn: chưa nối Flutter admin, AI/provider thật, wishlist/style/reviews, email/reset password hoặc thanh toán online. Khóa retry checkout chỉ ở RAM: nếu reload/đăng xuất sau lỗi mạng phải xem lịch sử trước khi đặt tiếp. Dữ liệu vẫn lưu trên server; phiên Web cần đăng nhập lại sau reload. Chưa tuyên bố production-ready.

Final review bởi reviewer độc lập phát hiện3 lỗi biên; cả3 đã được tái hiện bằng test thất bại rồi sửa: giữ yêu cầu checkout qua HTTP429, khôi phục đúng người nhận/phí giao/giá trị khi mở lại đơn đang chờ, và tách trạng thái tải cart/history/detail để lỗi giỏ không biến thành giỏ trống sau khi xem đơn. Sửa thêm dòng tài liệu auth cũ. Final suite214 đạt,2 live tests opt-in bỏ qua; analyze sạch; live PostgreSQL shopping đạt lại. Không có finding review còn hoãn. Phiên RAM, native/mobile, chức năng nâng cao và production deployment giữ đúng giới hạn đã nêu.
Chrome release sau các bản sửa cũng đạt toàn bộ hành trình và kiểm tra resize, không Flutter/browser exception. Helper browser chờ đồng bộ ô nhập với Flutter trước khi chuyển focus để thao tác điền tự động ổn định. Các ảnh kiểm chứng ở .tools/api-shopping-verification (ignored).
Lệnh tools/frontend.ps1 build-api cũng được chạy trực tiếp: sửa cách PowerShell5.1 xử lý native stderr khi redirect log, giữ kiểm tra exit code. Web release trỏ backend localhost:3000 build thành công (exit0); frontend runtime api dùng cổng8080 khớp CORS đã xác minh.

## Flutter API administration — 2026-10-18

Đã nối dashboard tổng hợp toàn database, sản phẩm/bộ ảnh/SKU, tồn kho có lý do và expectedVersion, đơn hàng theo bước và danh sách khách hàng. Route yêu cầu ADMIN; cache/provider loại dữ liệu khi đổi tài khoản, mutations không tự retry sau conflict hoặc kết quả chưa rõ. Sản phẩm/SKU ẩn vẫn hiện trong admin; public catalog giữ bộ lọc active. Giao hàng không tự chuyển COD sang PAID. Giữ demo/UI shell và tokens thiết kế hiện có.

Backend thêm GET summary, product/order detail; gallery replacement trong transaction, list có tie-break id. Công cụ cấp quyền local chỉ dùng tài khoản có sẵn và thu hồi phiên cũ. Đã thực hiện theo email người dùng chỉ định. Không tạo mật khẩu mặc định hoặc đổi database của ứng dụng.

Kiểm chứng trước final review: backend lint/build, 11 unit và 15 PostgreSQL E2E đạt (17 integration worker/storage tùy chọn không chạy ở lượt này); Flutter analyze sạch, 224 tests đạt, 2 live opt-in bỏ qua trong suite thường. Chrome release với API/PostgreSQL `_test` đã tạo sản phẩm+ảnh, tạo/sửa SKU, nhập kho, reload/login đọc lại, chuyển đơn đến DELIVERED với COD PENDING, xem khách, logout và chặn CUSTOMER. Kiểm tra giao diện375/1440px không Flutter/browser exception. Dọn đúng fixture của lượt chạy, không reset dữ liệu phát triển.

Phần còn lại: admin audit đầy đủ, quản lý taxonomy bằng UI, uploads catalog, đối soát COD, wishlist/reviews/promotions/style, reset-email và AI/provider/payment thật. Hướng dẫn sử dụng và kiểm thử tại [admin.md](admin.md).

## Separate customer and administrator sign-in — 2026-10-18

Khách hàng đăng nhập tại `/#/login`; quản trị đăng nhập tại `/#/admin/login` với form Studio độc lập. Tách client, token, account và dữ liệu quản trị khỏi phiên mua sắm. ADMIN được dùng cả hai khu vực bằng hai lần đăng nhập riêng; logout/hết phiên một bên giữ bên còn lại. Deep link quản trị chuyển tới form riêng và quay lại đường dẫn an toàn sau xác thực. API `/auth/admin/login` chặn CUSTOMER trước khi tạo phiên; các endpoint quản trị vẫn kiểm tra quyền máy chủ.

Kiểm chứng: 235 Flutter tests đạt (2 live opt-in không chạy trong suite thường), analyzer sạch; backend build/lint, 11 unit và 16 PostgreSQL E2E đạt (17 worker/storage opt-in không chạy). Chrome thật với PostgreSQL `_test` xác nhận hai giao diện, CUSTOMER bị từ chối, hai chiều logout độc lập, safe return path và các thao tác quản trị/sản phẩm/kho/đơn tiếp tục hoạt động. Ảnh desktop1440/mobile375 đã được xem; thêm regression cho viewport1440×400 khi mở DevTools, sửa overflow cột Studio bằng cuộn độc lập. Reload vẫn cần đăng nhập lại vì token chỉ ở RAM.

Final review của giai đoạn Flutter API administration trước đó phát hiện một lỗi mất ảnh khi quản trị viên lưu metadata từ bản cũ. Đã sửa PATCH chỉ gửi trường thay đổi và cập nhật mốc so sánh sau khi lưu thành công. Hai regression đã thất bại trước sửa và đạt sau sửa: giữ thay đổi gallery/chất liệu của người khác và giữ đúng mốc sau lần sửa gallery. Suite tại giai đoạn đó225 đạt,2 opt-in bỏ qua; analyzer sạch. Không có finding Critical/Important/Minor còn tồn đọng. Các giới hạn taxonomy/upload/audit, đối soát COD, native và production giữ nguyên như tài liệu.

## Persistent customer wishlist — 2026-10-18

Đã thêm wishlist API và Flutter thật: trái tim trên catalog/chi tiết, Lưu yêu thích trong giỏ, trang danh sách có phân trang12 mục, trạng thái tải/lỗi/rỗng và sản phẩm không còn mở bán. Dùng phiên khách hàng độc lập; đăng nhập lại lấy dữ liệu PostgreSQL, logout/đổi tài khoản loại cache và phản hồi cũ. ADMIN dùng wishlist bằng phiên mua sắm riêng. Không đổi schema hoặc dependencies.

PUT/DELETE idempotent, khóa theo user bảo đảm quota200 và không tạo trùng khi lưu đồng thời. Sản phẩm hết kho vẫn lưu được; sản phẩm bị ẩn/không còn SKU hoạt động thành placeholder có thể bỏ, không lộ metadata chưa công khai. Mất phản hồi ghi yêu cầu tải lại trước khi đảo trạng thái, và không báo lưu thành công khi một lệnh bỏ đang chờ.

Kiểm chứng: backend19 PostgreSQL E2E đạt (17 worker/storage opt-in bỏ qua), build/lint đạt. Flutter246 tests đạt (2 live opt-in bỏ qua), analyze sạch. Chrome/PostgreSQL thật đã lưu/bỏ từ card, chi tiết, giỏ, xác nhận lưu lặp trong giỏ không bỏ mục; reload/login giữ danh sách; tài khoản thứ hai rỗng; viewport375/600/1440 không exception. Helper `node tools/test-frontend-api.cjs --wishlist` dùng fixture riêng trên database `_test`, dọn đúng dữ liệu lượt chạy. Ảnh/log nằm tại `.tools/api-wishlist-verification` (ignored).

Tiếp theo: đánh giá sản phẩm, danh mục/thương hiệu trong quản trị, audit, promotions/style; email/reset password, AI/provider và payment thật vẫn chưa hoàn tất.

## Quản lý danh mục và thương hiệu — 2026-10-18

Thêm API và hai trang quản trị `/#/admin/categories`, `/#/admin/brands`: phân trang 20 mục, đếm sản phẩm, tạo tên/slug và đổi tên. Slug và liên kết sản phẩm giữ nguyên; đổi tên dùng expectedName để từ chối ghi đè từ form cũ. Tên được trim/giới hạn 100 ký tự, slug trùng trả409, mọi thao tác yêu cầu ADMIN. Không thêm migration hoặc dependency, chưa có xóa taxonomy.

Flutter cập nhật lựa chọn trong biểu mẫu sản phẩm và danh mục công khai ở trang chủ/cửa hàng. API lỗi có trạng thái tải lại, không lấy danh mục demo thay thế. Dialog xử lý validation, xung đột, kết quả chưa rõ và mất phiên quản trị; phiên khách hàng vẫn độc lập.

Kiểm chứng tự động trước review: 21 PostgreSQL E2E, 11 backend unit và 252 Flutter tests đạt; 17 worker/storage và 2 Flutter live tests opt-in được bỏ qua. Backend build/lint đạt, Flutter analyze sạch. Kiểm thử trình duyệt mở rộng dùng `node tools/test-frontend-api.cjs --admin`, chỉ tạo/dọn fixture của lượt chạy trên database `_test`.

Chrome/PostgreSQL thật đạt: tạo và đổi tên cả hai loại, chọn chúng khi tạo sản phẩm, lưu SKU/kho, tải lại và đăng nhập lại vẫn giữ dữ liệu; danh mục công khai lọc đúng sản phẩm. Đã xem ảnh 375/1440 px của danh sách, dialog và cửa hàng; không overflow hoặc exception. Luồng đơn/COD và đăng xuất độc lập ở hai khu vực vẫn đạt. API native đã reload, health ready; release bình thường khôi phục về localhost:3000.

Final review phát hiện cache công khai có thể giữ tên cũ khi đăng xuất trong lúc lưu hoặc đóng dialog sau mất phản hồi. Đã tái hiện hai trường hợp RED và sửa để làm mới cache độc lập với vòng đời trang quản trị; không gửi lại thao tác ghi. Sau sửa: 254 Flutter tests đạt (2 opt-in bỏ qua), không còn finding chưa xử lý. Các trình duyệt khác cần tải lại; expectedName so sánh tên hiện tại, chưa lưu lịch sử đổi tên.

Còn lại: reviews, promotions/style preferences, email/reset password, uploads catalog, audit/đối soát COD, AI/provider và payment thật. Chưa tuyên bố hoàn tất toàn bộ dự án hoặc sẵn sàng production.

## Đánh giá của người mua — 2026-10-19

Đã nối reviews API với Flutter: chỉ khách có đơn DELIVERED chứa sản phẩm được gửi 1–5 sao/nội dung; một đánh giá mỗi tài khoản/sản phẩm, sửa/xóa theo phiên bản timestamp. Người dùng đã chọn hiển thị ngay, không chờ duyệt. GET công khai phân trang kèm điểm trung bình, chỉ tính đánh giá có đơn đã giao, không gửi tên/email/userId hoặc dữ liệu đơn. SKU hết hàng vẫn đánh giá được; sản phẩm ẩn/không còn SKU active không công khai reviews.

Trang sản phẩm có nút Xem đánh giá và khu vực riêng, trạng thái rỗng/lỗi/tải lại, đăng nhập trở về đúng sản phẩm, xác nhận xóa và kiểm tra lại sau phản hồi không rõ. Khách chưa mua không có nút gửi; phiên ADMIN riêng không mở quyền đánh giá của khách. Repository kiểm tra generation/disposal và làm mới cache công khai sau mọi thao tác đã gửi, kể cả mất phiên hoặc mất phản hồi. Không tự gửi lại lệnh ghi.

Kiểm chứng sau sửa cuối: 27 PostgreSQL E2E + 11 unit backend đạt (17 worker/storage opt-in bỏ qua), build/lint đạt; Flutter269 tests đạt (2 live opt-in bỏ qua), analyze sạch và web release build đạt. Index Review(productId,createdAt,id) đã deploy vào PostgreSQL native, không reset dữ liệu. Hướng dẫn và giới hạn tại [reviews.md](reviews.md).

Rà soát cuối đã tái hiện và sửa: nội dung emoji hợp lệ được đếm theo Unicode code point ở cả API/Flutter; phản hồi đến sau timeout tiếp tục làm mới dữ liệu công khai mà không gửi lại lệnh hoặc khôi phục phiên đã thoát; timestamp phiên bản không đúng định dạng máy chủ trả400 trước truy vấn thay vì gây500. Cả bốn kiểm thử hồi quy đều đã quan sát thất bại trước sửa và đạt sau sửa.

Chrome/PostgreSQL thật (`node tools/test-frontend-api.cjs --reviews`) đạt: khách vãng lai và khách chưa mua được phân biệt, người đã nhận hàng gửi/sửa/xóa/viết lại, dữ liệu giữ qua reload, điểm trung bình đổi đúng và chỉ chủ đánh giá có hành động sửa/xóa. Đã xem ảnh giao diện375/1440, không overflow/exception. Helper chỉ dọn fixture riêng trên `_test`; API native đã reload và health ready, giữ nguyên tiến trình Flutter của người dùng.

Còn lại: promotions/style preferences, email/reset password, uploads catalog, audit/đối soát COD, AI/provider/payment thật; đánh giá chưa có ảnh đính kèm, trả lời của cửa hàng hoặc quản lý kiểm duyệt.

## Lịch sử đánh giá cá nhân — 2026-10-19

Theo ưu tiên người dùng chọn, bổ sung **Tài khoản → Đánh giá của tôi** tại `/#/account/reviews`. GET `/users/me/reviews` phân trang theo người dùng đang đăng nhập, hiển thị sản phẩm còn mở bán và quyền sửa theo đơn đã giao. Sản phẩm ẩn/không còn SKU active trở thành nhãn chung, không lộ tên/slug, vẫn xóa được đánh giá của mình. Dữ liệu legacy chưa có đơn đã giao vẫn được xem/xóa trong lịch sử riêng, không mở thêm quyền sửa/công khai.

Flutter dùng lại editor và xác nhận xóa hiện có; tải/lỗi/rỗng, thử lại, phân trang và trở về trang đầu sau thao tác. Logout/đổi tài khoản loại bỏ dữ liệu riêng và chặn phản hồi cũ; mọi revision đánh giá làm mới lịch sử cá nhân. Phiên ADMIN vẫn độc lập. Không thêm dữ liệu demo hoặc dependency.

Kiểm chứng: 29 PostgreSQL E2E +11 backend unit đạt (17 worker/storage opt-in bỏ qua), backend build/lint đạt; 279 Flutter tests đạt (2 live opt-in bỏ qua), analyze sạch. Đã thấy hai lỗi404 trước triển khai API và lỗi thiếu lớp trang/repository trước triển khai Flutter, sau đó đều đạt. Index Review(userId,createdAt,id) đã deploy trên wearly_test và wearly native, không reset dữ liệu.

Chrome/PostgreSQL thật đạt: đi từ tài khoản vào lịch sử, sửa đánh giá và kiểm tra điểm công khai, ẩn đúng sản phẩm fixture rồi xóa từ lịch sử, viết lại, reload/đăng nhập trở về đúng trang, tài khoản khác không thấy nội dung riêng. Đã xem ảnh375/1440 của trang thường và sản phẩm ẩn, không overflow/exception. Harness chỉ tạo/ẩn/khôi phục/dọn fixture của lượt chạy trên `_test`.

Các phần chưa triển khai vẫn gồm promotions/style preferences, khôi phục mật khẩu/email, uploads catalog, audit/đối soát COD, AI/provider/payment thật; ảnh/phản hồi/kiểm duyệt đánh giá là các phần mở rộng riêng. Không đánh dấu toàn bộ dự án đã hoàn tất.

Rà soát cuối sửa một lỗi thông báo: xác nhận xóa không còn hứa có thể viết lại đối với đánh giá của sản phẩm ẩn hoặc legacy chưa đủ điều kiện. Thông báo nêu rõ không thể hoàn tác. Hai kiểm thử giao diện375/1440 đã tái hiện lỗi trước sửa. Phạm vi tiếp tục yêu cầu tải lại ở trình duyệt khác; không tự sửa dữ liệu lịch sử sai định dạng hoặc triển khai ảnh/phản hồi/kiểm duyệt trong đợt này.

## Hồ sơ phong cách lưu thật — 2026-10-19

Mở **Tài khoản → Phong cách của tôi** trong chế độ API. Size, phong cách, màu ưu tiên và ngân sách được lưu theo tài khoản trong PostgreSQL; không mất khi đăng xuất hoặc reload. GET/PUT `/users/me/style` kiểm tra danh tính, giá trị lựa chọn và expectedVersion. Lần lưu đầu/cập nhật đồng thời được tuần tự hóa, bản cũ trả409; GET mặc định không tạo hàng. Bảng StylePreference có userId PK/FK, budget Decimal và version, đã migrate vào DB test/native bằng migration cộng thêm.

Flutter mở lại route phong cách bằng phiên khách hàng, giữ các lựa chọn/bố cục đã có; không còn thông báo lưu demo hay nút AI chưa hoạt động trong chế độ API. Lỗi/xung đột chưa rõ khóa lưu và yêu cầu tải lại; cập nhật baseline phiên bản sau thành công. Late completion sau timeout làm mới cache cùng phiên, không tự gửi lại hoặc đưa dữ liệu tài khoản cũ trở lại. AccountDetails đọc địa chỉ và phong cách, nên kiểm thử luồng checkout hiện có cũng được chạy.

Kiểm chứng tự động:33 PostgreSQL E2E +11backend unit đạt (17worker/storage opt-in bỏ qua), backend lint/build đạt;290Flutter tests đạt (2live opt-in bỏ qua), analyzer sạch. Lỗi thiếu API/model đã được quan sát trước triển khai; lỗi reload giá trị dropdown và giữ thông báo lưu đã được tái hiện/sửa trong kiểm thử giao diện. Xem [style-preferences.md](style-preferences.md) để biết API, cách dùng và giới hạn.

Chrome/PostgreSQL thật đạt: lưu, reload/đăng nhập giữ lựa chọn, lưu lần tiếp theo ở375px, bản cũ bị từ chối409 và tải lại rồi lưu được, tài khoản khác chỉ thấy mặc định. DB xác nhận chính xác các lựa chọn/version4, GET mặc định không tạo hàng và địa chỉ còn nguyên. Đã xem ảnh375/1440; không tràn bố cục hay lỗi Flutter. Kiểm thử mua hàng thật cũng đạt: hồ sơ, địa chỉ, giỏ và lịch sử COD giữ qua đăng nhập. Chỉ dọn fixture trên DB test.

Còn lại: promotions, khôi phục mật khẩu/email, uploads catalog, audit/đối soát COD, AI/provider/payment thật và mở rộng đánh giá. Hồ sơ phong cách hiện chỉ lưu lựa chọn, chưa tự lọc sản phẩm hay tạo gợi ý AI.

Rà soát cuối phát hiện lỗi phong cách có thể làm mất kết quả đọc địa chỉ, chặn checkout hoặc báo lỗi sau khi tạo địa chỉ thành công. Đã tái hiện bằng kiểm thử rồi tách trạng thái lỗi phong cách trong AccountDetails; trang phong cách vẫn báo lỗi và không hiện form mặc định giả. Checkout tiếp tục đặt COD khi riêng endpoint phong cách trả503, địa chỉ đã tạo vẫn được trả về với UUID thật. Sau sửa:292 Flutter tests đạt (2live opt-in bỏ qua), analyzer sạch; live shopping PostgreSQL chạy lại đạt.

Các quyết định sau rà soát: sửa kế hoạch gom lỗi để bảo toàn địa chỉ; thành phần đọc phong cách sau này phải xử lý styleError. AI/suy đoán cơ thể/tự lọc vẫn ngoài phạm vi và chưa cá nhân hóa catalog. Rủi ro cũ khi chính POST địa chỉ mất phản hồi chưa nằm trong sửa này: gửi lại thủ công có thể tạo trùng, cần idempotency/reconciliation riêng. Không còn phát hiện Important/Critical chưa xử lý trong thay đổi này, không có Minor được nêu.

## Tạo địa chỉ an toàn khi thử lại — 19/10/2026

Đã xử lý tiếp rủi ro POST địa chỉ mất phản hồi ở trên: receipt theo user/key và hash nội dung trong cùng transaction, replay không tạo thêm/không ghi đè sửa đổi, tombstone không làm sống lại địa chỉ đã xóa. Flutter giữ mã/nội dung/default của lần tạo trong form, khóa bản nháp chưa rõ kết quả và chỉ thử lại khi người dùng bấm. Lỗi400 cho sửa, thay phiên chặn gửi dữ liệu cũ; demo vẫn dùng được. [Hợp đồng và giới hạn](address-retries.md).

Ba kiểm thử PostgreSQL đã tái hiện lỗi trước sửa, sau đó36E2E +11unit đạt;297 Flutter tests đạt (2live opt-in bỏ qua), analyzer sạch. Live shopping thực sự làm mất phản hồi sau khi POST đã commit, retry ra đúng một địa chỉ rồi hoàn tất kiểm thử giỏ/COD. Migration cộng thêm đã áp dụng DB test và native, không reset dữ liệu. Tiến độ mục tiêu bàn giao tiếp tục cập nhật tại [PROGRESS.md](../PROGRESS.md).

Rà soát cuối bổ sung hồi quy refresh đồng thời với retry: trước sửa retry thứ ba có thể409 do mất snapshot/default ban đầu; sau sửa giữ payload theo mã trong RAM suốt phiên và tránh late invalidation khi create/retry đang chạy. 299 Flutter tests +analyzer đạt, release build và live API/COD chạy lại đạt. Giới hạn RAM tăng theo số yêu cầu trong phiên, không persist bản nháp ra localStorage.

Đã khởi động lại MinIO local bằng helper hiện có và bật cả worker/storage tests: lần đầu52/53 đạt, lỗi helper đọc hash BullMQ cũ rồi getState mới. Sửa helper lấy lại hash sau terminal state, giữ nguyên kiểm tra mã lỗi/secret; lần cuối53/53 E2E đạt với PostgreSQL/Redis/MinIO thật, backend lint đạt. Docker Compose config hợp lệ; Docker engine chưa chạy ở thời điểm kiểm tra, native vẫn hoạt động. Chưa suy rộng các kết quả này thành chứng nhận production hoặc hoàn tất toàn bộ bàn giao.
