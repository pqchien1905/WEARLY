# Kiểm tra VNPay sandbox ngày 22/10/2026

Người dùng cung cấp cấu hình và yêu cầu kiểm tra trực tiếp. Đã lưu mã website,
khóa ký và URL trả về local trong `backend/.env` (được Git bỏ qua); không đưa
khóa vào báo cáo, mã nguồn frontend hoặc commit. Những cấu hình khác được giữ
nguyên, chỉ bổ sung origin cửa hàng 8080 vào CORS nếu thiếu.

## Kết quả thực tế

- Dùng `VnpayProvider` hiện có để tạo yêu cầu thanh toán sandbox 10.000 VND,
  tham chiếu kiểm tra riêng. Chrome truy cập đúng cổng sandbox, nhận HTTP 200
  nhưng chuyển đến trang lỗi: **“Website này chưa được phê duyệt”**.
  Mã tra cứu VNPay hiển thị: `HTjalgeXO0`; thời gian: 22/10/2026 18:56:58 (UTC+7).
- Gọi API `querydr` thật bằng cùng cấu hình: HTTP 200, `vnp_ResponseCode=02`,
  `vnp_Message="Website not approved"`. Phản hồi không có chữ ký, vì vậy bộ xác
  minh ứng dụng từ chối chứng nhận giao dịch như thiết kế.
- Không đi đến bước nhập thẻ/OTP; không có thanh toán thành công. Tham chiếu thử
  không tạo đơn hàng hoặc thay đổi dữ liệu thương mại local.

Kết luận: mã website hiện chưa dùng được để thanh toán sandbox vì VNPay báo chưa
phê duyệt. Chưa đủ bằng chứng kết luận khóa checksum hợp lệ hay không: phản hồi
hiện tại bị chặn ở trạng thái website và không có chữ ký để đối chiếu.

Giữ thông tin vừa cung cấp trong `.env`, đặt `VNPAY_ENABLED=false` chờ phê duyệt;
runtime hiện tại vốn tắt VNPay nên không cần khởi động lại. Sau khi VNPay phê
duyệt mã website (hoặc cấp cấu hình sandbox đã duyệt), bật lại, khởi động lại API
và kiểm tra thanh toán/thông báo/truy vấn thực tế. Gemini vẫn là đầu vào riêng.

Bằng chứng riêng tư: `.tools/vnpay-live-check-20261022/checkout-result.json`,
`checkout.png`, `query-result.json`. Thư mục chỉ cấp quyền chủ máy/SYSTEM.
Không lưu khóa trong các kết quả này. Bản cấu hình trước thay đổi cũng được giữ
riêng tư để đối chiếu; không commit thư mục bằng chứng.
