# SEO, hosting và performance

Demo dùng Flutter canvas renderer và hash routes, có title/description tiếng Việt, lang=vi, favicon, manifest và loading shell. `noindex,nofollow` cố ý giữ bản thương hiệu/catalog minh họa khỏi công cụ tìm kiếm.

Flutter Web phù hợp ứng dụng tương tác; không coi semantics DOM hoặc metadata tĩnh là thay thế cho HTML sản phẩm có thể index, structured data và social preview riêng từng SKU. Bản hiện tại không SSR, không dynamic OpenGraph/JSON-LD/sitemap sản phẩm. Không tuyên bố đạt SEO ecommerce.

Giai đoạn phát hành: chốt organic search có là nguồn bán hàng quan trọng không; nếu có, nghiên cứu giải pháp phân phối HTML metadata/content ở hosting/backend trong khi giữ Flutter cho trải nghiệm tương tác. Đây là quyết định kiến trúc tiếp theo, không phải đã đổi frontend sang React/Next. Kiểm chứng crawler và deep-link trên hosting thực trước khi bỏ noindex.

Static hosting cần HTTPS, MIME `.wasm`, cache immutable cho asset có fingerprint và revalidate bootstrap/index. Không cache dữ liệu ảnh cá nhân. Build hiện phục vụ CanvasKit từ cùng origin, fonts/images đóng gói local. Không cấu hình service worker/offline cache cho dữ liệu giao dịch; offline trong Admin chỉ là lỗi repository mô phỏng.

Performance thực tế chỉ đã smoke-test trên Chrome local. Chưa đo Core Web Vitals, mạng3G, low-memory phone hoặc Safari. Bảy ảnh demo tổng khoảng1,1MB; renderer và JS có chi phí tải ban đầu. Khi có catalog thật: CDN responsive derivatives, phân trang server, cache có invalidation, lazy image loading, profiling. Không dùng số latency mock làm benchmark backend.

Nguồn: [Flutter web](https://docs.flutter.dev/platform-integration/web), [web initialization](https://docs.flutter.dev/platform-integration/web/initialization), [image codec API](https://api.flutter.dev/flutter/dart-ui/instantiateImageCodec.html). Nguồn thư viện: [Riverpod](https://pub.dev/packages/flutter_riverpod), [go_router](https://pub.dev/packages/go_router), [file_selector](https://pub.dev/packages/file_selector). Phiên bản thực thi nằm trong pubspec.lock và logs QA.
