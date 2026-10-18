# Review và regression fixes

Review code độc lập chỉ đọc theo skill `requesting-code-review`, sau khi có storefront/AI/admin. Các phát hiện quan trọng đã được tái hiện bằng failing tests trước khi sửa.

| Phát hiện | Thay đổi | Chứng cứ |
|---|---|---|
| Update quantity dùng index cũ sau await | Resolve lại SKU sau await | `review_regressions_test.dart` |
| Checkout có thể xóa món thêm trong lúc chờ | Lock giỏ, snapshot, kiểm tra lock trước/sau await | Cùng suite |
| Giá có thể đổi giữa validation và trừ kho | consumeStock kiểm tra expectedPrices trong cùng pha mutation | Cùng suite |
| Stylist tính min price ở size khác | Project variants đúng size/color/stock, rồi tính budget | Cùng suite |
| Ảnh cá nhân còn trong Flutter ImageCache | Evict MemoryImage khi thay/xóa/dispose | `privacy_test.dart` |
| Catalog không invalidated nếu rời checkout | Callback trong commerce controller, không dùng WidgetRef sau await | Code + shopping tests |
| Offline switch không phản ánh state mới | Settings watch catalog revision | Chrome recovery audit |

Browser release QA phát hiện riêng: `ImageDescriptor.width` không hỗ trợ web. Đã chuyển sang decoded frame từ `instantiateImageCodec`, dispose frame/codec. Playwright chọn file JPEG thật, chạy lifecycle và xóa ảnh thành công. Widget tests không đủ để phát hiện khác biệt này.

Admin refinement: phân trang sản phẩm/tồn kho, tìm SKU chỉ trả dòng phù hợp, thêm/xóa biến thể màu–size, chặn trùng màu/size. `admin_workflow_test.dart` kiểm tra paging/search reset và lưu biến thể vào cùng repository.

Log red/green của review và admin workflow giữ trong `docs/qa` để có trace. Không coi review này là audit bảo mật production; auth/payment/provider/storage không thuộc bản demo.

## Review phần hoàn thiện 16/10/2026

- Controlled dropdown sửa lỗi chọn hủy đơn rồi “Giữ lại” nhưng nhãn vẫn báo đã hủy.
- AccountRepository + mock async tách form khỏi dữ liệu; kiểm tra sign-out trong lúc sign-in đang chờ.
- Review độc lập phát hiện Riverpod giữ notifier qua invalidate: tăng generation trong build để response cũ không khôi phục hồ sơ sau reset.
- Dialog hủy đơn có thể còn mở sau khi rời trang: kiểm tra mounted trước mutation/log sau await.
- Cả hai phát hiện mới đã được tái hiện (review-final-red.log) rồi sửa (review-final-green.log). Không còn phát hiện quan trọng chưa xử lý trong phạm vi đã review.
- Search heading dùng Expanded, kiểm tra cỡ chữ150% ở375px. Shell semantics boundary giữ header/sidebar trong cây truy cập của trình duyệt.

## Review bổ sung — storefront refinement16/10/2026

Reviewer độc lập rà soát thay đổi catalog/filter/quick add/gallery/support routes/Try-On/Admin cards. Không có critical issue. Important: có thể chạy ảnh cũ khi đọc ảnh thay thế. Đã tái hiện bằng file_selector platform fake với XFile đọc chậm, sau đó khóa run/retry/pick và guard callback theo selectionVersion. Logs tryon-replacement-red/green.

Mobile card8 màu gây overflow đã tái hiện rồi sửa Wrap + preview3swatches/tổng số màu (refinement-review-red/green). Bổ sung kiểm chứng gallery thumbnail/keyboard, result deletion, media giữ qua Admin save và12 route/viewport/text150% cases. Full suite147 pass. Bộ ảnh đúng màu/nhiều góc còn thiếu được ghi rõ, không thay bằng ảnh giả.
