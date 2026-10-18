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

Final review độc lập phát hiện một lỗi mất ảnh khi quản trị viên lưu metadata từ bản cũ. Đã sửa PATCH chỉ gửi trường thay đổi và cập nhật mốc so sánh sau khi lưu thành công. Hai regression đã thất bại trước sửa và đạt sau sửa: giữ thay đổi gallery/chất liệu của người khác và giữ đúng mốc sau lần sửa gallery. Suite cuối225 đạt,2 opt-in bỏ qua; analyzer sạch. Không có finding Critical/Important/Minor còn tồn đọng. Các giới hạn taxonomy/upload/audit, đối soát COD, native và production giữ nguyên như tài liệu.
