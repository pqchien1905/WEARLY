# MASTER PROMPT — FASHION AI COMMERCE: FLUTTER WEB FRONTEND-FIRST + ANTHROPIC FRONTEND-DESIGN

> **Dùng làm chỉ dẫn thực thi cho AI Coding Agent (Claude Code / Cursor / Codex / Agent hỗ trợ Skills).**  
> **Skill bắt buộc:** [`frontend-design`](https://github.com/anthropics/skills/tree/main/skills/frontend-design) của Anthropic.  
> **Tài liệu nghiệp vụ:** `fashion_ai_commerce_agent_spec.md` (nếu có trong workspace).  
> **Mục tiêu:** Hoàn thiện một Flutter Web storefront + trải nghiệm AI + giao diện Admin chuyên nghiệp **trước** khi phát triển Backend NestJS.  
> **Nguyên tắc ưu tiên:** Design System thống nhất → 3 màn hình mẫu xuất sắc → các luồng đầy đủ bằng mock repositories → visual QA → tài liệu kết nối API.

**Lưu ý về skill:** `frontend-design` là hệ thống hướng dẫn tư duy thiết kế và triển khai giao diện, KHÔNG phải bộ component Flutter, KHÔNG có generator `MASTER.md`, và KHÔNG có CLI `search.py`. Agent phải **đọc và áp dụng nội dung SKILL.md đang cài thực sự**, tự tạo Design System và viết code Flutter. Tuyệt đối không chạy lệnh cài/truy vấn của UI UX Pro Max.

---

## 1. VAI TRÒ VÀ NHIỆM VỤ

Bạn là **Principal Product Designer, Senior Flutter Web Engineer, UX Researcher, Design System Architect và Frontend Tech Lead**. Hãy hành động như một đội ngũ thiết kế/sản phẩm cao cấp đang chuẩn bị website thời trang thương mại điện tử có AI để phát hành thực tế, không phải một trang demo ghép nhiều widget.

Hãy **thiết kế và xây dựng code Flutter Web chạy được** cho nền tảng Fashion AI Commerce gồm:

1. Storefront bán quần áo B2C.
2. AI Fashion Stylist tư vấn phong cách và giới thiệu sản phẩm.
3. Virtual Try-On cho khách chọn trang phục, tải ảnh có đồng ý xử lý và xem ảnh mặc thử *mô phỏng*.
4. Admin Dashboard quản lý sản phẩm, biến thể, đơn hàng, nội dung và AI.

**Ưu tiên tuyệt đối:** thiết kế có hệ thống, thẩm mỹ thương hiệu, UX dễ sử dụng, tính nhất quán giữa các trang, responsive, accessibility, cấu trúc dễ bảo trì, và khả năng tích hợp backend sau này. **Không** chạy đua số lượng màn hình để đổi lấy chất lượng thấp.

### Phạm vi PHẢI làm bây giờ

- Phân tích kiến trúc thông tin (IA), hành trình khách hàng (user journey), sitemap và UX flow.
- Sử dụng **Anthropic `frontend-design` skill** để xác lập thiết kế khác biệt; tự tài liệu hóa và quản lý Design System thống nhất.
- Thiết kế các trang chính, component, responsive behavior, trạng thái UI và tương tác.
- Viết **Flutter Web + Dart** thực tế, có thể build và chạy local.
- Xây dựng data models, repository contracts, mock repositories, fixture data rõ ràng.
- Kiểm thử, responsive audit, accessibility audit và tài liệu bàn giao.

### KHÔNG làm bây giờ

- Không tạo NestJS/Express server, PostgreSQL, Prisma, Redis, Redis Queue.
- Không tích hợp API thanh toán, OpenAI, Gemini, FASHN hay dịch vụ thử đồ thật.
- Không yêu cầu API key; tuyệt đối không nhúng API key vào frontend.
- Không huấn luyện AI, không tự nhận AI mock là AI thật, không làm đăng nhập/thanh toán giả thành dịch vụ thật.
- Không đổi frontend sang React/Next.js/Vue hoặc sử dụng HTML/CSS làm ứng dụng chính. **Công nghệ bắt buộc là Flutter Web.**
- Không copy nguyên giao diện của thương hiệu thời trang khác.

Nếu `fashion_ai_commerce_agent_spec.md` tồn tại, đọc kỹ để bảo đảm mô hình sản phẩm, giỏ hàng, biến thể và quy trình AI phù hợp với kế hoạch backend. Nếu xảy ra xung đột về phạm vi triển khai: yêu cầu **frontend-first** của prompt này được ưu tiên.

---

## 2. BẮT BUỘC ÁP DỤNG ANTHROPIC FRONTEND-DESIGN SKILL ĐÚNG BẢN CHẤT

### 2.1. Nguồn và cách kích hoạt

- Nguồn chuẩn: <https://github.com/anthropics/skills/tree/main/skills/frontend-design>.
- Đọc kỹ file `SKILL.md` của skill được cài trong **môi trường Agent đang chạy** trước khi đưa ra phương án hình ảnh. Nếu Agent cung cấp cơ chế skill loading, hãy sử dụng cơ chế đó và tuân thủ chỉ dẫn của skill.
- Xác minh kỹ tên `frontend-design`, đường dẫn và nội dung. Nếu không tìm thấy skill, **báo trung thực rằng skill chưa có**, không được nói đã áp dụng. Có thể đọc nguồn chính thức theo quyền truy cập hiện có; nếu không truy cập được thì dùng yêu cầu thiết kế trong prompt này và ghi chú giới hạn.
- Không giả định skill có lệnh tạo Design System, tra cứu màu, `search.py` hay hỗ trợ riêng cho Flutter. Mọi tài liệu thiết kế dưới đây do Agent **chủ động tạo**.
- Không lén thay stack bằng React, Vue, Next.js hoặc HTML/CSS vì skill có nhắc đến khái niệm frontend web. **Sản phẩm chạy chính thức phải dùng Flutter Web và Dart.**

### 2.2. Quy trình thiết kế theo tinh thần skill — 2 vòng, có kiểm điểm chất lượng

**Vòng A — Định hướng sáng tạo (chưa code hàng loạt)**

1. Đọc nội dung nghiệp vụ, xác định nhóm khách hàng, loại mặt hàng, bối cảnh sử dụng và hành động cốt lõi: khám phá → chọn sản phẩm → mua → AI hỗ trợ khi cần.
2. Viết một creative brief một trang: thương hiệu placeholder, người dùng mục tiêu, ưu tiên kinh doanh, cảm xúc mong muốn, điều cần tránh, những ràng buộc Flutter Web.
3. Phát thảo **2 hướng visual có ý đồ khác nhau** (không làm 2 bộ code), mỗi hướng có: cảm hứng từ thời trang, ảnh, layout hero, lưới nội dung, typography, màu chủ đạo, accent, cách thể hiện AI, và ưu/nhược điểm.
4. Chọn **1 hướng mạnh nhất** bằng các tiêu chí: phù hợp thời trang, dễ mua hàng, khả năng dùng lại ở trang sản phẩm, AI, admin, hiển thị tốt tiếng Việt và mobile.
5. Viết design plan ngắn, có ít nhất: **4–6 màu HEX đặt tên**, **1–2 font có hỗ trợ tiếng Việt và vai trò rõ ràng**, type scale, spacing, grid, layout descriptions, ASCII wireframes cho Home / Catalog / Product Detail, 3–5 nguyên tắc thẩm mỹ riêng.
6. Tự phản biện: nếu có thể áp dụng nguyên thiết kế cho fintech/SaaS/blog bất kỳ thì chưa đủ bản sắc; chỉ rõ **điểm dễ bị đánh giá là UI do AI sinh** và sửa trước khi viết code.

**Vòng B — Triển khai, xem ảnh chụp, tự phê bình, tinh chỉnh**

1. Tạo design tokens và các reusable components.
2. Dựng **3 màn hình chuẩn thị giác** theo thứ tự: Home, Product Listing, Product Detail.
3. Xem screenshot thật của Flutter Web ở desktop và mobile (nếu môi trường hỗ trợ): kiểm tra khoảng trắng, bố cục, crop ảnh, font tiếng Việt, tỉ lệ CTA, mức độ đặc trưng, lỗi overflow và độ tương phản.
4. Viết review gồm `Điều đạt`, `Điều còn generic`, `Điều gây cản trở mua hàng`, `Điều cần sửa`, rồi sửa mã thực tế. Không chỉ tuyên bố "pixel-perfect".
5. Khi các màn hình chuẩn đã đạt quality gate, dùng đúng token và component để triển khai phần còn lại. Không tự tạo thêm một phong cách mới cho chatbot hoặc admin.
6. Lặp visual QA tại các milestone, ưu tiên sửa hệ thống (tokens/components) thay vì chắp vá từng màn hình.

**Nguyên tắc thẩm mỹ được áp dụng bắt buộc**

- Chỉ chọn **một điểm nhấn dễ nhớ** trên mỗi trang; các phần còn lại phải rõ, yên tĩnh và định hướng mua hàng.
- Typography là một phần của nhận diện thương hiệu, không phải chọn font mặc định hoặc chỉ làm heading đậm.
- Hero Home phải nói đúng về thời trang và bộ sưu tập; không lấy thống kê lớn, gradient, thẻ KPI hay dashboard làm hero khi không có lý do.
- Chỉ dùng đường viền, đường chia, nhãn, icon, số thứ tự khi chúng có chức năng thông tin. Tránh "01/02/03" mang tính trang trí hoặc dán nhãn ALL CAPS lên mọi section.
- Tránh mô-típ tạo cảm giác thiết kế hàng loạt: nền kem + serif lớn + accent cam đất vô cớ, SaaS cards bo tròn đồng loạt, shadow mờ ở mọi thứ, accent xanh neon, gradient cho mọi banner, hover tất cả phần tử, animation xuất hiện lặp lại liên tục.
- Motion hỗ trợ hành động (mở bộ lọc, xác nhận thêm giỏ hàng, chuyển ảnh) tốt hơn motion chỉ để khoe hiệu ứng. Tôn trọng reduced-motion.
- Copy tiếng Việt tự nhiên, rõ hành động: “Thêm vào giỏ”, “Xem bảng size”, “Thử đồ (bản demo)”. Trạng thái lỗi nói cụ thể điều xảy ra và cách giải quyết.
- Ưu tiên ảnh thời trang có ngôn ngữ thị giác nhất quán, không dùng ảnh stock ngẫu nhiên hoặc nhầm ảnh AI giả với kết quả Try-On thật.

### 2.3. Quy chuẩn Design System do Agent tự tạo (không nhầm là tính năng sinh file của skill)

Sau khi tự đánh giá hai hướng thiết kế, chốt một hướng và tạo:

```text
design-system/fashion-ai-commerce/
├── BRIEF.md                    # Khách hàng, ý tưởng, mục tiêu và ràng buộc
├── CONCEPTS.md                 # 2 hướng visual và lý do chọn / loại
├── MASTER.md                   # Single source of truth: token, font, grid, motion, imagery
├── DECISIONS.md                # Design decisions, self-critique và ảnh hưởng thay đổi
├── COMPONENTS.md               # Design contracts của các reusable widgets
└── pages/
    ├── home.md
    ├── catalog.md
    ├── product-detail.md
    ├── cart-checkout.md
    ├── ai-stylist.md
    ├── virtual-try-on.md
    └── admin-dashboard.md
```

`MASTER.md` phải quy định tối thiểu:

- Color tokens 4–6 màu HEX chính + semantic success/warning/error/focus, contrast-tested.
- Font gia đình/chữ mẫu tiếng Việt, type scale, weight, line-height, tracking, responsive typography.
- Spacing scale, max content width, grid columns, gutters, section rhythm, image ratios.
- Button, link, input, card, badge, chip, modal, toast, nav, table, loading/empty/error state.
- Hệ icon, border, radius, shadow (hạn chế), elevation, responsive behavior.
- Photography and editorial art direction; cách dùng ảnh campaign vs ảnh catalog.
- Motion rules: thời gian, easing, phản hồi tương tác và reduced-motion.
- UI Writing rules: tone tiếng Việt, CTA, error, tooltip, AI demo disclosures.
- Accessibility: focus, contrast, touch area, keyboard behavior, semantics.
- Những anti-pattern cấm và cách đánh giá màn hình mới.

`MASTER.md` là nguồn chuẩn thiết kế; `pages/*.md` chỉ được ghi khác biệt chức năng/thị giác **có căn cứ**. Chỉnh token phải rà soát các component phụ thuộc. Không tự ý sửa `MASTER.md` khi gặp một trang khó làm rồi gây lệch toàn hệ thống.

**Quality Gate P0:** Không được nhân bản hàng loạt 20+ trang nếu chưa hoàn thiện design plan, ít nhất 3 wireframes, token system, component inventory và nhận diện duy nhất. Không dừng ở lý thuyết: phải có Flutter scaffold + gallery, sau đó triển khai 3 màn hình chuẩn và visual QA.

### 2.4. Diễn giải skill sang Flutter Web

Skill đưa ra các nhận xét về web UI/CSS, nhưng bạn phải **chuyển thành quyết định Flutter phù hợp**:

| Nguyên tắc thiết kế | Triển khai Flutter Web |
|---|---|
| Type scale và font | `TextTheme`, `ThemeExtension`, font assets, responsive styles |
| Layout có ý đồ | `LayoutBuilder`, `ConstrainedBox`, `SliverGrid`, `Wrap`, padding tokens |
| Cơ chế tương tác | `FocusableActionDetector`, InkWell/button semantics, hover/focus/touch |
| Visual hierarchy | Typography, alignment, space, ảnh, emphasis có mục đích |
| Motion có kiểm soát | Widget transitions ngắn, tôn trọng thiết lập giảm chuyển động |
| Accessibility | `Semantics`, Focus traversal, hỗ trợ screen readers theo Flutter Web |
| Điều hướng web | `go_router`, URL/deep-link, browser back/forward, query sync |

Không sao chép mã HTML/CSS/React sang ứng dụng chính. Có thể dùng ASCII wireframes hoặc tài liệu tham khảo tĩnh để kiểm tra ý tưởng, nhưng **deliverable cuối cùng** là Flutter Web thực tế.

---

## 3. HƯỚNG NGHỆ THUẬT VÀ BẢN SẮC THƯƠNG HIỆU

### 3.1. Creative direction ưu tiên để Agent đánh giá (không phải template rập khuôn)

**Contemporary Fashion Gallery × Precision Shopping × Human-Centered AI.**

Thông điệp: trải nghiệm mua quần áo như khám phá một gallery thời trang được biên tập kỹ, nhưng hiệu quả sử dụng giống một cửa hàng thương mại điện tử tốt. Tên thương hiệu và phân khúc chưa chốt, nên phương án này là **hướng thẩm mỹ đề xuất**; Agent phải kiểm tra lại trên brief và tự phản biện trước khi khóa.

Các đặc điểm cần xem xét:

- **Ảnh là trọng tâm:** Campaign photography kích thước lớn, ảnh sản phẩm crop 3:4 thống nhất, bối cảnh thương hiệu rõ ràng. Hero có một bố cục asymmetrical/split-frame đáng nhớ; không nhồi bốn CTA vào cùng một góc.
- **Thiết kế trật tự:** Lưới thương mại rõ, filter đáng tin cậy, thông tin size/giá/tồn kho dễ nhìn. Người mua đạt mục tiêu với ít bước, không phải mò trong trải nghiệm nghệ thuật.
- **Typography hiện đại có dấu ấn:** Ưu tiên font sans được chọn kỹ vì hệ chữ Việt; dùng độ lớn, khoảng thở và độ đậm để tạo khí chất. Nếu dùng font display thứ hai, phải giải thích vì sao và kiểm tra hiển thị tiếng Việt thực tế.
- **Một accent nhận diện:** Có thể thử oxblood/burgundy gợi nhịp thời trang, chỉ dành cho chỗ thật sự cần; không biến toàn bộ sản phẩm thành dashboard đỏ. So sánh tối thiểu một cách phối màu khác trước khi chốt.
- **AI là dịch vụ mặc vừa vặn:** Stylist như "góc tư vấn phối đồ" trong cửa hàng, Try-On như "phòng thử ảo". Thông điệp an toàn, minh bạch; không dùng gradient AI tím-xanh hoặc icon robot vui nhộn nếu lệch brand.
- **Admin khác nhiệm vụ nhưng cùng DNA:** Các bảng quản trị ưu tiên khả năng quét thông tin, trạng thái và thao tác nhanh; typography, spacing, icon vẫn nhận diện cùng thương hiệu.

### 3.2. Palette gợi ý cho vòng đánh giá đầu tiên

**Bộ màu này là một concept seed để nghiên cứu, chưa phải quyết định áp đặt.** Agent phải so sánh concept khác, kiểm tra WCAG, điều chỉnh và ghi trong `CONCEPTS.md` + `MASTER.md`.

| Token tham khảo | HEX | Vai trò |
|---|---|---|
| `canvas` | `#F7F8F7` | Nền sáng mát, sạch, không ngả kem mặc định |
| `surface` | `#FFFFFF` | Card/form hoặc mặt nền thật sự cần tách lớp |
| `ink` | `#181A1C` | Nội dung chính, CTA chính |
| `muted` | `#5F6568` | Nội dung phụ, secondary labels |
| `line` | `#D9DEDD` | Đường ranh có chức năng |
| `brandAccent` | `#733640` | Accent oxblood chọn lọc, không dùng đại trà |

Các màu trạng thái (`success`, `warning`, `danger`, `info`) phải có tên riêng, hoạt động cho text/icon/background, đạt tương phản; không dùng accent làm màu thông báo lỗi. Font body gợi ý `Be Vietnam Pro` hoặc font có đầy đủ glyph tiếng Việt, còn display font do Agent quyết định sau khi so concept. Không chọn font phổ biến chỉ vì tiện; không chọn font lạ mà thiếu dấu.

**Bố cục hero đề xuất để thẩm định:**

```text
Desktop — Home concept (không phải kích thước bắt buộc)
┌────────────────────────────────────────────────────────────┐
│ Brand           Shop  Collections  AI Stylist  Search Cart│
├────────────────────────────────────────────────────────────┤
│                                                        │   │
│  Bộ sưu tập mới                    Editorial campaign   │   │
│  headline ngắn                     photograph  │        │   │
│  mô tả đúng sản phẩm               portrait    │        │   │
│  [Khám phá] [Tư vấn phong cách]     imagery      │        │   │
│                                                        │   │
├────────────────────────────────────────────────────────────┤
│ Featured categories / new arrivals / editorial stories    │
└────────────────────────────────────────────────────────────┘

Mobile — một cột, ưu tiên ảnh sản phẩm + CTA rõ, không nhồi text vào ảnh.
```

Chỉ là gợi ý bố cục. Kết quả cuối cùng phải cân bằng hiệu quả thương mại, cảm xúc thời trang và khả năng tương tác ở mọi viewport.

### 3.3. Brand configuration

Tên thương hiệu chưa chốt. Dùng **placeholder có thể đổi tập trung** trong `BrandConfig` (ví dụ `FASHION STUDIO`, gắn nhãn placeholder), cùng logo, slogan, email, social, chính sách demo. Không hardcode trong widgets. Khi có brand assets thật, chỉ thay config/theme/assets thay vì viết lại nhiều màn hình.

### 3.4. Hình ảnh và nội dung thương hiệu

- Cần có nguyên tắc phân loại: ảnh campaign/lifestyle, ảnh catalogue, ảnh chi tiết chất liệu, ảnh minh họa AI demo.
- Ảnh demo có quyền sử dụng phù hợp hoặc placeholder có định hướng rõ. Ghi nguồn/quyền sử dụng vào `assets/ATTRIBUTION.md` nếu dùng ảnh thật của bên ngoài.
- Không dùng ảnh từ các thương hiệu thời trang khác rồi giả dạng sản phẩm đang bán.
- Giữ chất lượng ảnh, focal point, tỷ lệ 3:4 sản phẩm; optimize asset kích thước theo viewport và fallback khi lỗi.
- Text/nội dung mock tiếng Việt phải cụ thể, hợp lý với sản phẩm quần áo; không có slogan vô nghĩa, đánh giá 5 sao hoặc claim doanh số bịa đặt.
- Không đưa ảnh cá nhân hoặc ảnh thử đồ thật ra public URL trong demo.

---

## 4. INFORMATION ARCHITECTURE, NAVIGATION VÀ ROUTES

Thiết kế sitemap, breadcrumb, global navigation, footer, link và browser back/forward chuẩn web.

### 4.1. Storefront routes

```text
/                              Home
/shop                          Tất cả sản phẩm
/shop/:category                Danh mục
/collections                   Bộ sưu tập
/collections/:slug             Trang bộ sưu tập
/products/:slug                Chi tiết sản phẩm
/search?q=...                  Tìm kiếm + lọc + sort (URL-sync)
/cart                          Giỏ hàng
/checkout                      Checkout demo
/checkout/success              Xác nhận đơn demo
/login                         Đăng nhập demo
/register                      Đăng ký demo
/forgot-password               Quên mật khẩu demo
/account                       Hồ sơ
/account/orders                Lịch sử đơn hàng
/account/orders/:id            Chi tiết đơn
/wishlist                      Yêu thích
/ai-stylist                    AI Fashion Stylist demo
/virtual-try-on                Virtual Try-On demo
/virtual-try-on/:jobId         Trạng thái/kết quả demo
/about                         Giới thiệu thương hiệu
/contact                       Liên hệ
/size-guide                    Hướng dẫn chọn size
/faq                           Câu hỏi thường gặp
/shipping-returns              Giao hàng & đổi trả
/privacy                       Chính sách dữ liệu (copy demo có nhãn)
/404                           Không tìm thấy trang
```

### 4.2. Admin routes

```text
/admin                         Dashboard demo
/admin/products                Danh sách sản phẩm
/admin/products/new            Thêm sản phẩm demo
/admin/products/:id/edit       Chỉnh sửa sản phẩm demo
/admin/inventory               Quản lý biến thể/tồn kho
/admin/orders                  Danh sách đơn hàng
/admin/orders/:id              Chi tiết đơn
/admin/customers               Danh sách khách hàng
/admin/promotions              Khuyến mãi / banner
/admin/content                 Quản trị nội dung
/admin/ai-monitoring           Lượt tư vấn, thử đồ, quota giả lập
/admin/settings                Cài đặt giao diện/dữ liệu demo
```

Admin cần **layout riêng** (sidebar + topbar + bảng dữ liệu tiện dụng), nhưng vẫn dùng cùng core typography/colors/spacing trong Design System. Admin ưu tiên rõ ràng và hiệu quả thao tác, không sao chép layout storefront.

---

## 5. THIẾT KẾ CHI TIẾT CÁC MÀN HÌNH BẮT BUỘC

### A. Home / Landing (ưu tiên số 1)

Phải có:

1. Announcement bar gọn gàng có thể tắt (chính sách vận chuyển / chương trình demo).
2. Header desktop: brand, nav danh mục, search, wishlist, account, cart có badge; sticky có kiểm soát.
3. Header mobile: menu, logo, search, cart; navigation drawer hoạt động.
4. Hero editorial chất lượng cao: ảnh thời trang, headline ngắn, CTA "Khám phá bộ sưu tập", CTA thứ cấp "Tư vấn phong cách với AI".
5. Category entry cards (Áo, Quần, Váy/Đầm, Phụ kiện, ...).
6. New Arrivals / Best Sellers có product card chuẩn.
7. AI Stylist section có mô tả ngắn, gợi ý prompts và CTA vào trải nghiệm.
8. Virtual Try-On section giải thích 3 bước, quyền riêng tư, CTA.
9. Lookbook / editorial story, ưu tiên nội dung sản phẩm.
10. Social proof giả lập có nhãn *minh họa* hoặc dùng lợi ích khách hàng không bịa rating.
11. Newsletter demo (input validation, success demo rõ ràng).
12. Footer nhiều cột: hỗ trợ, chính sách, danh mục, liên hệ, bản quyền.

Không lạm dụng hero carousel, motion quá mức hoặc pop-up ép đăng ký.

### B. Product Listing / Search

- Breadcrumb; title và số lượng kết quả.
- Bộ lọc: danh mục, giá, size, màu, phong cách, trạng thái còn hàng.
- Sort: mới nhất, giá tăng/giảm, phổ biến (mock có logic minh bạch).
- Desktop: sidebar filter; tablet/mobile: filter drawer/bottom sheet rõ ràng.
- Active filter chips, nút Clear all, trạng thái Empty/Loading/Error.
- Grid nhất quán 4 cột desktop rộng, 3/2 cột tablet tùy không gian, 2 cột mobile; 1 cột nếu màn rất hẹp hoặc cần accessibility.
- Product card: ảnh 3:4, tên, giá VNĐ, swatches, badge hạn chế, quick add/wishlist; hover/focus/touch states.
- URL query lưu filter, sort, keyword và hỗ trợ browser back/forward.
- Không tải toàn bộ số lượng lớn vào UI cùng lúc; mock có phân trang/infinite loading hợp lý.

### C. Product Detail (ưu tiên số 1)

- Gallery ảnh lớn + thumbnails, click/keyboard navigation, zoom/lightbox.
- Thông tin sản phẩm: brand, tên, giá, mô tả, chất liệu, hướng dẫn bảo quản.
- Chọn **màu và size** có trạng thái selected, unavailable, disabled; kiểm tra bắt buộc trước add to cart.
- Size guide mở đúng ngữ cảnh; thông báo tồn kho demo; số lượng giới hạn phù hợp.
- CTA chính **Thêm vào giỏ**, CTA thứ cấp **Thử đồ bằng AI**, wishlist.
- Thông tin vận chuyển, đổi trả, accordion chi tiết.
- Tab/section "Phối đồ cùng AI" + sản phẩm tương tự.
- Sticky purchase bar trên mobile nhưng không che nội dung quan trọng.
- Image gallery và product variants dựa trên cùng repository/data models.

### D. Cart & Checkout

**Giỏ hàng:** edit quantity, remove, wishlist, tổng tiền, trống giỏ, feedback khi sản phẩm hết hàng/demo stock changed. Cart mini-drawer và cart full page phải cùng nguồn trạng thái.

**Checkout demo:** thông tin liên hệ, địa chỉ, lựa chọn vận chuyển mock, phương thức thanh toán demo, order summary, validation và bước xác nhận. Số tiền định dạng VNĐ; tổng phải được tính từ mock repository. Không tự công bố thanh toán thật thành công. `Checkout success` phải ghi rõ **"Đơn hàng mô phỏng – chưa thanh toán thật"** nếu chưa tích hợp backend.

### E. Authentication & Account

Trang login, register, forgot password, account/profile, orders list/detail, wishlist. Forms có validation, show/hide password, error/success/loading states, keyboard navigation. Demo authentication state có thể reset được, không giả dạng OAuth hoặc secure session production.

### F. AI Fashion Stylist — trải nghiệm khác biệt

Phải thiết kế như **trợ lý phối đồ tích hợp mua sắm**, không đơn thuần là khung chat generic:

- Welcome state với câu hỏi gợi ý: "Đi làm thanh lịch", "Hẹn hò cuối tuần", "Phối đồ theo ngân sách", "Minimalist".
- Khung chat rõ người dùng/bot, timestamp vừa đủ, ô nhập đa dòng, nút gửi, trạng thái đang trả lời, retry.
- Bảng sản phẩm đề xuất với product cards thật từ mock catalog, hình ảnh/giá/size, CTA xem sản phẩm / lưu / thử đồ.
- Bộ lọc theo ngân sách, phong cách, dịp dùng, màu sắc, size theo nhu cầu, không suy đoán nhạy cảm.
- Desktop có thể dùng 2 pane: chat + recommended looks; mobile chuyển 1 pane có sections/tab hợp lý.
- Mock engine **deterministic**: đọc từ repository để trả về kịch bản theo keyword; không cần model AI thật.
- Mọi phản hồi demo phải có nhãn "Trải nghiệm mô phỏng – chưa kết nối AI".
- Không tạo sản phẩm hoặc giá không có trong mock catalog; tất cả `recommended_product_ids` hợp lệ.
- Empty, pending, timeout giả lập, error và regenerate states.

### G. Virtual Try-On — trải nghiệm quan trọng nhất

Thiết kế một **flow 4 bước** (có thể là wizard hoặc giao diện cùng trang):

1. Chọn sản phẩm/biến thể tương thích.
2. Tải ảnh cá nhân bằng picker/dropzone; xem preview, hướng dẫn góc chụp, giới hạn dung lượng và định dạng.
3. Hiển thị quyền riêng tư + checkbox đồng ý xử lý ảnh trước khi thao tác "Tạo ảnh thử".
4. Mô phỏng job `queued -> processing -> succeeded/failed`, hiển thị progress có ý nghĩa, retry, cancel nếu kịch bản hỗ trợ, before/after comparison, CTA trở lại product/giỏ.

**Quan trọng:** chưa tích hợp AI thật. Kết quả trong bản demo phải có nhãn lớn, dễ thấy: "Ảnh minh họa giao diện – không phải kết quả AI thực tế". Không dùng ảnh người khác như kết quả đã biến đổi từ ảnh khách. Nếu không có cặp trước/sau hợp lệ, hãy hiển thị **mock result placeholder** thay vì bịa phép biến đổi.

Yêu cầu UI: trạng thái permission denied, invalid file, upload cancelled, processing timeout, no result, retry exhausted, deletion success. Không gửi ảnh ra mạng dưới danh nghĩa mock. Có nút xóa ảnh khỏi phiên demo và rõ ràng về những gì được lưu tạm ở client.

### H. Admin dashboard

- Dashboard KPIs và biểu đồ **demo** có nguồn mock data rõ ràng.
- Product CRUD UI: form có preview ảnh, category, description, size/color variant matrix, SKU, giá, tồn kho, publish status.
- Orders table: filter, search, sort, status chip, detail panel, xác nhận demo.
- Inventory table: SKU, size, color, current stock, low stock state.
- Promotions/content mock; AI monitoring (mock requests/status/cost placeholders, không bịa actual provider data).
- Tables responsive với scroll có định hướng / card view mobile, trạng thái empty/invalid/pagination.
- Confirmation dialog cho thao tác phá hủy, toast cho kết quả.

### I. UI states chung

Phải có tất cả: `initial`, `loading`, `skeleton`, `empty`, `error`, `success`, `disabled`, `offline/no network mock`, `permission denied` nơi phù hợp; 404, 403/mock, không có kết quả tìm kiếm, ảnh hỏng, giá trị quá dài, ảnh chưa tải được.

---

## 6. COMPONENT SYSTEM — THIẾT KẾ MỘT LẦN, DÙNG NHIỀU NƠI

Thiết kế component có API nhất quán thay vì viết lặp từng trang:

- `AppScaffold`, `StorefrontHeader`, `AnnouncementBar`, `StorefrontFooter`, `MobileNavDrawer`.
- `AppButton` (primary/secondary/tertiary/destructive, loading, disabled), `AppIconButton`.
- `AppTextField`, `SearchField`, `SelectField`, `Checkbox`, `RadioTile`, `FormError`.
- `ProductCard`, `ProductGrid`, `ProductPrice`, `StockBadge`, `ColorSwatch`, `SizeSelector`, `QuantitySelector`.
- `ProductGallery`, `Breadcrumbs`, `FilterChips`, `FilterSheet`, `SortDropdown`.
- `AppDialog`, `BottomSheet`, `Toast/Feedback`, `EmptyState`, `ErrorState`, `SkeletonCard`, `ImageFallback`.
- `AiChatBubble`, `AiPromptChip`, `AiRecommendationCard`, `OutfitCard`.
- `TryOnStepper`, `ImageUploadDropzone`, `TryOnJobStatus`, `BeforeAfterComparison`.
- `AdminSidebar`, `KpiCard`, `StatusChip`, `DataTable`, `PaginationControls`, `AdminFormField`.

Component phải dùng `ThemeData`, token Dart và các wrapper thống nhất; không hardcode hex/radius/shadow ở nhiều file. Document trạng thái component và variants. Tạo **Component Gallery/Storybook-like route nội bộ** để xem các component và trạng thái khi phát triển (ẩn khỏi navigation production nếu không cần).

---

## 7. RESPONSIVE WEB, ACCESSIBILITY VÀ CHẤT LƯỢNG HIỂN THỊ

**Thiết kế các breakpoint theo nội dung, không chỉ rập khuôn:**

- Small mobile: 320–374px.
- Mobile: khoảng 375–599px.
- Tablet: 600–1023px.
- Desktop: 1024–1439px.
- Wide desktop: từ 1440px.

Đánh giá ở **320, 375, 390, 768, 1024, 1280, 1440 và 1920px**, portrait/landscape nơi hợp lý.

Flutter Web bắt buộc:

- Dùng `LayoutBuilder`, `MediaQuery`, `ConstrainedBox`, `Wrap`, `SliverGrid` và widget responsive phù hợp.
- Không sử dụng kích thước cố định gây overflow; không để `RenderFlex overflowed` ở mọi kích thước kể trên.
- Hỗ trợ browser back/forward, deep link `/products/:slug`, URL state tìm kiếm/lọc.
- Header, filter, modal, form, sticky CTA phù hợp touch và pointer; hover là enhancement chứ không phải cơ chế duy nhất.
- Tôn trọng zoom/text scaling, độ dài tiếng Việt, nhãn dài, keyboard traversal, focus ring và screen-reader semantics nơi Flutter hỗ trợ.
- Nút bấm/tương tác mobile ưu tiên vùng chạm ~44–48px.
- Tương phản hướng WCAG 2.2 AA; không dùng màu làm tín hiệu duy nhất.
- Chuyển động giảm khi hệ thống yêu cầu reduced-motion; tránh auto-play chuyển động không cần thiết.
- Có alt/semantic label cho ảnh sản phẩm và nút icon; loading/error được diễn đạt bằng chữ.
- Không tạo dropdown/dialog gây kẹt focus.

**SEO caveat:** Flutter Web không thay thế đầy đủ SSR/HTML theo nhu cầu SEO catalog. Không tự ý chuyển stack; viết `docs/seo-web-strategy.md` mô tả rủi ro và phương án tối ưu hoặc hybrid/SSR trong giai đoạn sau, chờ quyết định kiến trúc.

---

## 8. KIẾN TRÚC FRONTEND, MOCK DATA VÀ BACKEND-READY CONTRACTS

### 8.1. Tech stack

- Flutter Web + Dart, Material 3 được tùy biến theo Design System; không để visual mặc định Material làm mất nét thương hiệu.
- `flutter_riverpod` cho state management.
- `go_router` cho navigation/deep links.
- `dio` hoặc HTTP adapter để tích hợp API về sau, **nhưng hiện tại mock repos**.
- `freezed`, `json_serializable` nếu phù hợp để sinh typed DTO/models.
- Bộ icons nhất quán (Material Symbols Outlined hoặc icon set có license phù hợp); tránh trộn lẫn nhiều hệ.
- Font có license phù hợp, hỗ trợ tiếng Việt, được quản lý trong asset/theme.

Trước khi thêm package mới phải kiểm tra package còn được duy trì, tương thích Flutter/Dart thực tế và không tạo dependency thừa.

### 8.2. Cấu trúc thư mục đề xuất

```text
fashion-ai-commerce/
├── apps/
│   ├── storefront/
│   │   ├── lib/
│   │   │   ├── main.dart
│   │   │   ├── app/                 # app, router, theme, config
│   │   │   ├── core/                # design tokens, widgets, errors, utils
│   │   │   ├── features/
│   │   │   │   ├── home/
│   │   │   │   ├── catalog/
│   │   │   │   ├── product_detail/
│   │   │   │   ├── search/
│   │   │   │   ├── cart/
│   │   │   │   ├── checkout/
│   │   │   │   ├── auth/
│   │   │   │   ├── account/
│   │   │   │   ├── wishlist/
│   │   │   │   ├── ai_stylist/
│   │   │   │   └── virtual_tryon/
│   │   │   ├── data/
│   │   │   │   ├── fixtures/
│   │   │   │   ├── mock_repositories/
│   │   │   │   └── repositories/    # interfaces, adapters
│   │   │   └── l10n/
│   │   ├── assets/
│   │   ├── test/
│   │   └── integration_test/
│   └── admin/
│       ├── lib/
│       ├── assets/
│       └── test/
├── packages/
│   ├── fashion_design_system/    # shared design tokens/widgets nếu phù hợp
│   └── fashion_domain/           # shared typed models & interfaces
├── design-system/fashion-ai-commerce/
│   ├── MASTER.md
│   ├── DECISIONS.md
│   └── pages/
├── docs/
│   ├── frontend-architecture.md
│   ├── user-flows.md
│   ├── api-contracts-frontend.md
│   ├── responsive-audit.md
│   ├── seo-web-strategy.md
│   ├── frontend-acceptance.md
│   └── visual-qa.md
└── README_FRONTEND.md
```

Nếu repo hiện tại đã tồn tại, **không phá cấu trúc đang ổn**. Đề xuất thay đổi hợp lý, giải thích tradeoff. Có thể gom app và admin thành một codebase có shell/route riêng nếu điều đó giảm đáng kể overhead mà vẫn đảm bảo separation; ghi ADR và giữ design system chung.

### 8.3. Models và repositories cần ổn định

Định nghĩa typed models tối thiểu:

- `Category`, `Collection`, `Product`, `ProductVariant`, `ProductImage`, `Money`, `Price`, `InventoryAvailability`.
- `Cart`, `CartItem`, `CheckoutDraft`, `ShippingMethod`, `Order`, `OrderItem`, `PaymentMethodDemo`.
- `UserProfile`, `Address`, `WishlistItem`.
- `AiMessage`, `AiStylistSession`, `Recommendation`, `OutfitSuggestion`.
- `TryOnJob`, `TryOnStatus`, `ImageAssetReference`, `ConsentState`.

Repository interfaces ví dụ:

```dart
abstract interface class ProductRepository {
  Future<PaginatedProducts> getProducts(ProductQuery query);
  Future<Product?> getProductBySlug(String slug);
  Future<List<Product>> getRecommendations(String productId);
}

abstract interface class TryOnRepository {
  Future<TryOnJob> createDemoJob(TryOnRequest request);
  Future<TryOnJob?> getJob(String jobId);
  Future<void> deleteDemoImage(String imageId);
}
```

`MockProductRepository`, `MockCartRepository`, `MockOrderRepository`, `MockAiStylistRepository`, `MockTryOnRepository` cung cấp dữ liệu từ cùng nguồn. Cấu hình `AppEnvironment.demoMode = true` hoặc `--dart-define=DEMO_MODE=true`; về sau hoán đổi `Remote*Repository` không làm thay màn hình.

**Các quy tắc dữ liệu demo:**

- Ít nhất 30–50 sản phẩm giả lập có phân loại rõ, ảnh phù hợp, giá VNĐ, size, màu, SKU và tồn kho nhất quán.
- Không được có tình huống product card hiện một giá còn giỏ hàng lại tự tính giá khác.
- Không gắn rating hoặc đánh giá giả làm feedback khách hàng thật.
- Dữ liệu mock có thể reset; các action add cart/wishlist/edit sản phẩm trong demo phải tạo hiệu ứng đúng, không phải nút vô tác dụng.
- Không dùng `Future.delayed` phân tán trong widget; tập trung fake latency và lỗi giả lập ở mock service.
- `AI` / `payment` / `try-on` mock phải luôn có nhãn demo rõ ràng, không gửi dữ liệu người dùng đến backend giả.
- Không lưu ảnh người dùng dài hạn vào browser storage. Nếu lưu temporary in-memory, phải xóa được và giải thích rõ.

### 8.4. Chuẩn bị API contract cho NestJS

Tạo `docs/api-contracts-frontend.md` mô tả request/response mong đợi, pagination, filter query, errors, authorization và trạng thái bất đồng bộ cho các endpoint như:

- `GET /v1/products`, `GET /v1/products/:slug`
- `POST /v1/cart/items`, `POST /v1/orders/checkout`
- `POST /v1/ai/stylist/messages`, `GET /v1/recommendations`
- `POST /v1/uploads/presign`, `POST /v1/ai/tryons`, `GET /v1/ai/tryons/:id`

Không tự động xây server, nhưng đảm bảo frontend đã được thiết kế dựa trên contracts có khả năng triển khai thực tế. Mọi xử lý giá/tồn kho cuối cùng sẽ thuộc Backend, UI chỉ hiển thị giá trị nhận được.

---

## 9. INTERACTION REQUIREMENTS — KHÔNG CHẤP NHẬN "UI CHỈ ĐỂ NHÌN"

Các luồng sau **phải hoạt động trong demo mode**:

1. Từ Home → Shop → Filter → Product Detail → chọn size/màu → Cart → Checkout → Demo confirmation.
2. Nhập tìm kiếm → thấy gợi ý → Enter → Search results → lọc/sort → quay lại bằng browser history mà không mất state.
3. Wishlist toggle hoạt động ở product card, product detail và trang wishlist.
4. Tất cả modal, drawer, dropdown, accordion, tabs, carousel (nếu có), toast hoạt động.
5. AI Stylist gửi prompt mẫu → mock reply dựa trên catalog → nhấp sản phẩm → product detail.
6. Product Detail → "Thử đồ bằng AI" → chọn ảnh → consent → fake job → xem status → mock result có nhãn → trở lại sản phẩm.
7. Admin có thể mở form, sửa mock data, validate, xem trạng thái thay đổi khi điều hướng trong phiên demo.
8. Nút thiếu backend phải thông báo đúng "Chức năng mô phỏng" hoặc disabled rõ ràng; **không để CTA vô tác dụng**.

---

## 10. HIỆU SUẤT VÀ KIỂM THỬ

- `flutter analyze` không có lỗi nghiêm trọng; xử lý warning phát sinh bởi code mới.
- `flutter test` chạy được; có unit test cho filter/sort, cart totals, variant selection, fake AI/try-on statuses.
- `flutter build web` hoàn thành với môi trường hiện tại, hoặc báo nguyên nhân khách quan nếu không đủ toolchain.
- Có widget tests cho ProductCard, SizeSelector, CartSummary, AI states, TryOn states.
- Nếu môi trường có Chrome/test automation: test flow mua hàng, tìm kiếm, AI demo và try-on demo.
- Capture screenshots/golden tests tại các viewport tiêu biểu (375, 768, 1024, 1440) khi môi trường hỗ trợ; kiểm tra ảnh, typography, hero, spacing và "generic AI look", đối chiếu với `MASTER.md`; ghi nhận trong `docs/visual-qa.md`.
- Kiểm tra overflow, text wrapping, skeleton/empty/error, slow images, malformed data, keyboard focus, touch target.
- Không đưa phần lớn UI vào một file duy nhất; không có copy-paste token và hardcoded mock data trực tiếp trong widgets.

**Không được tuyên bố "đã chạy/test" nếu chưa thực sự thực hiện.** Nếu môi trường thiếu Flutter, Chrome hoặc network, ghi rõ test nào đã thực hiện và test nào chưa.

---

## 11. QUY TRÌNH THỰC THI BẮT BUỘC — FRONTEND-FIRST THEO MILESTONE

### P0 — Creative Direction & Design System (làm trước tất cả)

1. Đọc tài liệu nghiệp vụ, xem workspace và kiểm tra Flutter/Dart/browser toolchain.
2. Xác minh và **đọc `frontend-design` SKILL.md thực sự**, ghi rõ đã đọc từ đâu; không giả vờ có design CLI.
3. Xây creative brief + 2 concept options gắn với thời trang, chọn 1 và tự phê bình các dấu hiệu thiết kế generic.
4. Vẽ sitemap, user flows, ASCII wireframes Home/Catalog/Product Detail và component inventory.
5. Chốt palette 4–6 màu HEX, fonts tiếng Việt, type scale, responsive layout, spacing, photographic direction.
6. Tạo `BRIEF.md`, `CONCEPTS.md`, `MASTER.md`, `DECISIONS.md`, `COMPONENTS.md`, page guidelines.
7. Xây Flutter Web scaffold với router/theme, mock fixture cơ bản và component gallery.
8. Dựng **ba trang chuẩn thị giác** Home/Catalog/Product Detail; đánh giá screenshot 375, 768, 1440 khi có môi trường, sửa những chỗ generic/khó dùng trước khi nhân rộng.

**Gate:** 3 trang chuẩn đẹp, nhất quán và có tương tác cơ bản; code Flutter có khả năng mở rộng, báo cáo design critique/screenshot. Không được chốt P0 chỉ bằng mô tả đẹp trên giấy.

### P1 — Storefront Core (ưu tiên cao nhất)

1. Home hoàn thiện chất lượng cao.
2. ProductCard, grid, catalog, filters, search.
3. Product Detail, variant picker, gallery, size guide.
4. Cart, Checkout demo, Success page.
5. Hoàn thiện responsive + smoke test end-to-end.

**Gate:** luồng mua hàng demo chạy được trên desktop và mobile; giao diện đạt tiêu chuẩn thẩm mỹ đã chốt, có tự đánh giá hình ảnh thực tế. Sau gate, **không redesign toàn bộ** trừ khi có lỗi nghiêm trọng hoặc chủ dự án yêu cầu.

### P2 — AI UX

1. AI Fashion Stylist với mock prompt + real catalog cards.
2. Virtual Try-On upload/consent/job/result mock, có privacy states.
3. Recommendation widgets xuyên suốt storefront.

**Gate:** luồng AI trọn vẹn, nhãn mô phỏng rõ ràng, không có dữ liệu nhạy cảm rời khỏi trình duyệt trong demo.

### P3 — Account & Admin UI

1. Auth demo, profile, wishlist, orders.
2. Admin dashboard, products, variants, orders, promotions, monitoring.
3. Shared tokens/component variants và role-specific layouts.

**Gate:** admin và storefront đồng nhất ở design DNA nhưng tối ưu khác nhau về thông tin/trải nghiệm.

### P4 — Audit & Handover

1. Fix vấn đề visual hierarchy, spacing, contrast, typo, image crop, responsiveness.
2. Test luồng, forms, keyboard, overflow, failures.
3. Build web và viết hướng dẫn chạy.
4. Chốt model/repository contract để nối NestJS.
5. Xuất checklist nghiệm thu, screenshots và các quyết định mở.

**Trong mỗi milestone:** hoàn thiện, tự đánh giá và báo cáo chính xác phần đã thực hiện cùng file đã tạo; không làm giả kết quả. Tập trung tiến triển thực tế thay vì dừng ở mockup hay pseudo-code. Nếu task quá lớn, chia commits/nhóm màn hình và tiếp tục trong phạm vi cho phép, giữ P0/P1 là ưu tiên.

---

## 12. ĐẦU RA BẮT BUỘC

Hãy bàn giao ít nhất:

1. Project Flutter Web chạy được, storefront và admin rõ ràng.
2. `design-system/fashion-ai-commerce/BRIEF.md`, `CONCEPTS.md`, `MASTER.md`, `DECISIONS.md` và `COMPONENTS.md`.
3. Sitemap, user journeys, responsive rules, component inventory.
4. Shared design tokens/components và component gallery; mỗi component có trạng thái, keyboard/focus semantics và variants.
5. Mock repositories + data models + fixture catalog thực tế và nhất quán.
6. Các trang và luồng demo có tương tác như mô tả.
7. `docs/api-contracts-frontend.md` để giai đoạn Node.js tích hợp tiếp.
8. `README_FRONTEND.md` có hướng dẫn cài, chạy, đổi brand/theme, bật demo, build và vị trí skill đã được sử dụng.
9. `docs/frontend-acceptance.md` đánh dấu Pass/Fail/Not tested cho từng tiêu chí.
10. Ảnh chụp viewport/screenshot, `docs/visual-qa.md` có phê bình và thay đổi sau review; nếu môi trường không hỗ trợ phải ghi giới hạn thực tế.

### Định dạng báo cáo sau mỗi milestone

```text
Milestone:
Đã xây dựng:
Files/Modules quan trọng:
Anthropic frontend-design skill: trạng thái/đường dẫn file đã đọc:
Design concepts đã so sánh + quyết định Design System:
Luồng demo hoạt động:
Tests đã chạy và kết quả:
Screenshot critique + Responsive/Accessibility issues còn lại:
Next tasks:
```

---

## 13. TIÊU CHÍ NGHIỆM THU KHÔNG THỂ BỎ QUA

**DESIGN**
- [ ] Thương hiệu có phong cách premium fashion nhất quán, không mang cảm giác template demo.
- [ ] `frontend-design` skill được đọc và áp dụng thực tế; `BRIEF.md`, `CONCEPTS.md`, `MASTER.md`, `DECISIONS.md` do Agent tự tạo và được áp dụng toàn project.
- [ ] Typography đẹp, rõ, tiếng Việt hiển thị đúng; khoảng trắng/grid/radius/button đều thống nhất.
- [ ] Bộ ảnh đúng định hướng editorial và minh bạch nguồn sử dụng.
- [ ] AI feature thống nhất thẩm mỹ storefront, không trở thành một app hoàn toàn khác.

**FUNCTIONAL UX**
- [ ] Có luồng shopping end-to-end bằng mock thực.
- [ ] Tìm kiếm, lọc, sort, wishlist, variants, cart update chạy được.
- [ ] Checkout mô phỏng, không mạo nhận thanh toán thành công thật.
- [ ] AI Stylist và Virtual Try-On là demo tương tác với trạng thái đầy đủ, nhãn rõ ràng.
- [ ] Form, modal, navigation và validation không có dead action.

**ENGINEERING**
- [ ] Flutter Web/Dart thực sự được sử dụng.
- [ ] Mock data nằm ngoài UI, repositories hoán đổi được.
- [ ] Responsive 320–1920px không có overflow nghiêm trọng.
- [ ] Browser back/deep-link/query state hợp lý.
- [ ] Có tests và log kết quả thật; build được nếu toolchain khả dụng.
- [ ] Không có API key/secret ở frontend; dữ liệu cá nhân không bị upload khi chỉ chạy demo.
- [ ] Có tài liệu kết nối NestJS mà không phải viết lại trang.

**CÁC ĐIỀU TUYỆT ĐỐI TRÁNH**

- Không thiết kế mỗi trang một bảng màu hay mỗi component một kiểu.
- Không có `TODO: build this page` thay cho màn hình cần nghiệm thu của milestone hiện tại.
- Không thêm package animation nặng nếu không cải thiện UX.
- Không dùng ảnh stock bất đồng nhất, emoji thay cho icons, gradient AI tím xanh; không rơi vào các motif mặc định bị skill cảnh báo (nền kem + serif + cam đất, hàng loạt SaaS-card, motion giả trang trí).
- Không tạo "AI result" làm khách tưởng ảnh đã được xử lý thật.
- Không thay đổi stack hoặc triển khai backend trái phạm vi.
- Không nhận mình đã cài/chạy skill/test nếu thực tế không làm được.

---

## 14. YÊU CẦU BẮT ĐẦU NGAY

**Hãy bắt đầu bằng P0 — Creative Direction & Design System**: kiểm tra workspace, đọc tài liệu nghiệp vụ, xác minh và đọc skill `frontend-design` của Anthropic, đưa ra 2 concept khác nhau, tự phê bình concept dễ bị generic, chọn 1 concept có căn cứ. Tự tạo `BRIEF.md`, `CONCEPTS.md`, `MASTER.md`, `DECISIONS.md`, lập sitemap và user flows, dựng Flutter scaffold + component gallery. Dựng Home, Catalog, Product Detail theo cùng Design System, xem ảnh chụp để điều chỉnh rồi mới nhân rộng P1 theo khả năng thực tế.

Khi có điểm chưa được quyết định (tên thương hiệu, logo thật, ảnh sản phẩm, phí ship...), dùng config và mock minh bạch; không tạo quyết định không thể đảo ngược. Mỗi quyết định ảnh hưởng UX phải được tài liệu hóa. Ưu tiên **chất lượng nền tảng trước tốc độ làm nhiều màn hình**.

**Kết quả mong muốn:** một storefront thời trang có thể trình diễn đẹp và thực sự tương tác, một design system đã được chuẩn hóa, và frontend architecture cho phép thay `MockRepository` bằng API NestJS trong giai đoạn sau mà hầu như không phải sửa UI.

---

## 15. QUALITY RUBRIC — ĐÁNH GIÁ CHẶT ĐỂ HẠN CHẾ SỬA LẠI

Trước khi tuyên bố mỗi milestone hoàn tất, hãy chấm theo bảng sau (thang 1–5, có dẫn chứng hình ảnh/code). Mục tiêu tối thiểu **4/5** mỗi tiêu chí của trang đã hoàn thành; nếu thấp hơn, sửa trước khi mở rộng diện tích UI.

| Tiêu chí | Câu hỏi kiểm tra |
|---|---|
| Bản sắc thương hiệu | Nếu xóa logo, UI vẫn có ngôn ngữ thị giác riêng, phù hợp thời trang không? |
| Visual hierarchy | Trong 3 giây đầu, người dùng thấy đúng điểm nhấn và CTA quan trọng nhất không? |
| Typography tiếng Việt | Dấu, line height, wrapping, font rendering có đẹp ở 320px và desktop không? |
| Shopping UX | Khách tìm được size, giá, tồn kho, vận chuyển và thêm giỏ dễ dàng không? |
| Consistency | Header, button, field, product card, modal có đúng tokens và hành vi thống nhất không? |
| AI UX | Chat/try-on liền mạch với storefront và minh bạch trạng thái demo không? |
| Responsive | Mobile, tablet, desktop không overflow; CTA và bộ lọc vẫn dùng được không? |
| Accessibility | Tương phản, labels, bàn phím, focus, semantics và reduced-motion có đạt không? |
| Maintainability | Đổi font/màu/product field/API adapter có thể thực hiện ở lớp đúng mà không sửa 20 trang không? |
| Polish | Ảnh crop, skeleton, hover/focus, empty/error có được chăm chút thật sự không? |

**Visual QA protocol:**

1. Chụp `Home`, `Shop`, `Product Detail` với cùng viewport 375px và 1440px; sau đó chụp AI Stylist, Try-On và Admin khi hoàn thành.
2. Ghi `Điều làm tốt`, `Điều chưa thuyết phục`, `Hướng sửa`, `Ảnh/chứng cứ` trong `docs/visual-qa.md`.
3. Chỉ ưu tiên sửa những yếu tố có tác động lớn (hero, hierarchy, typography, crop, component consistency, CTA) trước tiểu tiết không quan trọng.
4. Sau khi sửa, cập nhật screenshot, bài test và trạng thái checklist. Nếu không có browser/screenshot tool, báo `Not visually verified` thay vì tự nhận đã review bằng mắt.

## 16. TÀI LIỆU NGUỒN VÀ RANH GIỚI CÔNG NGHỆ

- Anthropic skill: <https://github.com/anthropics/skills/tree/main/skills/frontend-design>
- Nội dung skill chính thức: <https://raw.githubusercontent.com/anthropics/skills/main/skills/frontend-design/SKILL.md>
- Flutter Web FAQ/SEO: <https://docs.flutter.dev/platform-integration/web/faq>
- Flutter Web accessibility: <https://docs.flutter.dev/ui/accessibility/web-accessibility>

Không sao chép hoặc giả định một công cụ như design-token generator, CSS framework hay asset generator tồn tại chỉ vì có skill. Nếu skill đưa guideline chung cho web, hãy diễn dịch thành Flutter widgets, routing, assets, semantics và responsive constraints phù hợp với thực tế.
