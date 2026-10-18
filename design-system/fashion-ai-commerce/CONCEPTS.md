# Hai hướng thiết kế

## A — Wearly / Tủ đồ đương đại (chọn)

Ảnh campaign chiếm phần lớn hero, khối chữ lệch trái với nền phớt mận. Chữ Be Vietnam Pro ở nội dung, Manrope ở tiêu đề. Nền trắng lạnh, mận trầm chọn lọc. Grid sản phẩm mở, ảnh 3:4, không bọc card trắng có bóng. AI dùng hình ảnh sản phẩm và câu hỏi phối đồ.

```
Desktop Home
┌ logo ───── cửa hàng / bộ sưu tập / stylist ── tìm / thích / giỏ ┐
│     Mặc theo           │                                      │
│     cách bạn.          │       ảnh campaign khổ lớn           │
│     mô tả / CTA        │                                      │
├ danh mục ──────────────┴──────────────────────────────────────┤
│ Mới trong tủ đồ                   [xem bộ sưu tập]             │
│ [ảnh]           [ảnh]           [ảnh]           [ảnh]         │
└ góc stylist / phòng thử / câu chuyện / footer ────────────────┘
```

Ưu: tự nhiên với thời trang; nền yên giúp giá/size rõ; dễ chuyển sang admin. Nhược: phụ thuộc chất lượng ảnh, mận dùng quá nhiều sẽ nặng. Chỉ dùng mận ở CTA và một mảng hero.

## B — Urban Utility / Tủ đồ chuyển động

Xanh thép #244F63, trắng #FFFFFF, ghi #E8EDF0, than #232B30, muted #52636B. Một font sans, headline hẹp, ảnh đường phố và module theo hoàn cảnh đi làm/di chuyển. Hero ảnh ngang, chữ nằm dưới; AI như công cụ xây outfit.

```
┌ logo ───────── nav ───────── actions ┐
│        campaign ảnh ngang           │
├ Tủ đồ chuyển động       [Khám phá] ─┤
│ Đi làm     Cuối tuần      Du lịch    │
└ lưới sản phẩm và outfit builder ─────┘
```

Ưu: dễ mua, gọn mobile. Nhược: dễ giống cửa hàng outdoor; thiên chức năng hơn cảm xúc, ảnh street cần nhiều nguồn đồng bộ.

| Tiêu chí / 5 | A | B |
|---|---:|---:|
| Phù hợp thời trang đương đại | 5 | 4 |
| Mua hàng rõ ràng | 5 | 5 |
| Dùng lại cho AI/admin | 5 | 4 |
| Tiếng Việt/mobile | 5 | 5 |
| Tính khả thi với asset demo | 4 | 3 |

Đây là đánh giá phương án, không phải điểm QA ứng dụng. Chọn A.

## Tự phản biện trước code

Split hero và burgundy có thể thành template nếu ghép badge/stats và serif. Bỏ toàn bộ KPI/eyebrow trang trí, không italic một từ, không gradient AI. Dùng chữ sans lớn, ảnh thật và một bố cục lệch có khoảng thở. Các đường chia chỉ phân cách thông tin hoặc hành động. Product cards không có bóng; radius theo chức năng. Admin dùng cùng màu nhưng khác mật độ.
